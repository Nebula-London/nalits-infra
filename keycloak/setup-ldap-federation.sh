#!/bin/bash
# ===========================================
# Setup Keycloak LDAP Federation with Samba AD
# Host-run, idempotent. Creates federation + attribute mappers via REST API,
# then triggers a Full Sync.
#
# Usage (from host):
#   ./keycloak/setup-ldap-federation.sh
#
# Why not a group mapper? The group-ldap-mapper breaks KC26 user sync
# (GroupsMultipleParents / NPE). It is excluded here on purpose.
# See README "Adding AD Group -> Keycloak Group sync" for the manual opt-in.
# ===========================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

# Load relevant vars from .env if present (do NOT source whole file - values
# like KC_DB_URL contain parens/quotes that break `source`).
# NOTE: AD_REALM in .env is the KERBEROS realm (uppercase, e.g. RENTOPTION.COM);
# the Keycloak admin realm name is dicted by realm-export.json (rentoption.com).
# KC_REALM is the Keycloak admin realm used in API paths.
ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
    for VAR in KEYCLOAK_ADMIN KEYCLOAK_ADMIN_PASSWORD AD_DOMAIN AD_NETBIOS SAMBA_ADMIN_PASSWORD; do
        VAL="$(grep -E "^${VAR}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-)"
        if [[ -n "$VAL" ]]; then
            export "${VAR}=${VAL}"
        fi
    done
fi

KC_REALM="${KC_REALM:-rentoption.com}"

# --- Configuration (env overridable, sensible defaults) ---
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
KC_ADMIN_USER="${KEYCLOAK_ADMIN:-admin}"
KC_ADMIN_PASS="${KEYCLOAK_ADMIN_PASSWORD:-ChangeMe_KeycloakAdmin_2024!}"
AD_DOMAIN="${AD_DOMAIN:-rentoption.com}"
AD_NETBIOS="${AD_NETBIOS:-RENTOPTION}"
SAMBA_ADMIN_PASS="${SAMBA_ADMIN_PASSWORD:-ChangeMe_SambaAdmin_2024!}"

LDAP_CONN_URL="${LDAP_CONN_URL:-ldap://samba:389}"
LDAP_USERS_DN="${LDAP_USERS_DN:-CN=Users,DC=${AD_DOMAIN//./,DC=}}"
LDAP_BIND_DN="${LDAP_BIND_DN:-CN=Administrator,CN=Users,DC=${AD_DOMAIN//./,DC=}}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Get admin token ---
log "Authenticating to Keycloak (${KEYCLOAK_URL})..."
TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" \
    -d "username=${KC_ADMIN_USER}" \
    -d "password=${KC_ADMIN_PASS}" \
    -d "grant_type=password" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null)

if [[ -z "$TOKEN" ]]; then
    log "ERROR: Could not get Keycloak admin token. Is Keycloak running and reachable at ${KEYCLOAK_URL}?"
    exit 1
fi
log "Authenticated."

# --- Check if LDAP federation already exists (idempotent) ---
EXISTING=$(curl -s "${KEYCLOAK_URL}/admin/realms/${KC_REALM}/components?type=org.keycloak.storage.UserStorageProvider" \
    -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)

LDAP_ID=$(echo "$EXISTING" | python3 -c "
import sys,json
data = json.load(sys.stdin)
for c in data:
    if c.get('providerId') == 'ldap':
        print(c['id'])
        break
" 2>/dev/null || echo "")

if [[ -n "$LDAP_ID" ]]; then
    log "LDAP federation already exists (id: ${LDAP_ID}). Skipping creation."
    log "Triggering Full Sync..."
else
    # --- Create LDAP federation ---
    log "Creating LDAP federation..."

    LDAP_CONFIG=$(python3 -c "
import json
config = {
    'connectionUrl': ['${LDAP_CONN_URL}'],
    'usersDn': ['${LDAP_USERS_DN}'],
    'bindDn': ['${LDAP_BIND_DN}'],
    'bindCredential': ['${SAMBA_ADMIN_PASS}'],
    'usernameLDAPAttribute': ['sAMAccountName'],
    'rdnLDAPAttribute': ['cn'],
    'uuidLDAPAttribute': ['objectGUID'],
    'userObjectClasses': ['person,organizationalPerson,user'],
    'vendor': ['active-directory'],
    'editMode': ['WRITABLE'],
    'syncRegistrations': ['false'],
    'authType': ['simple'],
    'importEnabled': ['true'],
    'enabled': ['true'],
    'searchScope': ['1'],
    'fullSyncPeriod': ['86400'],
    'changedSyncPeriod': ['3600'],
    'batchSizeForSync': ['1000'],
    'pagination': ['true'],
    'connectionPooling': ['true'],
    'useTruststoreSpi': ['never'],
    'priority': ['0'],
    'krbPrincipalAttribute': ['krb5PrincipalName']
}
comp = {
    'name': 'ldap',
    'providerId': 'ldap',
    'providerType': 'org.keycloak.storage.UserStorageProvider',
    'parentId': None,
    'config': config
}
print(json.dumps(comp))
")

    # Realm ID needed for parentId
    REALM_ID=$(curl -s "${KEYCLOAK_URL}/admin/realms/${KC_REALM}" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)

    LDAP_CONFIG=$(echo "$LDAP_CONFIG" | python3 -c "
import sys,json
comp = json.load(sys.stdin)
comp['parentId'] = '${REALM_ID}'
print(json.dumps(comp))
")

    RESULT=$(curl -s -w "\n%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${KC_REALM}/components" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$LDAP_CONFIG" 2>/dev/null)

    HTTP_CODE=$(echo "$RESULT" | tail -1)
    BODY=$(echo "$RESULT" | sed '$d')

    if [[ "$HTTP_CODE" != "201" ]]; then
        log "ERROR: Failed to create LDAP federation (HTTP ${HTTP_CODE})"
        echo "$BODY"
        exit 1
    fi

    LDAP_ID=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
    log "LDAP federation created (id: ${LDAP_ID})"

    # --- Create attribute mappers ---
    log "Creating attribute mappers..."

    create_mapper() {
        local NAME="$1"
        local LDAP_ATTR="$2"
        local MODEL_ATTR="$3"
        local IS_MANDATORY="${4:-true}"
        local READ_ONLY="${5:-false}"
        local ALWAYS_READ="${6:-true}"

        MAPPER_CONFIG=$(python3 -c "
import json
comp = {
    'name': '${NAME}',
    'providerId': 'user-attribute-ldap-mapper',
    'providerType': 'org.keycloak.storage.ldap.mappers.LDAPStorageMapper',
    'parentId': '${LDAP_ID}',
    'config': {
        'ldap.attribute': ['${LDAP_ATTR}'],
        'user.model.attribute': ['${MODEL_ATTR}'],
        'is.mandatory.in.ldap': ['${IS_MANDATORY}'],
        'read.only': ['${READ_ONLY}'],
        'always.read.value.from.ldap': ['${ALWAYS_READ}']
    }
}
print(json.dumps(comp))
")

        RESULT=$(curl -s -w "\n%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${KC_REALM}/components" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$MAPPER_CONFIG" 2>/dev/null)

        CODE=$(echo "$RESULT" | tail -1)
        if [[ "$CODE" == "201" ]]; then
            log "  Mapper '${NAME}' created (${LDAP_ATTR} -> ${MODEL_ATTR})"
        else
            log "  WARNING: Mapper '${NAME}' creation returned HTTP ${CODE}"
        fi
    }

    # username: sAMAccountName -> username (writable, not always read from LDAP)
    create_mapper "username" "sAMAccountName" "username" "true" "false" "false"
    # email: mail -> email (writable, not always read)
    create_mapper "email" "mail" "email" "false" "false" "false"
    # firstName: givenName -> firstName (always read from LDAP)
    create_mapper "first name" "givenName" "firstName" "true" "false" "true"
    # lastName: sn -> lastName (always read from LDAP)
    create_mapper "last name" "sn" "lastName" "true" "false" "true"
    # creationDate: createTimestamp -> createTimestamp (read-only)
    create_mapper "creation date" "createTimestamp" "createTimestamp" "false" "true" "true"
    # modifyDate: modifyTimestamp -> modifyTimestamp (read-only)
    create_mapper "modify date" "modifyTimestamp" "modifyTimestamp" "false" "true" "true"

    log "Triggering Full Sync..."
fi

# --- Trigger full sync (works whether just created or already existed) ---
RSYNC=$(curl -s -X POST \
    "${KEYCLOAK_URL}/admin/realms/${KC_REALM}/user-storage/${LDAP_ID}/sync?action=triggerFullSync" \
    -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)

echo "$RSYNC" | python3 -c "
import sys,json
try:
    r = json.load(sys.stdin)
    if isinstance(r, dict) and 'status' in r:
        print(f'  Sync result: {r[\"status\"]} (failed: {r.get(\"failed\",0)})')
    else:
        print(f'  Sync response: {r}')
except Exception as e:
    print(f'  Sync response: {sys.stdin.read()}')
"

log "LDAP federation setup complete!"
log "  Federation: ldap (${LDAP_CONN_URL})"
log "  Bind DN: ${LDAP_BIND_DN}"
log "  User Base: ${LDAP_USERS_DN}"
log "  Mappers: username, email, firstName, lastName, creationDate, modifyDate"
log ""
log "Group mapper NOT configured (breaks KC26 user sync). See README to add manually."
