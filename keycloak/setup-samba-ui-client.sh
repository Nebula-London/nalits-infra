#!/bin/bash
# Setup samba-admin-ui OIDC client — idempotent, host-run similar to setup-ldap-federation.sh
set -euo pipefail
KC_URL="${KC_URL:-http://localhost:8080}"
KC_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KC_PASS="${KEYCLOAK_ADMIN_PASSWORD:-}"
if [ -z "$KC_PASS" ]; then echo "KEYCLOAK_ADMIN_PASSWORD not set"; exit 1; fi
REALM="rentoption.com"
CLIENT_ID="samba-admin-ui"
CLIENT_SECRET="${SAMBA_UI_CLIENT_SECRET:-ChangeMe_SambaUI_ClientSecret_2024!}"

echo "Getting admin token..."
TOKEN=$(curl -s -X POST "$KC_URL/realms/master/protocol/openid-connect/token" -d "client_id=admin-cli" -d "username=$KC_ADMIN" -d "password=$KC_PASS" -d "grant_type=password" | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
if [ -z "$TOKEN" ] || [ "$TOKEN" = "None" ]; then echo "Failed to get token"; exit 1; fi

# check existing
EXISTING=$(curl -s -H "Authorization: Bearer $TOKEN" "$KC_URL/admin/realms/$REALM/clients?clientId=$CLIENT_ID")
if echo "$EXISTING" | grep -q "samba-admin-ui"; then echo "Client $CLIENT_ID already exists — skipping create"; exit 0; fi

echo "Creating client $CLIENT_ID..."
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$KC_URL/admin/realms/$REALM/clients" -d @- <<JSON
{
  "clientId": "$CLIENT_ID",
  "name": "Samba AD Management Portal",
  "description": "Internal AD UI dc.rentoption.com — OIDC PKCE",
  "enabled": true,
  "clientAuthenticatorType": "client-secret",
  "secret": "$CLIENT_SECRET",
  "redirectUris": ["https://dc.rentoption.com/*","https://dc.rentoption.com:443/*","http://localhost:3000/*"],
  "webOrigins": ["https://dc.rentoption.com","http://localhost:3000"],
  "protocol": "openid-connect",
  "attributes": {"pkce.code.challenge.method":"S256","post.logout.redirect.uris":"https://dc.rentoption.com/*"},
  "standardFlowEnabled": true,
  "implicitFlowEnabled": false,
  "directAccessGrantsEnabled": false,
  "serviceAccountsEnabled": false,
  "publicClient": false,
  "fullScopeAllowed": false,
  "defaultClientScopes": ["web-origins","roles","profile","email"],
  "optionalClientScopes": ["address","phone","offline_access"]
}
JSON
echo "Client created. Also creating realm roles samba-* ..."
for role in samba-super-admin samba-ad-admin samba-helpdesk samba-hr samba-auditor samba-readonly; do
  curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$KC_URL/admin/realms/$REALM/roles" -d "{\"name\":\"$role\"}" || true
done
echo "Done. Assign roles to users via Admin Console -> Realm roles."
