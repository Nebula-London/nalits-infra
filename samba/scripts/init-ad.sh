#!/bin/bash
# ===========================================
# Samba AD Domain Controller Initialization Script
# Flow: provision -> start background -> wait -> configure -> exec foreground
# ===========================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"; }

AD_DOMAIN="${AD_DOMAIN:-rentoption.com}"
AD_REALM="${AD_REALM:-RENTOPTION.COM}"
AD_NETBIOS="${AD_NETBIOS:-RENTOPTION}"
SAMBA_ADMIN_PASS="${SAMBA_ADMIN_PASS:-ChangeMe_SambaAdmin_2024!}"
SAMBA_DNS_FORWARDER="${SAMBA_DNS_FORWARDER:-8.8.8.8}"

SAMBA_DATA_DIR="/var/lib/samba"
SAMBA_ETC_DIR="/etc/samba"
SAMBA_PROVISIONED_FLAG="${SAMBA_DATA_DIR}/.provisioned"

log "Starting Samba AD initialization..."
log "Domain: ${AD_DOMAIN}"
log "Realm: ${AD_REALM}"
log "NetBIOS: ${AD_NETBIOS}"

# =============================================
# STEP 1: CHECK IF ALREADY PROVISIONED
# =============================================
if [[ -f "${SAMBA_PROVISIONED_FLAG}" ]]; then
    log "Samba AD already provisioned. Starting services..."
    exec /usr/sbin/samba -i -F --debug-stdout
fi

# =============================================
# STEP 2: PROVISION DOMAIN
# =============================================
log "Provisioning new Samba AD domain..."

log "Generating smb.conf..."
cat > "${SAMBA_ETC_DIR}/smb.conf" <<EOF
[global]
    workgroup = ${AD_NETBIOS}
    realm = ${AD_REALM}
    netbios name = DC1
    server role = active directory domain controller
    idmap_ldb:use rfc2307 = yes
    dns forwarder = ${SAMBA_DNS_FORWARDER}
    kerberos method = secrets and keytab
    dedicated keytab file = /etc/samba/dc1.keytab
    ldap server require strong auth = no
    tls enabled = yes
    tls keyfile = /etc/samba/tls/key.pem
    tls certfile = /etc/samba/tls/cert.pem
    tls cafile = /etc/samba/tls/ca.pem
    max open files = 65535
    socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=524288 SO_SNDBUF=524288
    log level = 2
    log file = /var/log/samba/log.%m
    max log size = 100
    winbind use default domain = yes
    winbind enum users = yes
    winbind enum groups = yes
    winbind nss info = rfc2307
    winbind refresh tickets = yes
    vfs objects = dfs_samba4 acl_xattr
    map acl inherit = yes
    store dos attributes = yes

[sysvol]
    path = /var/lib/samba/sysvol
    read only = no

[netlogon]
    path = /var/lib/samba/sysvol/${AD_REALM}/scripts
    read only = no

[IPC$]
    path = /tmp
    hosts allow = 172.25.0.0/24 172.24.0.0/24
EOF

log "Generating krb5.conf..."
cat > "${SAMBA_ETC_DIR}/krb5.conf" <<EOF
[libdefaults]
    default_realm = ${AD_REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false
    pkinit_anchors = FILE:/etc/samba/tls/ca.pem
    default_ccache_name = KEYRING:persistent:%{uid}

[realms]
    ${AD_REALM} = {
        kdc = dc1.${AD_REALM}
        admin_server = dc1.${AD_REALM}
        default_domain = ${AD_DOMAIN}
    }

[domain_realm]
    .${AD_DOMAIN} = ${AD_REALM}
    ${AD_DOMAIN} = ${AD_REALM}

[logging]
    kdc = FILE:/var/log/krb5kdc.log
    admin_server = FILE:/var/log/kadmind.log
    default = FILE:/var/log/krb5lib.log
EOF

log "Running samba-tool domain provision..."
samba-tool domain provision \
    --realm="${AD_REALM}" \
    --domain="${AD_NETBIOS}" \
    --adminpass="${SAMBA_ADMIN_PASS}" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --use-rfc2307 \
    --option="interfaces=lo eth0" \
    --option="bind interfaces only=yes"

# =============================================
# STEP 3: CREATE TLS CERTIFICATES
# =============================================
log "Creating TLS certificates for LDAPS..."
mkdir -p "${SAMBA_ETC_DIR}/tls"

openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
    -nodes -keyout "${SAMBA_ETC_DIR}/tls/ca.key" \
    -out "${SAMBA_ETC_DIR}/tls/ca.pem" \
    -subj "/CN=${AD_REALM} CA" \
    -addext "basicConstraints=critical,CA:TRUE"

openssl genrsa -out "${SAMBA_ETC_DIR}/tls/key.pem" 4096

openssl req -new -key "${SAMBA_ETC_DIR}/tls/key.pem" \
    -out "${SAMBA_ETC_DIR}/tls/server.csr" \
    -subj "/CN=dc1.${AD_REALM}" \
    -addext "subjectAltName=DNS:dc1.${AD_REALM},DNS:${AD_DOMAIN},IP:127.0.0.1"

openssl x509 -req -in "${SAMBA_ETC_DIR}/tls/server.csr" \
    -CA "${SAMBA_ETC_DIR}/tls/ca.pem" \
    -CAkey "${SAMBA_ETC_DIR}/tls/ca.key" \
    -CAcreateserial \
    -out "${SAMBA_ETC_DIR}/tls/cert.pem" \
    -days 3650 -sha256 \
    -extfile <(echo -e "subjectAltName=DNS:dc1.${AD_REALM},DNS:${AD_DOMAIN},IP:127.0.0.1\nextendedKeyUsage=serverAuth")

chmod 600 "${SAMBA_ETC_DIR}/tls/key.pem"
chmod 644 "${SAMBA_ETC_DIR}/tls/cert.pem" "${SAMBA_ETC_DIR}/tls/ca.pem"

# =============================================
# STEP 4: START SAMBA IN BACKGROUND
# =============================================
log "Starting Samba AD in background..."
/usr/sbin/samba -i -F --debug-stdout &
SAMBA_PID=$!

# =============================================
# STEP 5: WAIT FOR LDAP PORT TO BE READY
# =============================================
log "Waiting for LDAP to be ready..."
TIMEOUT=120
INTERVAL=2
ELAPSED=0
while ! (echo > /dev/tcp/localhost/389) 2>/dev/null; do
    if ! kill -0 ${SAMBA_PID} 2>/dev/null; then
        error "Samba process died during startup"
        exit 1
    fi
    sleep ${INTERVAL}
    ELAPSED=$((ELAPSED + INTERVAL))
    if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
        error "LDAP port 389 not ready within ${TIMEOUT}s"
        exit 1
    fi
done
log "LDAP ready after ${ELAPSED}s"

# =============================================
# STEP 6: POST-PROVISION CONFIGURATION
# =============================================
log "Configuring Kerberos..."
kinit administrator@"${AD_REALM}" <<< "${SAMBA_ADMIN_PASS}" || warn "kinit failed, continuing anyway"

log "Creating service principals..."
samba-tool spn add ldap/dc1.${AD_REALM} DC1$ \
    --option="password=${SAMBA_ADMIN_PASS}" || warn "SPN add failed"

log "Creating DNS records..."
samba-tool dns add dc1.${AD_REALM} ${AD_DOMAIN} dc1 A $(hostname -i) \
    -U administrator --password="${SAMBA_ADMIN_PASS}" || warn "DNS record add failed"
samba-tool dns add dc1.${AD_REALM} ${AD_DOMAIN} @ A $(hostname -i) \
    -U administrator --password="${SAMBA_ADMIN_PASS}" || warn "DNS SOA record add failed"

log "Creating standard groups..."
samba-tool group add "Domain Admins" --group-scope=Global --group-type=Security \
    -U administrator --password="${SAMBA_ADMIN_PASS}" || true
samba-tool group add "HR Users" --group-scope=Global --group-type=Security \
    -U administrator --password="${SAMBA_ADMIN_PASS}" || true
samba-tool group add "Service Accounts" --group-scope=Global --group-type=Security \
    -U administrator --password="${SAMBA_ADMIN_PASS}" || true

log "Creating Keycloak service account..."
samba-tool user create keycloak-service "ChangeMe_KeycloakSvc_2024!" \
    --given-name="Keycloak" --surname="Service" \
    --mail="keycloak@${AD_DOMAIN}" \
    --userou="CN=Users" \
    -U administrator --password="${SAMBA_ADMIN_PASS}" || true

samba-tool group addmembers "Service Accounts" keycloak-service \
    -U administrator --password="${SAMBA_ADMIN_PASS}" || true

log "Creating SSSD access groups..."
samba-tool group add "root-sssd" --group-scope=Global --group-type=Security \
    -U administrator --password="${SAMBA_ADMIN_PASS}" 2>/dev/null && \
    log "Created group 'root-sssd' (SSH + sudo)" || \
    warn "Group 'root-sssd' may already exist"

samba-tool group add "non-root-sssd" --group-scope=Global --group-type=Security \
    -U administrator --password="${SAMBA_ADMIN_PASS}" 2>/dev/null && \
    log "Created group 'non-root-sssd' (SSH only)" || \
    warn "Group 'non-root-sssd' may already exist"

log "Granting LDAP write permissions to keycloak-service..."
samba-tool dsacl set "CN=Users,DC=${AD_DOMAIN//./,DC=}" \
    --acl="keycloak-service:CR;user" \
    -U administrator --password="${SAMBA_ADMIN_PASS}" 2>/dev/null || warn "dsacl set failed (non-critical)"

# =============================================
# STEP 7: MARK AS PROVISIONED
# =============================================
log "Samba AD provisioning complete!"
touch "${SAMBA_PROVISIONED_FLAG}"

# =============================================
# STEP 8: EXEC SAMBA IN FOREGROUND
# =============================================
log "Starting Samba AD Domain Controller in foreground..."
exec /usr/sbin/samba -i -F --debug-stdout
