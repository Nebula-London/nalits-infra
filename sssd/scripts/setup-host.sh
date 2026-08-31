#!/bin/bash
# ===========================================
# One-time host setup for SSSD integration
# Run this on the jumpbox/remote server
# Installs packages, configures nsswitch, PAM, sshd
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

# =============================================
# STEP 1: Install host packages
# =============================================
log "Installing host packages..."
apt-get update && apt-get install -y --no-install-recommends \
    libnss-sss \
    libpam-sss \
    libsss-sudo \
    sssd-client \
    autossh \
    || error "Failed to install packages"

# =============================================
# STEP 2: Configure nsswitch.conf
# =============================================
log "Configuring nsswitch.conf..."

# Backup original
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
# STEP 3: Configure PAM
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
# STEP 4: Configure sshd for AD key lookup
# =============================================
log "Configuring sshd..."

SSHD_CONFIG="/etc/ssh/sshd_config"
cp -n "${SSHD_CONFIG}" "${SSHD_CONFIG}.bak" 2>/dev/null || true

# Add AuthorizedKeysCommand if not present
if ! grep -q "AuthorizedKeysCommand" "${SSHD_CONFIG}"; then
    cat >> "${SSHD_CONFIG}" <<'EOF'

# SSSD AD authorized keys lookup
AuthorizedKeysCommand /usr/bin/sss_ssh_authorizedkeys
AuthorizedKeysCommandUser nobody
EOF
fi

# Enable password auth for AD users
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "${SSHD_CONFIG}"

log "Restarting sshd..."
systemctl restart sshd || warn "Could not restart sshd (may need manual restart)"

# =============================================
# STEP 5: Configure sudoers for AD groups
# =============================================
log "Configuring sudoers for root-sssd group..."
cat > /etc/sudoers.d/root-sssd <<'EOF'
# Members of AD group "root-sssd" get full sudo access
%root-sssd ALL=(ALL:ALL) ALL
EOF
chmod 440 /etc/sudoers.d/root-sssd

log "Host setup complete!"
log ""
log "Next steps:"
log "  1. Build and start the SSSD Docker container"
log "  2. Ensure SSSD pipes are available to the host"
log "     If running in Docker, mount /var/lib/sss/pipes from the container"
log "  3. Test: getent passwd Administrator (should return AD user info)"
