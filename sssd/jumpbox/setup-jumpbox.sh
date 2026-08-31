#!/bin/bash
# ===========================================
# Jumpbox SSSD Setup - Native Install
# One-time script to configure SSSD on the jumpbox
# Connects directly to Samba AD on the main server
#
# Usage:
#   MAIN_SERVER_IP=145.241.221.212 SAMBA_ADMIN_PASSWORD=ChangeMe_SambaAdmin_2024! ./setup-jumpbox.sh
# ===========================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"; exit 1; }

if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
fi

MAIN_SERVER_IP="${MAIN_SERVER_IP:?Set MAIN_SERVER_IP (e.g. 145.241.221.212)}"
SAMBA_ADMIN_PASSWORD="${SAMBA_ADMIN_PASSWORD:?Set SAMBA_ADMIN_PASSWORD}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# =============================================
# STEP 1: Install packages
# =============================================
log "Installing SSSD and dependencies..."
apt-get update && apt-get install -y --no-install-recommends \
    sssd \
    sssd-ldap \
    sssd-krb5 \
    sssd-tools \
    libnss-sss \
    libpam-sss \
    libsss-sudo \
    libpam-mkhomedir \
    krb5-user \
    krb5-config \
    ldap-utils \
    dnsutils \
    || error "Failed to install packages"

# =============================================
# STEP 2: Configure SSSD
# =============================================
log "Configuring SSSD..."

# Generate sssd.conf from template
cat > /etc/sssd/sssd.conf <<EOF
[sssd]
domains = rentoption.local
config_file_version = 2
services = nss, pam, sudo

[nss]
filter_users = root, daemon, bin, sys, sync, games, man, lp, mail, news, uucp, proxy, www-data, backup, list, irc, gnats, systemd-network, systemd-resolve, systemd-timesync, systemd-journal, syslog, messagebus, tss, sshd, statd, ntp, cups, avahi, winbindd
filter_groups = root, daemon, bin, sys, adm, tty, disk, audio, video, plugdev, users, netdev, staff, sambashare

[pam]
debug_level = 0

[sudo]

[domain/rentoption.local]
id_provider = ldap
auth_provider = krb5
chpass_provider = krb5
access_provider = permit

ldap_schema = ad
ldap_id_mapping = True
ldap_referrals = false
ldap_uri = ldaps://${MAIN_SERVER_IP}:636
ldap_search_base = DC=rentoption,DC=local
ldap_tls_reqcert = never
ldap_default_bind_dn = CN=Administrator,CN=Users,DC=rentoption,DC=local
ldap_default_authtok_type = password
ldap_default_authtok = ${SAMBA_ADMIN_PASSWORD}

ldap_user_search_base = CN=Users,DC=rentoption,DC=local
ldap_user_object_class = user
ldap_user_name = sAMAccountName
ldap_user_home_directory = unixHomeDirectory
ldap_user_principal = userPrincipalName
ldap_group_search_base = DC=rentoption,DC=local
ldap_group_object_class = group
ldap_group_name = cn

krb5_server = ${MAIN_SERVER_IP}:88
krb5_realm = RENTOPTION.LOCAL
krb5_canonicalize = false

use_fully_qualified_names = False
fallback_homedir = /home/%u
default_shell = /bin/bash

cache_credentials = True
enumerate = False
ldap_use_tokengroups = True
EOF

chmod 600 /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf
log "SSSD config written to /etc/sssd/sssd.conf"

# =============================================
# STEP 3: Configure Kerberos
# =============================================
log "Configuring Kerberos..."

cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = RENTOPTION.LOCAL
    dns_lookup_realm = false
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false
    default_ccache_name = KEYRING:persistent:%{uid}

[realms]
    RENTOPTION.LOCAL = {
        kdc = ${MAIN_SERVER_IP}:88
        admin_server = ${MAIN_SERVER_IP}
        default_domain = rentoption.local
    }

[domain_realm]
    .rentoption.local = RENTOPTION.LOCAL
    rentoption.local = RENTOPTION.LOCAL

[logging]
    default = FILE:/var/log/krb5libs.log
EOF

log "Kerberos config written to /etc/krb5.conf"

# =============================================
# STEP 4: Configure nsswitch.conf
# =============================================
log "Configuring nsswitch.conf..."

cp -n /etc/nsswitch.conf /etc/nsswitch.conf.bak 2>/dev/null || true

cat > /etc/nsswitch.conf <<'EOF'
passwd:         compat sss
group:          compat sss
shadow:         compat sss
gshadow:        files
hosts:          files dns
networks:       files
protocols:      db files
services:       db files sss
ethers:         db files
rpc:            db files
netgroup:       nis sss
sudoers:        files sss
EOF

# =============================================
# STEP 5: Configure PAM
# =============================================
log "Configuring PAM..."

cat > /etc/pam.d/common-auth <<'EOF'
#%PAM-1.0
auth    [success=2 default=ignore]      pam_unix.so nullok try_first_pass
auth    [success=1 default=ignore]      pam_sss.so use_first_pass
auth    requisite                       pam_deny.so
auth    required                        pam_permit.so
EOF

cat > /etc/pam.d/common-session <<'EOF'
#%PAM-1.0
session required                        pam_mkhomedir.so skel=/etc/skel umask=0077
session required                        pam_permit.so
EOF

# =============================================
# STEP 6: Configure sshd
# =============================================
log "Configuring sshd..."

SSHD_CONFIG="/etc/ssh/sshd_config"
cp -n "${SSHD_CONFIG}" "${SSHD_CONFIG}.bak" 2>/dev/null || true

if ! grep -q "AuthorizedKeysCommand" "${SSHD_CONFIG}"; then
    cat >> "${SSHD_CONFIG}" <<'EOF'

# SSSD AD authorized keys lookup
AuthorizedKeysCommand /usr/bin/sss_ssh_authorizedkeys
AuthorizedKeysCommandUser nobody
EOF
fi

sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "${SSHD_CONFIG}"

# =============================================
# STEP 7: Configure sudoers
# =============================================
log "Configuring sudoers for root-sssd group..."

cat > /etc/sudoers.d/root-sssd <<'EOF'
%root-sssd ALL=(ALL:ALL) ALL
EOF
chmod 440 /etc/sudoers.d/root-sssd

# =============================================
# STEP 8: Clear cache and start SSSD
# =============================================
log "Clearing SSSD cache..."
rm -f /var/run/sssd.pid
rm -rf /var/lib/sss/db/*.ldb /var/lib/sss/mc/*
rm -f /var/lib/sss/pipes/nss /var/lib/sss/pipes/pam
rm -f /var/lib/sss/pipes/private/sbus-*

log "Starting SSSD..."
systemctl stop sssd 2>/dev/null || true
systemctl start sssd
systemctl enable sssd

# Wait for SSSD to initialize
sleep 3

# =============================================
# STEP 9: Test
# =============================================
log "Testing AD user resolution..."
if getent passwd testuser >/dev/null 2>&1; then
    log "SUCCESS: testuser resolved via SSSD"
    getent passwd testuser
else
    warn "testuser not resolved yet. Checking SSSD logs..."
    sss_cache -E 2>/dev/null || true
    sleep 2
    if getent passwd testuser >/dev/null 2>&1; then
        log "SUCCESS: testuser resolved after cache clear"
        getent passwd testuser
    else
        warn "testuser still not resolved. Check: journalctl -u sssd"
    fi
fi

log "Testing group resolution..."
if getent group non-root-sssd >/dev/null 2>&1; then
    log "SUCCESS: non-root-sssd group resolved"
    getent group non-root-sssd
else
    warn "non-root-sssd group not resolved"
fi

log ""
log "=========================================="
log "Jumpbox SSSD setup complete!"
log "=========================================="
log ""
log "Test SSH login:"
log "  ssh testuser@localhost"
log "  Password: TestUser123!"
log ""
log "Test sudo (should FAIL for non-root-sssd):"
log "  sudo -l -U testuser"
log ""
log "View SSSD logs:"
log "  journalctl -u sssd -f"
log "  cat /var/log/sssd/sssd_rentoption.local.log"
log ""
log "Restart SSSD after config changes:"
log "  systemctl restart sssd && sss_cache -E"
