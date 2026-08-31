#!/bin/bash
# ===========================================
# Remote Server SSSD Setup - through Jumpbox SSH tunnel
# One-time script for a server with NO internet access (private IP only)
#
# Architecture:
#   Remote server (no internet) -> SSH tunnel -> Jumpbox -> Main server (Samba AD)
#   SSSD on remote points to localhost; autossh forwards the ports through jumpbox
#
# Requirements:
#   - Jumpbox already has SSSD running (see sssd/jumpbox/setup-jumpbox.sh)
#   - Remote can SSH to jumpbox (outbound only, no inbound ports needed)
#   - SSH key auth from remote -> jumpbox is set up (recommended, no passwords)
#
# Usage:
#   JUMPBOX_HOST=<jumpbox-ip> JUMPBOX_USER=<user> \
#   MAIN_SERVER_IP=<main-server-ip> \
#   SAMBA_ADMIN_PASSWORD=ChangeMe_SambaAdmin_2024! ./setup-remote.sh
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

JUMPBOX_HOST="${JUMPBOX_HOST:?Set JUMPBOX_HOST (jumpbox reachable from this remote)}"
JUMPBOX_USER="${JUMPBOX_USER:?Set JUMPBOX_USER (ssh user on jumpbox)}"
MAIN_SERVER_IP="${MAIN_SERVER_IP:?Set MAIN_SERVER_IP (main server reachable FROM THE JUMPBOX)}"
SAMBA_ADMIN_PASSWORD="${SAMBA_ADMIN_PASSWORD:?Set SAMBA_ADMIN_PASSWORD}"

# SSSD on the remote always uses the tunnel endpoints on localhost
LDAP_URI="ldaps://127.0.0.1:636"
KRB5_SERVER="127.0.0.1:88"

# =============================================
# STEP 1: Install packages
# =============================================
log "Installing SSSD, autossh and dependencies..."
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
    autossh \
    openssh-client \
    || error "Failed to install packages"

# =============================================
# STEP 2: Set up SSH key auth to jumpbox
# =============================================
log "Setting up SSH key authentication to jumpbox..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [[ ! -f /root/.ssh/id_ed25519 ]]; then
    ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519 -q
    log "Generated SSH key. Add this PUBLIC KEY to ${JUMPBOX_USER}@${JUMPBOX_HOST}:/root/.ssh/authorized_keys:"
    cat /root/.ssh/id_ed25519.pub
    warn "Run the following on the jumpbox, then re-run this script:"
    warn "  echo '<key>' >> ${JUMPBOX_USER}@${JUMPBOX_HOST}:/root/.ssh/authorized_keys  # (as JUMPBOX_USER)"
    exit 1
fi

log "Testing SSH connection to jumpbox..."
if ! timeout 15 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
    "${JUMPBOX_USER}@${JUMPBOX_HOST}" "echo connected" >/dev/null 2>&1; then
    error "Cannot SSH to jumpbox. Ensure key auth is set up (key in ${JUMPBOX_USER}@${JUMPBOX_HOST}:/root/.ssh/authorized_keys)"
fi
log "SSH connection to jumpbox OK"

# =============================================
# STEP 3: Configure autossh tunnel (systemd service)
# =============================================
log "Creating autossh tunnel systemd service..."

cat > /etc/systemd/system/autossh-tunnel.service <<EOF
[Unit]
Description=SSH tunnel for SSSD AD connectivity via jumpbox
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# Forward Samba AD ports from localhost through jumpbox to the main server.
# The 'MAIN_SERVER_IP' is resolved FROM THE JUMPBOX (the SSH client side).
ExecStart=/usr/bin/autossh -M 0 -N \\
    -o "StrictHostKeyChecking=no" \\
    -o "UserKnownHostsFile=/dev/null" \\
    -o "BatchMode=yes" \\
    -o "ServerAliveInterval 15" \\
    -o "ServerAliveCountMax 3" \\
    -o "ExitOnForwardFailure yes" \\
    -i /root/.ssh/id_ed25519 \\
    -L 636:${MAIN_SERVER_IP}:636 \\
    -L 389:${MAIN_SERVER_IP}:389 \\
    -L 88:${MAIN_SERVER_IP}:88 \\
    ${JUMPBOX_USER}@${JUMPBOX_HOST}

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable autossh-tunnel
systemctl restart autossh-tunnel

# =============================================
# STEP 4: Wait for tunnel and verify
# =============================================
log "Waiting for tunnel to establish..."
sleep 8

for port in 389 636 88; do
    if (echo > /dev/tcp/127.0.0.1/${port}) 2>/dev/null; then
        log "Tunnel OK - localhost:${port} reachable"
    else
        warn "localhost:${port} NOT reachable yet. Check: journalctl -u autossh-tunnel"
    fi
done

# =============================================
# STEP 5: Configure SSSD
# =============================================
log "Configuring SSSD..."

mkdir -p /etc/sssd
cat > /etc/sssd/sssd.conf <<EOF
[sssd]
domains = rentoption.local
config_file_version = 2
services = nss, pam, sudo

[nss]
filter_users = root, daemon, bin, sys, sync, games, man, lp, mail, news, uucp, proxy, www-data, backup, list, irc, gnats, systemd-network, systemd-resolve, systemd-timesync, systemd-journal, syslog, messagebus, tss, sshd, statd, ntp, cups, avahi, winbindd
filter_groups = root, daemon, bin, sys, adm, tty, disk, audio, video, plugdev, users, netdev, staff, sambashare

[pam]

[sudo]

[domain/rentoption.local]
id_provider = ldap
auth_provider = krb5
chpass_provider = krb5
access_provider = permit

ldap_schema = ad
ldap_id_mapping = True
ldap_referrals = false
ldap_uri = ${LDAP_URI}
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

krb5_server = ${KRB5_SERVER}
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
log "SSSD config written to /etc/sssd/sssd.conf"

# =============================================
# STEP 6: Configure Kerberos
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
        kdc = ${KRB5_SERVER}
        admin_server = 127.0.0.1
        default_domain = rentoption.local
    }

[domain_realm]
    .rentoption.local = RENTOPTION.LOCAL
    rentoption.local = RENTOPTION.LOCAL

[logging]
    default = FILE:/var/log/krb5libs.log
EOF

# =============================================
# STEP 7: Configure nsswitch.conf
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
# STEP 8: Configure PAM
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
# STEP 9: Configure sshd
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
# STEP 10: Configure sudoers
# =============================================
log "Configuring sudoers for root-sssd group..."

cat > /etc/sudoers.d/root-sssd <<'EOF'
%root-sssd ALL=(ALL:ALL) ALL
EOF
chmod 440 /etc/sudoers.d/root-sssd

# =============================================
# STEP 11: Clear cache and start SSSD
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

sleep 3

# =============================================
# STEP 12: Test
# =============================================
log "Testing AD user resolution through tunnel..."
if getent passwd testuser >/dev/null 2>&1; then
    log "SUCCESS: testuser resolved via tunnel"
    getent passwd testuser
else
    warn "testuser not resolved yet. Checking SSSD logs..."
    sss_cache -E 2>/dev/null || true
    sleep 2
    if getent passwd testuser >/dev/null 2>&1; then
        log "SUCCESS: testuser resolved after cache clear"
        getent passwd testuser
    else
        warn "testuser still not resolved. Check:"
        warn "  journalctl -u autossh-tunnel -f"
        warn "  journalctl -u sssd -f"
        warn "  cat /var/log/sssd/sssd_rentoption.local.log"
    fi
fi

log ""
log "=========================================="
log "Remote server SSSD setup complete!"
log "=========================================="
log ""
log "Tunnel service:  systemctl status autossh-tunnel"
log "SSSD service:    systemctl status sssd"
log ""
log "Test SSH login:  ssh testuser@<this-server>  (password: <AD password>)"
log ""
log "To verify tunnel first:"
log "  ss -tlnp | grep -E ':(389|636|88)'"
