#!/bin/bash
# ===========================================
# RentOption Infrastructure Deployment Script
# Complete deployment with validation and health checks
# ===========================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"; }
info() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

cd "${PROJECT_DIR}"

# Load environment
if [[ ! -f .env ]]; then
    error ".env file not found! Copy .env.example to .env and configure."
    exit 1
fi

export $(grep -v '^#' .env | xargs)

# ===========================================
# Pre-deployment Checks
# ===========================================
log "Starting RentOption Infrastructure Deployment"
log "Project directory: ${PROJECT_DIR}"

# Check Docker
if ! command -v docker &> /dev/null; then
    error "Docker not installed"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    error "Docker Compose v2 not available"
    exit 1
fi

# Check required ports
check_port() {
    local port=$1
    local service=$2
    if ss -tuln | grep -q ":${port} "; then
        warn "Port ${port} is already in use (needed for ${service})"
        return 1
    fi
    return 0
}

log "Checking required ports..."
check_port 80 "nginx HTTP" || true
check_port 443 "nginx HTTPS" || true
check_port 8080 "Keycloak HTTP" || true
check_port 8081 "LAM HTTP" || true
check_port 5432 "PostgreSQL" || true

# Validate environment variables
log "Validating configuration..."
REQUIRED_VARS=(
    "KEYCLOAK_HOSTNAME"
    "AD_DOMAIN"
    "AD_REALM"
    "SAMBA_ADMIN_PASSWORD"
    "KEYCLOAK_ADMIN_PASSWORD"
    "KC_DB_PASSWORD"
    "POSTGRES_PASSWORD"
    "CERTBOT_EMAIL"
    "CERTBOT_DOMAINS"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" || "${!var}" == "ChangeMe_"* ]]; then
        warn "Variable ${var} is not set or uses default value"
    fi
done

# ===========================================
# Initial Certificate Generation
# ===========================================
if [[ ! -d "nginx/certbot/conf/live/${KEYCLOAK_HOSTNAME}" ]]; then
    log "Generating initial SSL certificates..."

    # Start nginx temporarily for ACME challenge
    docker compose up -d nginx
    sleep 5

    STAGING_FLAG=""
    if [[ "${CERTBOT_STAGING:-1}" == "1" ]]; then
        STAGING_FLAG="--staging"
        warn "Using Let's Encrypt STAGING environment"
    fi

    docker run --rm \
        -v "rentoption-nginx-certbot:/var/www/certbot" \
        -v "rentoption-nginx-certbot-conf:/etc/letsencrypt" \
        certbot/certbot certonly \
        --webroot --webroot-path=/var/www/certbot \
        --email "${CERTBOT_EMAIL}" \
        --agree-tos --no-eff-email --non-interactive \
        ${STAGING_FLAG} \
        -d "${KEYCLOAK_HOSTNAME}"

    docker compose stop nginx
    log "Initial certificates obtained"
fi

# ===========================================
# Deploy Services
# ===========================================
log "Deploying all services..."

if [[ "${1:-}" == "--build" ]]; then
    log "Building images..."
    docker compose build --no-cache
fi

log "Starting services..."
docker compose up -d

# ===========================================
# Health Checks
# ===========================================
log "Waiting for services to be healthy..."

check_service() {
    local service=$1
    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        local status=$(docker compose ps --format json ${service} 2>/dev/null | jq -r '.[0].Health // "unknown"' 2>/dev/null || echo "unknown")

        if [[ "${status}" == "healthy" ]]; then
            log "${service} is healthy"
            return 0
        elif [[ "${status}" == "unhealthy" ]]; then
            error "${service} is unhealthy"
            docker compose logs ${service} --tail=50
            return 1
        fi

        info "Waiting for ${service}... (${attempt}/${max_attempts})"
        sleep 10
        ((attempt++))
    done

    error "${service} health check timeout"
    return 1
}

check_service postgres
check_service samba
check_service keycloak

# LAM is optional (profile)
if docker compose --profile internal ps lam &>/dev/null; then
    check_service lam
fi

# ===========================================
# Post-deployment: Setup LDAP Federation
# ===========================================
log "Running post-deployment tasks..."

# Setup LDAP federation + mappers (one-shot, idempotent)
log "Setting up LDAP federation in Keycloak..."
docker compose exec -T keycloak bash -c '
    for i in $(seq 1 10); do
        if curl -sf http://localhost:8080/realms/master > /dev/null 2>&1; then
            break
        fi
        echo "Waiting for Keycloak... ($i/10)"
        sleep 3
    done

    TOKEN=$(curl -s -X POST http://localhost:8080/realms/master/protocol/openid-connect/token \
        -d "client_id=admin-cli" -d "username=admin" \
        -d "password='"${KEYCLOAK_ADMIN_PASSWORD}"'" -d "grant_type=password" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)[\"access_token\"])" 2>/dev/null)

    if [[ -n "$TOKEN" ]]; then
        EXISTING=$(curl -s http://localhost:8080/admin/realms/'"${AD_REALM}"'/components?type=org.keycloak.storage.UserStorageProvider \
            -H "Authorization: Bearer $TOKEN")
        HAS_LDAP=$(echo "$EXISTING" | python3 -c "import sys,json; print(any(c.get(\"providerId\")==\"ldap\" for c in json.load(sys.stdin)))" 2>/dev/null)

        if [[ "$HAS_LDAP" != "True" ]]; then
            echo "LDAP federation not found. Run setup-ldap-federation.sh to configure it."
        else
            echo "LDAP federation already configured."
        fi
    fi
' 2>/dev/null || warn "LDAP federation check failed (run setup-ldap-federation.sh manually)"

log ""
info "==========================================="
info "Deployment Complete!"
info "==========================================="
echo ""
info "Services:"
info "  Keycloak:     https://${KEYCLOAK_HOSTNAME}"
info "  Keycloak Admin: https://${KEYCLOAK_HOSTNAME}/admin (admin / ${KEYCLOAK_ADMIN_PASSWORD})"
info "  LAM (AD UI):  http://<server-ip>:8081 (internal only, requires --profile internal)"
info "  Samba AD:     ldap://samba:389 (internal only)"
echo ""
info "Next Steps:"
info "  1. If first deploy: Setup LDAP federation"
info "     docker exec rentoption-keycloak /scripts/setup-ldap-federation.sh"
info "  2. Create users in Samba AD:"
info "     docker exec rentoption-samba /scripts/create-user.sh <username> -f <first> -l <last>"
info "  3. Sync users in Keycloak admin console:"
info "     rentoption realm -> User Federation -> ldap -> Sync -> Full Sync"
info "  4. Test SSO login with an AD user"
echo ""
info "DNS Records Required:"
info "  ${KEYCLOAK_HOSTNAME}  A  <this-server-ip>"
echo ""
log "To view logs: docker compose logs -f [service]"
log "To stop: docker compose down"
