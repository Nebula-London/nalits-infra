# RentOption Infrastructure

Docker Compose stack for identity management with Keycloak 26, Samba AD, and LDAP Account Manager.

## Architecture

```
Internet (port 80/443)
    |
    v
+-------------------------------------+
|         Nginx (SSL/LE)              |
|  sso.rentoption.com -> Keycloak      |
+-------------------------------------+
    |                    |
    v                    v
+-------------+    +-------------+
|  Keycloak   |<---|  Samba AD   |
|  (8080)     |LDAP|  (DC)       |
|             |    | rentoption.local
+-------------+    +-------------+
                           |
                    +------|------+
                    |  LAM (UI)   |
                    |  (8081)     |
                    | Internal only
                    +-------------+
```

## Services

| Service | Port | Purpose | Access |
|---------|------|---------|--------|
| **nginx** | 80, 443 | Reverse proxy, SSL termination | Public |
| **certbot** | - | Let's Encrypt certificates | Internal |
| **keycloak** | 8080 | Identity Provider (OIDC/SAML), DB = OCI ADB (Oracle) | Via nginx |
| **samba** | 389, 445, etc. | Active Directory DC | Internal |
| **lam** | 8081 | LDAP Account Manager UI | Internal only |

## Quick Start

### 1. Prerequisites

- Docker 24+ and Docker Compose v2
- DNS A record: `sso.rentoption.com` -> server IP
- Ports 80, 443 open to internet
- Minimum 4GB RAM, 20GB disk

### 2. Configuration

```bash
cp .env.example .env
vim .env  # Change ALL passwords and domain settings
```

**Critical variables:**
- `SAMBA_ADMIN_PASSWORD` - Domain Admin password
- `KEYCLOAK_ADMIN_PASSWORD` - Keycloak admin password
- `KC_DB_URL` / `KC_DB_PASSWORD` - OCI Autonomous DB (Oracle) connection
- `CERTBOT_EMAIL` - Let's Encrypt registration email

### 3. Deploy

```bash
chmod +x scripts/*.sh samba/scripts/*.sh
./scripts/deploy.sh
```

Or manually:
```bash
docker compose up -d
```

### 4. First-Time Setup (Manual Steps)

After `docker compose up -d` completes and all services are healthy:

**Step 1: Obtain SSL certificate (if not done by deploy.sh)**
```bash
docker compose run --rm certbot certonly \
  --webroot --webroot-path=/var/www/certbot \
  --email admin@rentoption.com --agree-tos --no-eff-email \
  -d sso.rentoption.com
docker compose restart nginx
```

**Step 2: Setup LDAP federation in Keycloak**

The realm (`rentoption`) is auto-imported from `keycloak/realm-export.json` on first boot. However, the LDAP user federation cannot be imported via realm import in KC26 — it must be configured separately:

```bash
./samba/scripts/setup-ldap-federation.sh
```

This creates:
- LDAP federation pointing to `ldap://samba:389`
- Bind DN: `CN=Administrator,CN=Users,DC=RENTOPTION,DC=LOCAL`
- Attribute mappers: username (sAMAccountName), email, firstName, lastName, creationDate, modifyDate
- Group mapper: group-ldap-mapper (READ_ONLY, syncs AD groups to Keycloak)

**Step 3: Sync users and groups from Samba AD to Keycloak**

In Keycloak admin console (`https://sso.rentoption.com/admin`):
- Switch to `rentoption` realm (top-left dropdown)
- User Federation -> ldap -> Sync -> **Full Sync** (users)
- User Federation -> ldap -> **Sync group registrations** (groups)

**Step 4: Create users in Samba AD**
```bash
docker exec rentoption-samba /scripts/create-user.sh <username> -f <first> -l <last>
```

### 5. Access Services

| Service | URL | Credentials |
|---------|-----|-------------|
| Keycloak Admin | https://sso.rentoption.com/admin | admin / `KEYCLOAK_ADMIN_PASSWORD` |
| Keycloak User Login | https://sso.rentoption.com | AD users (synced from Samba) |
| LAM (AD UI) | http://<server-ip>:8081 | admin / `LAM_PASSWORD` |

## Directory Structure

```
infra-nalits/
|-- docker-compose.yml          # Main compose file
|-- .env                        # Environment variables (DO NOT COMMIT)
|-- .env.example                # Template
|-- nginx/
|   |-- nginx.conf              # Main nginx config
|   |-- conf.d/
|   |   |-- keycloak.conf       # Keycloak proxy (HTTP->HTTPS + SSL)
|   |-- certbot/
|       |-- www/                # ACME challenge webroot
|       |-- conf/               # Let's Encrypt certificates
|-- keycloak/
|   |-- Containerfile           # Keycloak image + Oracle JDBC drivers
|   |-- realm-export.json       # Pre-configured realm (KC26-compatible)
|   |-- providers/              # Custom SPI providers
|   |-- themes/                 # Custom themes
|-- samba/
|   |-- Dockerfile
|   |-- scripts/
|       |-- init-ad.sh          # Domain provisioning (provision -> background -> wait -> config -> foreground)
|       |-- create-user.sh      # Create user in AD + sync to Keycloak
|       |-- setup-ldap-federation.sh  # Setup LDAP federation in Keycloak
|       |-- healthcheck.sh      # Health check
|-- lam/
|   |-- Dockerfile
|   |-- config/lam.conf
|-- certbot/
|   |-- Dockerfile
|   |-- renew.sh
|   |-- cron
|-- scripts/
    |-- deploy.sh               # Full deployment with health checks
```

## Keycloak <-> Samba AD Integration

### Configuration

| Setting | Value |
|---------|-------|
| Realm | `rentoption` |
| LDAP Server | `ldap://samba:389` |
| Bind DN | `CN=Administrator,CN=Users,DC=RENTOPTION,DC=LOCAL` |
| User Base DN | `CN=Users,DC=RENTOPTION,DC=LOCAL` |
| Username Attribute | `sAMAccountName` |
| Edit Mode | `WRITABLE` |
| Sync Registrations | `false` (AD is source of truth) |
| Vendor | Active Directory |

### Attribute Mappers

| Mapper | Type | LDAP Attribute | KC Attribute | Read Only |
|--------|------|---------------|-------------|-----------|
| username | user-attribute-ldap-mapper | sAMAccountName | username | No |
| email | user-attribute-ldap-mapper | mail | email | No |
| first name | user-attribute-ldap-mapper | givenName | firstName | No |
| last name | user-attribute-ldap-mapper | sn | lastName | No |
| creation date | user-attribute-ldap-mapper | createTimestamp | createTimestamp | Yes |
| modify date | user-attribute-ldap-mapper | modifyTimestamp | modifyTimestamp | Yes |
| **groups** | **group-ldap-mapper** | **cn, member** | **Keycloak groups** | **Yes** |

### Sync Direction

**Samba AD is the source of truth.** Users are created in Samba AD (via `samba-tool` or `create-user.sh`) and synced to Keycloak. Keycloak does not write users back to AD (syncRegistrations=false).

### Group Sync

The `group-ldap-mapper` syncs AD groups into Keycloak. After the LDAP federation is created (via `setup-ldap-federation.sh` or manually), trigger a group sync:

**Via Keycloak Admin Console:**
1. Go to `User Federation` -> `ldap`
2. Under **Sync group registrations**, click `Sync group registrations`

**Via API:**
```bash
TOKEN=$(curl -s -X POST "http://localhost:8080/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" -d "username=admin" -d "password=<ADMIN_PASS>" \
  -d "grant_type=password" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Find the group-ldap-mapper ID
MAPPER_ID=$(curl -s "http://localhost:8080/admin/realms/rentoption/components?parent=<LDAP_FEDERATION_ID>&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
for m in json.load(sys.stdin):
    if m.get('providerId') == 'group-ldap-mapper':
        print(m['id']); break
")

# Trigger group sync
curl -s -X POST "http://localhost:8080/admin/realms/rentoption/user-storage/<LDAP_FEDERATION_ID>/sync?strategy=FULL&mapperId=$MAPPER_ID" \
  -H "Authorization: Bearer $TOKEN"
```

**Available AD groups:**

| Group | Purpose |
|-------|---------|
| `root-sssd` | SSH access + sudo (full root) |
| `non-root-sssd` | SSH access only (no sudo) |
| `HR Users` | HR department users |
| `Service Accounts` | Non-human accounts |

**Important:** The `Groups DN` in the mapper must be set to `CN=Users,DC=RENTOPTION,DC=LOCAL` (not `DC=rentoption,DC=local`). Using the domain root DN triggers Samba AD referral responses that Keycloak silently drops, resulting in 0 imported groups.

## Keycloak on OCI Autonomous DB (Oracle)

Keycloak uses an **OCI Autonomous Database (Oracle)** as its database. No local
PostgreSQL is used. The `keycloak` service builds the custom Oracle image and holds
port `8080` behind nginx.

### Connection (TLS-only, no wallet)

OCI ADB is used with **TLS only** (mTLS disabled), so **no wallet** is needed.

```bash
KC_DB=oracle
KC_DB_URL=jdbc:oracle:thin:@(description=(retry_count=20)(retry_delay=3)(address=(protocol=tcps)(port=1521)(host=adb.<region>.oraclecloud.com))(connect_data=(service_name=<DBNAME>_tp.adb.oraclecloud.com))(security=(ssl_server_dn_match=yes)))
KC_DB_USERNAME=keycloak
KC_DB_PASSWORD=<oracle-db-password>
KC_DB_TLS_MODE=verify-server
```

> **IMPORTANT:** The service name must use the **`_tp`** tier. The `_medium` / `_high`
> tiers have **parallel DML enabled**, which breaks the Liquibase schema migration with
> `ORA-12838: cannot read/modify an object after modifying it in parallel`.
> `_tp` disables parallelism and migrates cleanly.

### Custom Keycloak image

`keycloak/Containerfile` builds a Keycloak `26.6` image that adds the Oracle JDBC
drivers and sets the Oracle DB type:

- `ojdbc17` + `orai18n` JARs are downloaded from Maven Central **at build time**
  (requires outbound internet to `repo1.maven.org`).
- `ENV KC_DB=oracle`, plus `KC_FEATURES=token-exchange`, `KC_HEALTH_ENABLED=true`,
  `KC_METRICS_ENABLED=true`.

### Deploy / test

```bash
docker compose build keycloak
docker compose up -d keycloak
```

Admin console: `https://sso.rentoption.com/admin`

### Verify it works

```bash
# 1. Container stable and healthy?
docker ps --filter name=rentoption-keycloak

# 2. Admin console responds (expect 302)?
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/admin/

# 3. Realm loaded from Oracle (expect realm: rentoption)?
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/admin/realms/rentoption
```

Expected result: `90` tables, `148` Liquibase changesets executed, `0` failed.

### Fresh-clone prerequisites

- Build-time internet (JDBC JAR download from Maven Central).
- ADB `keycloak` user grants:
  CREATE SESSION/TABLE/SEQUENCE/VIEW/PROCEDURE/TRIGGER/TYPE, UNLIMITED TABLESPACE,
  SELECT_CATALOG_ROLE.
- Keep the `_tp` service suffix.
- Realm auto-imports from `keycloak/realm-export.json` on first boot.

## Samba AD Domain

- **Domain**: `rentoption.local` (Kerberos realm: `RENTOPTION.LOCAL`)
- **NetBIOS**: `RENTOPTION`
- **DC Name**: `DC1`
- **DNS**: Internal, forwards to `8.8.8.8`
- **LDAPS**: Enabled with self-signed cert (auto-generated)

### Creating Users

```bash
# Minimal (username only, defaults applied)
docker exec rentoption-samba /scripts/create-user.sh john

# With options
docker exec rentoption-samba /scripts/create-user.sh jane \
  --first-name=Jane --last-name=Doe \
  --email=jane@rentoption.local \
  --password=MyPass123!
```

The script:
1. Creates user in Samba AD via `samba-tool user create`
2. Sets password to never expire
3. Triggers Keycloak LDAP Full Sync via API
4. Verifies user appears in Keycloak

## SSL Certificates (Let's Encrypt)

- Automated via Certbot (webroot mode)
- Renewal: via cron in certbot container
- **Production mode**: `CERTBOT_STAGING=0` in `.env`
- Certificates stored in Docker named volumes (`rentoption-nginx-certbot`, `rentoption-nginx-certbot-conf`)

### Manual Certificate Renewal
```bash
docker compose run --rm certbot certbot renew --webroot --webroot-path=/var/www/certbot
docker compose restart nginx
```

## LAM (LDAP Account Manager)

Web UI for managing Samba AD users/groups (internal access only):
- URL: `http://<server-ip>:8081`
- Login: `admin` / `LAM_PASSWORD`

**To enable:** `docker compose --profile internal up -d lam`

## Maintenance

### View Logs
```bash
docker compose logs -f              # All services
docker compose logs -f keycloak     # Specific service
```

### Update Services
```bash
docker compose pull
docker compose up -d
```

### Rebuild Samba (after script changes)
```bash
docker compose build samba
docker compose up -d --force-recreate samba
```

### Reset Samba AD (DANGEROUS)
```bash
docker compose down -v
docker volume rm rentoption-samba-data rentoption-samba-etc
docker compose up -d samba
```

## Troubleshooting

### Keycloak admin console shows http:// URLs
Ensure `KC_PROXY_HEADERS=xforwarded` is set in docker-compose.yml. Without this, Keycloak generates `http://` URLs behind a reverse proxy.

### LDAP sync fails with "GroupsMultipleParents"
The group-ldap-mapper is not compatible with KC26. Delete it from User Federation -> ldap -> Mappers.

### "Could not create user: unknown_error"
The role-ldap-mapper or syncRegistrations=true is causing issues. Ensure:
- `syncRegistrations: false` on the LDAP federation
- No role-ldap-mapper or group-ldap-mapper configured

### Keycloak won't start
```bash
docker compose logs keycloak
```

### Keycloak-on-Oracle startup fails with ORA-12838
`ORA-12838: cannot read/modify an object after modifying it in parallel` — the ADB
service tier has parallel DML enabled. Change the service name in `KC_DB_URL`
from `_medium`/`_high` to `_tp` (e.g. `<DBNAME>_tp.adb.oraclecloud.com`), then clean
the ADB schema and restart.

### Keycloak-on-Oracle migration fails with ORA-00955
`ORA-00955: name is already used by an existing object` — a partial/leftover schema
exists from a failed run. Drop the ADB schema objects (or the data volume) and
restart.

### Samba AD not provisioning
```bash
docker compose logs samba
docker compose exec samba /scripts/init-ad.sh
```

### LDAP sync not working
```bash
# Test LDAP connectivity from Keycloak container
docker compose exec keycloak bash -c \
  'ldapsearch -x -H ldap://samba:389 -D "CN=Administrator,CN=Users,DC=RENTOPTION,DC=LOCAL" -w "CHANGE_ME" -b "CN=Users,DC=RENTOPTION,DC=LOCAL" "(objectClass=user)" sAMAccountName'
```

### Group sync imports 0 groups
The `Groups DN` in the group-ldap-mapper must be `CN=Users,DC=RENTOPTION,DC=LOCAL`, not `DC=rentoption,DC=local`. Using the domain root DN triggers Samba AD referral responses that Keycloak silently drops. Edit the mapper in `User Federation -> ldap -> groups` and fix the `Groups DN` field, then re-sync.

### Certificate issues
```bash
docker compose run --rm certbot certbot renew --force-renewal
docker compose exec nginx nginx -t
```

## Security Checklist

- [ ] Change all default passwords in `.env`
- [ ] Set `CERTBOT_STAGING=0` for production
- [ ] Restrict SSH access (key-only, non-standard port)
- [ ] Enable firewall: only 80, 443, 22 (SSH) from trusted IPs
- [ ] Monitor logs for failed logins
- [ ] Update images monthly: `docker compose pull && docker compose up -d`

## License

Internal use only - RentOption Infrastructure
