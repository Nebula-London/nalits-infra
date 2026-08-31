#!/bin/bash
# ===========================================
# Create a user in Samba AD and sync to Keycloak
# Usage: docker exec rentoption-samba /scripts/create-user.sh <username> [options]
# ===========================================

set -euo pipefail

# --- Defaults ---
KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak:8080}"
KC_ADMIN_USER="${KC_ADMIN_USER:-admin}"
KC_ADMIN_PASS="${KC_ADMIN_PASS:-ChangeMe_KeycloakAdmin_2024!}"
LDAP_PROVIDER_ID="${LDAP_PROVIDER_ID:-eJ2zucVTQn2l-oOKzMPXpw}"
KC_REALM="${KC_REALM:-rentoption.com}"
SAMBA_ADMIN_PASS="${SAMBA_ADMIN_PASS:-ChangeMe_SambaAdmin_2024!}"

FIRST_NAME=""
LAST_NAME=""
EMAIL=""
PASSWORD="ChangeMe_2024!"
USERNAME=""

usage() {
    echo "Usage: $0 <username> [options]"
    echo ""
    echo "Required:"
    echo "  <username>              Username (positional)"
    echo ""
    echo "Options:"
    echo "  -f, --first-name NAME   First name (default: same as username)"
    echo "  -l, --last-name NAME    Last name (default: User)"
    echo "  -e, --email EMAIL       Email (default: username@rentoption.com)"
    echo "  -p, --password PASS     Password (default: ChangeMe_2024!)"
    echo "  -h, --help              Show this help"
    exit 1
}

# --- Parse args ---
if [[ $# -lt 1 ]]; then
    usage
fi

USERNAME="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--first-name) FIRST_NAME="$2"; shift 2 ;;
        -l|--last-name) LAST_NAME="$2"; shift 2 ;;
        -e|--email) EMAIL="$2"; shift 2 ;;
        -p|--password) PASSWORD="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Set defaults
FIRST_NAME="${FIRST_NAME:-$USERNAME}"
LAST_NAME="${LAST_NAME:-User}"
EMAIL="${EMAIL:-${USERNAME}@rentoption.com}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Create user in Samba AD ---
log "Creating user '${USERNAME}' (${FIRST_NAME} ${LAST_NAME}) in Samba AD..."

if echo -e "${PASSWORD}\n${PASSWORD}" | samba-tool user create "${USERNAME}" \
    --given-name="${FIRST_NAME}" \
    --surname="${LAST_NAME}" \
    --mail-address="${EMAIL}" \
    --use-username-as-cn \
    -U administrator --password="${SAMBA_ADMIN_PASS}" 2>/dev/null; then
    log "User '${USERNAME}' created in Samba AD."
else
    log "ERROR: Failed to create user '${USERNAME}' in Samba AD."
    exit 1
fi

# Set password to never expire
samba-tool user setexpiry "${USERNAME}" --noexpiry -U administrator --password="${SAMBA_ADMIN_PASS}" 2>/dev/null || true

# --- Trigger Keycloak LDAP sync ---
log "Triggering Keycloak LDAP Full Sync..."

TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" \
    -d "username=${KC_ADMIN_USER}" \
    -d "password=${KC_ADMIN_PASS}" \
    -d "grant_type=password" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null)

if [[ -z "$TOKEN" ]]; then
    log "WARNING: Could not get Keycloak admin token. Skipping sync."
    log "User '${USERNAME}' created in AD but not synced to Keycloak."
    exit 0
fi

SYNC_RESULT=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${KC_REALM}/user-storage/${LDAP_PROVIDER_ID}/sync?action=triggerFullSync" \
    -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)

log "Sync triggered. Waiting for user to appear in Keycloak..."

KC_FOUND=0
for i in $(seq 1 10); do
    sleep 3
    KC_USER=$(curl -s "${KEYCLOAK_URL}/admin/realms/${KC_REALM}/users?username=${USERNAME}&exact=true" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)
    KC_USER_COUNT=$(echo "$KC_USER" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo "0")
    if [[ "$KC_USER_COUNT" -gt 0 ]]; then
        KC_FOUND=1
        break
    fi
    log "  Waiting... (attempt $i/10)"
done

if [[ "$KC_FOUND" -eq 1 ]]; then
    log "User '${USERNAME}' found in Keycloak."
    echo "$KC_USER" | python3 -c "
import sys,json
u = json.load(sys.stdin)[0]
print('  Username:   ', u.get('username',''))
print('  First Name: ', u.get('firstName',''))
print('  Last Name:  ', u.get('lastName',''))
print('  Email:      ', u.get('email',''))
print('  Enabled:    ', u.get('enabled',''))
"
else
    log "WARNING: User '${USERNAME}' not visible in Keycloak after sync. Try manual sync."
fi

log "Done. Password: ${PASSWORD}"
