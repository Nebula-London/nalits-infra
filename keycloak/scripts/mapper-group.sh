#!/bin/bash
# ===========================================
# Add AD Group -> Keycloak Group mapper (MANUAL, OPT-IN)
# Creates a group-ldap-mapper on an existing LDAP federation.
#
# WARNING: The group-ldap-mapper breaks KC26 user sync (GroupsMultipleParents
# and an NPE in GroupLDAPStorageMapperFactory.onCreate). Use only if you accept
# the tradeoff (AD group -> Keycloak group sync over user sync), or upgrade to
# Keycloak 27+. Run AFTER user sync is working.
#
# Usage (from host):
#   ./keycloak/scripts/mapper-group.sh
# ===========================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "${SCRIPT_DIR}")")"

# Load relevant vars from .env if present (do NOT source whole file - values
# like KC_DB_URL contain parens/quotes that break `source`).
# NOTE: AD_REALM in .env is the KERBEROS realm (uppercase); the Keycloak admin
# realm name is set by realm-export.json (rentoption.com). Use KC_REALM for the
# Keycloak API path.
ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
    for VAR in KEYCLOAK_ADMIN KEYCLOAK_ADMIN_PASSWORD AD_DOMAIN AD_NETBIOS; do
        VAL="$(grep -E "^${VAR}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2-)"
        if [[ -n "$VAL" ]]; then
            export "${VAR}=${VAL}"
        fi
    done
fi

KC_REALM="${KC_REALM:-rentoption.com}"

KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
KC_ADMIN_USER="${KEYCLOAK_ADMIN:-admin}"
KC_ADMIN_PASS="${KEYCLOAK_ADMIN_PASSWORD:-ChangeMe_KeycloakAdmin_2024!}"
AD_DOMAIN="${AD_DOMAIN:-rentoption.com}"
LDAP_USERS_DN="${LDAP_USERS_DN:-CN=Users,DC=${AD_DOMAIN//./,DC=}}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# --- Get token ---
log "Authenticating to Keycloak..."
TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" \
    -d "username=${KC_ADMIN_USER}" \
    -d "password=${KC_ADMIN_PASS}" \
    -d "grant_type=password" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null)

if [[ -z "$TOKEN" ]]; then
    log "ERROR: Could not get Keycloak admin token."
    exit 1
fi

# --- Find LDAP federation ---
LDAP_ID=$(curl -s "${KEYCLOAK_URL}/admin/realms/${KC_REALM}/components?type=org.keycloak.storage.UserStorageProvider" \
    -H "Authorization: Bearer ${TOKEN}" 2>/dev/null | python3 -c "
import sys,json
for c in json.load(sys.stdin):
    if c.get('providerId') == 'ldap':
        print(c['id']); break
" 2>/dev/null || echo "")

if [[ -z "$LDAP_ID" ]]; then
    log "ERROR: No LDAP federation found. Run keycloak/setup-ldap-federation.sh first."
    exit 1
fi

# --- Idempotency: skip if group mapper already exists ---
EXISTS=$(curl -s "${KEYCLOAK_URL}/admin/realms/${KC_REALM}/components?parent=${LDAP_ID}&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" \
    -H "Authorization: Bearer ${TOKEN}" 2>/dev/null | python3 -c "
import sys,json
print(any(c.get('providerId')=='group-ldap-mapper' for c in json.load(sys.stdin)))
" 2>/dev/null || echo "False")

if [[ "$EXISTS" == "True" ]]; then
    log "Group mapper already exists. Skipping."
    exit 0
fi

# --- Create group mapper ---
log "Creating group-ldap-mapper on federation ${LDAP_ID}..."
log "WARNING: This may break user sync in KC26. Ensure user sync works first."

GROUP_CONFIG=$(python3 -c "
import json
comp = {
    'name': 'groups',
    'providerId': 'group-ldap-mapper',
    'providerType': 'org.keycloak.storage.ldap.mappers.LDAPStorageMapper',
    'parentId': '${LDAP_ID}',
    'config': {
        'groups.dn': ['${LDAP_USERS_DN}'],
        'group.object.classes': ['group'],
        'group.name.ldap.attribute': ['cn'],
        'membership.ldap.attribute': ['member'],
        'membership.user.ldap.attribute': ['member'],
        'membership.attribute.type': ['DN'],
        'mode': ['READ_ONLY'],
        'preserve.group.inheritance': ['false'],
        'ignore.missing.groups': ['false'],
        'drop.non.existing.groups.during.sync': ['false'],
        'groups.path': ['/'],
        'memberof.ldap.attribute': ['memberOf']
    }
}
print(json.dumps(comp))
")

RESULT=$(curl -s -w "\n%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms/${KC_REALM}/components" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$GROUP_CONFIG" 2>/dev/null)

CODE=$(echo "$RESULT" | tail -1)
BODY=$(echo "$RESULT" | sed '$d')

if [[ "$CODE" == "201" ]]; then
    log "Group mapper 'groups' created (group-ldap-mapper, READ_ONLY)."
    log "Next: Sync group registrations (KC admin -> User Federation -> ldap -> Sync group registrations)."
else
    log "ERROR: Group mapper creation returned HTTP ${CODE}"
    echo "$BODY"
    exit 1
fi
