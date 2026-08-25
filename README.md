# RentOption Infrastructure

Docker Compose stack for identity management with Keycloak, Samba AD, and LDAP Account Manager.

## Architecture

```
Internet (port 80/443)
    │
    ▼
┌─────────────────────────────────────┐
│         Nginx (SSL/LE)              │
│  sso.rentoption.com → Keycloak      │
└─────────────────────────────────────┘
    │                    │
    ▼                    ▼
┌─────────────┐    ┌─────────────┐
│  Keycloak   │◄───│  Samba AD   │
│  (8080)     │LDAP│  (DC)       │
│             │    │ SAMBA.INTERNAL
└─────────────┘     └─────────────┘
                            │
                     ┌──────┴──────┐
                     │  LAM (UI)   │
                     │  (8081)     │
                     │ Internal only
                     └─────────────┘
```

## Services

| Service | Port | Purpose | Access |
|---------|------|---------|--------|
| **nginx** | 80, 443 | Reverse proxy, SSL termination | Public |
| **certbot** | - | Let's Encrypt certificates | Internal |
| **keycloak** | 8080 | Identity Provider (OIDC/SAML) | Via nginx |
| **postgres** | 5432 | Keycloak database | Internal |
| **samba** | 53,88,135,139,389,445,636,3268,3269 | Active Directory DC | Internal |
| **lam** | 8081 | LDAP Account Manager UI | Internal only |

## Quick Start

### 1. Prerequisites

- Docker 24+ and Docker Compose v2
- DNS A record: `sso.rentoption.com` → server IP
- Ports 80, 443 open to internet
- Minimum 4GB RAM, 20GB disk

### 2. Configuration

```bash
# Copy environment template
cp .env.example .env

# Edit with your values (REQUIRED: change all passwords!)
vim .env
```

**Critical variables to change:**
- `SAMBA_ADMIN_PASSWORD` - Domain Admin password
- `KEYCLOAK_ADMIN_PASSWORD` - Keycloak admin password
- `KC_DB_PASSWORD` / `POSTGRES_PASSWORD` - Database passwords
- `CERTBOT_EMAIL` - Let's Encrypt registration email
- `CERTBOT_STAGING=0` for production certificates

### 3. Deploy

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Deploy (first run obtains SSL certs)
./scripts/deploy.sh

# Or manually:
docker compose up -d
```

### 4. Access Services

| Service | URL | Credentials |
|---------|-----|-------------|
| Keycloak Admin | https://sso.rentoption.com/admin | admin / `KEYCLOAK_ADMIN_PASSWORD` |
| Keycloak User | https://sso.rentoption.com | AD users (synced) |
| LAM (AD UI) | http://<server-ip>:8081 | admin / `LAM_PASSWORD` |

## Directory Structure

```
infra-nalits/
├── docker-compose.yml          # Main compose file
├── .env                        # Environment variables (DO NOT COMMIT)
├── .env.example                # Template
├── nginx/
│   ├── nginx.conf              # Main nginx config
│   └── conf.d/
│       ├── keycloak.conf       # Keycloak proxy config
│       ├── certbot-challenge.conf
│       └── samba-ui.conf       # LAM proxy (disabled)
│   └── certbot/
│       ├── www/                # ACME challenge webroot
│       └── conf/               # Let's Encrypt certificates
├── keycloak/
│   ├── realm-export.json       # Pre-configured realm
│   ├── providers/              # Custom SPI providers
│   └── themes/                 # Custom themes
├── samba/
│   ├── smb.conf                # Samba config template
│   ├── krb5.conf               # Kerberos config
│   └── scripts/
│       ├── init-ad.sh          # Domain provisioning
│       ├── create-users.sh     # Test users
│       └── healthcheck.sh      # Health check
├── lam/
│   ├── Dockerfile              # Custom LAM image
│   ├── config/lam.conf         # LAM configuration
│   └── entrypoint.sh           # Auto-config script
├── postgres/
│   └── init/                   # DB init scripts
├── certbot/
│   ├── renew.sh                # Renewal script
│   └── cron                    # Cron schedule
└── scripts/
    ├── deploy.sh               # Full deployment
    ├── backup.sh               # Backup all volumes
    └── restore.sh              # Restore from backup
```

## Network Ports

### Public (Internet-facing)
- **80/tcp** - HTTP → HTTPS redirect, ACME challenges
- **443/tcp** - HTTPS for Keycloak

### Internal (Docker network only)
- **8080/tcp** - Keycloak HTTP
- **8081/tcp** - LAM HTTP
- **5432/tcp** - PostgreSQL
- **53/tcp/udp** - DNS
- **88/tcp/udp** - Kerberos
- **135/tcp** - RPC
- **139/tcp** - NetBIOS
- **389/tcp/udp** - LDAP
- **445/tcp** - SMB
- **636/tcp** - LDAPS
- **3268/tcp** - Global Catalog
- **3269/tcp** - Global Catalog SSL

## Keycloak ↔ Samba AD Integration

The stack configures **LDAP User Federation (WRITE)** from Keycloak to Samba AD:

- **Realm**: `rentoption`
- **LDAP Server**: `ldaps://samba:636`
- **Bind DN**: `CN=Administrator,CN=Users,DC=SAMBA,DC=INTERNAL`
- **User Base DN**: `CN=Users,DC=SAMBA,DC=INTERNAL`
- **Mappers**: username (userPrincipalName), email, firstName, lastName, displayName, groups, roles
- **Sync**: Full sync daily, changed users hourly

HR creates users in Keycloak → automatically synced to Samba AD.

## Samba AD Domain

- **Domain**: `SAMBA.INTERNAL` (Kerberos realm)
- **NetBIOS**: `SAMBA`
- **DC Name**: `DC1`
- **DNS**: Internal, forwards to `8.8.8.8`
- **LDAPS**: Enabled with self-signed cert (auto-generated)

## SSL Certificates (Let's Encrypt)

- Automated via Certbot (webroot mode)
- Renewal: Daily at 3 AM via cron
- Staging mode by default (`CERTBOT_STAGING=1`)
- **Production**: Set `CERTBOT_STAGING=0` in `.env`

## LAM (LDAP Account Manager)

Web UI for managing Samba AD users/groups (internal access only):

- URL: `http://<server-ip>:8081`
- Login: `admin` / `LAM_PASSWORD`
- Features: User/group management, password reset, self-service

**To enable**: `docker compose --profile internal up -d lam`

## Backup & Restore

```bash
# Backup all volumes and configs
./scripts/backup.sh

# Restore from backup
./scripts/restore.sh rentoption-backup-20240115_030000
# Or latest:
./scripts/restore.sh latest
```

Backups stored in `./backups/` with 30-day retention.

## Maintenance

### View Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f keycloak
```

### Update Services
```bash
docker compose pull
docker compose up -d
```

### Scale Keycloak (HA)
```yaml
# In docker-compose.override.yml
services:
  keycloak:
    deploy:
      replicas: 2
```

### Reset Samba AD (DANGEROUS)
```bash
docker compose down -v
docker volume rm rentoption-samba-data rentoption-samba-etc
docker compose up -d samba
```

## Troubleshooting

### Keycloak won't start
```bash
# Check database connectivity
docker compose exec postgres pg_isready -U keycloak

# Check Keycloak logs
docker compose logs keycloak
```

### Samba AD not provisioning
```bash
# Check logs
docker compose logs samba

# Manual provision
docker compose exec samba /scripts/init-ad.sh
```

### LDAP sync not working
```bash
# Test LDAP connectivity
docker compose exec keycloak ldapsearch -x -H ldaps://samba:636 -D "CN=Administrator,CN=Users,DC=SAMBA,DC=INTERNAL" -W -b "CN=Users,DC=SAMBA,DC=INTERNAL"
```

### Certificate issues
```bash
# Force renewal
docker compose run --rm certbot certbot renew --force-renewal

# Check nginx config
docker compose exec nginx nginx -t
```

## Security Checklist

- [ ] Change all default passwords in `.env`
- [ ] Set `CERTBOT_STAGING=0` for production
- [ ] Restrict SSH access (key-only, non-standard port)
- [ ] Enable firewall: only 80, 443, 22 (SSH) from trusted IPs
- [ ] Regular backups (cron: `0 2 * * * /path/scripts/backup.sh`)
- [ ] Monitor logs for failed logins
- [ ] Update images monthly: `docker compose pull && docker compose up -d`
- [ ] Review Keycloak brute force settings

## License

Internal use only - RentOption Infrastructure