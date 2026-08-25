#!/bin/bash
# ===========================================
# Create Test Users in Samba AD
# Run manually after domain is provisioned
# Usage: docker exec rentoption-samba /scripts/create-users.sh
# ===========================================

set -euo pipefail

AD_REALM="${AD_REALM:-SAMBA.INTERNAL}"
AD_DOMAIN="${AD_DOMAIN:-SAMBA.INTERNAL}"
SAMBA_ADMIN_PASS="${SAMBA_ADMIN_PASS:-ChangeMe_SambaAdmin_2024!}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "Creating test users in ${AD_REALM}..."

# Authenticate
echo "${SAMBA_ADMIN_PASS}" | kinit administrator@"${AD_REALM}"

# Create HR group if not exists
samba-tool group add "HR Users" --group-scope=Global --group-type=Security -U administrator --password="${SAMBA_ADMIN_PASS}" 2>/dev/null || true

# Create test users
declare -A USERS=(
    ["hr.admin"]="HR Admin User"
    ["john.doe"]="John Doe"
    ["jane.smith"]="Jane Smith"
    ["bob.wilson"]="Bob Wilson"
    ["alice.brown"]="Alice Brown"
)

for USERNAME in "${!USERS[@]}"; do
    DISPLAY_NAME="${USERS[$USERNAME]}"
    FIRST_NAME=$(echo "$DISPLAY_NAME" | cut -d' ' -f1)
    LAST_NAME=$(echo "$DISPLAY_NAME" | cut -d' ' -f2-)
    EMAIL="${USERNAME}@${AD_DOMAIN,,}"
    PASSWORD="TempPass123!"
    
    log "Creating user: ${USERNAME} (${DISPLAY_NAME})"
    
    samba-tool user create "${USERNAME}" "${PASSWORD}" \
        --given-name="${FIRST_NAME}" \
        --surname="${LAST_NAME}" \
        --mail="${EMAIL}" \
        --userou="CN=Users" \
        -U administrator --password="${SAMBA_ADMIN_PASS}" 2>/dev/null || log "User ${USERNAME} may already exist"
    
    # Add to HR Users group
    samba-tool group addmembers "HR Users" "${USERNAME}" -U administrator --password="${SAMBA_ADMIN_PASS}" 2>/dev/null || true
    
    # Set password never expires (for testing)
    samba-tool user setexpiry "${USERNAME}" --noexpiry -U administrator --password="${SAMBA_ADMIN_PASS}" 2>/dev/null || true
done

# Create additional service accounts
log "Creating service accounts..."
samba-tool user create "jenkins" "JenkinsSvc2024!" \
    --given-name="Jenkins" --surname="CI" \
    --mail="jenkins@${AD_DOMAIN,,}" \
    --userou="CN=Users" \
    -U administrator --password="${SAMBA_ADMIN_PASS}" 2>/dev/null || true

samba-tool group addmembers "Service Accounts" "jenkins" -U administrator --password="${SAMBA_ADMIN_PASS}" 2>/dev/null || true

# List all users
log "Current users in domain:"
samba-tool user list -U administrator --password="${SAMBA_ADMIN_PASS}"

log "Test users created successfully!"
log "Default password for all users: TempPass123!"
log "Please change passwords on first login."