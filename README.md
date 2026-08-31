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
| **keycloak** | 8080 | Identity Provider (OIDC/SAML) | Via nginx |
| **postgres** | 5432 | Keycloak database | Internal |
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
- `KC_DB_PASSWORD` / `POSTGRES_PASSWORD` - Database passwords
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

## SSSD Client Deployment

Servers authenticate their SSH users against Samba AD via SSSD. Two connection patterns are supported and tested.

### Architecture

```
Main server (145.241.221.212) - Samba AD (389/636/88 + SSH)
      ↑
  JUMPBOX connects directly over the internet (has a public IP)
      ↑
  REMOTE connects via an SSH tunnel through the jumpbox (private IP, no internet)
```

- **Jumpbox** (public IP): talks to Samba AD directly over the internet.
- **Remote server** (private IP, no internet): can't reach Samba directly, so it tunnels `389/636/88` from `localhost` through an SSH connection to the jumpbox, which forwards to the main server. **No inbound ports are needed on the jumpbox or remote** — the tunnel is initiated outbound from the remote.

### Prerequisites

- Main server firewall allows ports `389`, `636`, `88` from the jumpbox's public IP.
- Jumpbox SSH (port 22) is reachable from the remote server's IP.
- Remote server can make outbound SSH connections to the jumpbox (no inbound ports required on the remote).

### Deploy on the Jumpbox (direct connection)

```bash
cd sssd/jumpbox
MAIN_SERVER_IP=145.241.221.212 SAMBA_ADMIN_PASSWORD=ChangeMe_SambaAdmin_2024! ./setup-jumpbox.sh
```

This installs SSSD natively, writes `/etc/sssd/sssd.conf` (LDAPS to the main server), configures nsswitch/PAM/sshd/sudoers, and starts SSSD.

### Deploy on a Remote Server (via SSH tunnel)

```bash
cd sssd/remote
JUMPBOX_HOST=<jumpbox-ip> JUMPBOX_USER=<user> \
MAIN_SERVER_IP=145.241.221.212 \
SAMBA_ADMIN_PASSWORD=ChangeMe_SambaAdmin_2024! ./setup-remote.sh
```

The script:
1. Installs SSSD + autossh.
2. Sets up SSH key auth from the remote to the jumpbox (run it once to generate/print the key, add it to the jumpbox's `authorized_keys`, then re-run).
3. Creates the `autossh-tunnel.service` systemd unit that forwards `389/636/88` from `localhost` through the jumpbox to the main server.
4. Configures SSSD to point at `ldaps://127.0.0.1:636` and `krb5_server = 127.0.0.1:88` (the tunnel endpoints).
5. Configures nsswitch/PAM/sshd/sudoers and starts SSSD.

Reusable reference configs live in `sssd/remote/` (`sssd.conf`, `krb5.conf`, `autossh-tunnel.service`).

### Verify

```bash
id testuser                               # resolves AD user + groups
getent passwd testuser                    # passwd entry
getent group root-sssd                    # sudo group
ssh testuser@<server>                     # SSH login with AD password
```

The remote must have the tunnel running for SSSD to work. Check: `systemctl status autossh-tunnel`, `ss -tlnp | grep -E ':(389|636|88)'`. If the tunnel drops, SSSD goes offline; restore the tunnel and `sss_cache -E`.

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
docker compose exec postgres pg_isready -U keycloak
```

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

### SSSD not resolving AD users
If `id testuser` returns "no such user" but LDAP searches work (e.g. `ldapsearch` returns the user), the issue is likely the ID mapping filter. SSSD with `rfc2307bis` schema generates a search filter that requires `uidNumber`, which Samba AD users don't have by default. The fix: in `/etc/sssd/sssd.conf`, set `ldap_schema = ad` and `ldap_id_mapping = True`. This switches to SID-based ID mapping and drops the uidNumber requirement. After changing, clear the cache: `sss_cache -E && systemctl restart sssd`. Both `sssd/jumpbox/sssd.conf` and `sssd/config/sssd.conf` already include this fix.

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
