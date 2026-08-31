#!/bin/bash
# ===========================================
# Samba AD Health Check Script (minimal)
# Only checks process + LDAP on port 389
# ===========================================

set -euo pipefail

AD_DOMAIN="${AD_DOMAIN:-rentoption.com}"
SAMBA_ADMIN_PASS="${SAMBA_ADMIN_PASS:-ChangeMe_SambaAdmin_2024!}"

# Check 1: Samba process running
if ! pgrep samba > /dev/null; then
    echo "FAIL: Samba process not running"
    exit 1
fi

# Check 2: LDAP responding
if ! ldapsearch -x -H ldap://localhost:389 -b "DC=${AD_DOMAIN//./,DC=}" -s base dn -D "CN=Administrator,CN=Users,DC=${AD_DOMAIN//./,DC=}" -w "${SAMBA_ADMIN_PASS}" > /dev/null 2>&1; then
    echo "FAIL: LDAP not responding on port 389"
    exit 1
fi

echo "OK: Samba healthy"
exit 0
