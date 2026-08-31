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

check_service samba
check_service keycloak

# LAM is optional (profile)
if docker compose --profile internal ps lam &>/dev/null; then
    check_service lam
fi

# ===========================================
# Post-deployment: Setup LDAP Federation (automatic)
# ===========================================
log "Running post-deployment tasks..."

# Wait for Keycloak to be accepting requests on the host port
log "Waiting for Keycloak to be reachable on port 8080..."
for i in $(seq 1 20); do
    if curl -sf http://localhost:8080/realms/master > /dev/null 2>&1; then
        break
    fi
    info "Waiting for Keycloak... (${i}/20)"
    sleep 5
done

# Idempotent: creates LDAP federation + attribute mappers, then triggers Full Sync.
log "Setting up LDAP federation in Keycloak..."
if bash "${PROJECT_DIR}/keycloak/setup-ldap-federation.sh"; then
    log "LDAP federation setup complete."
else
    warn "LDAP federation setup failed. Run manually: ./keycloak/setup-ldap-federation.sh"
fi

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
info "  1. Create users in Samba AD (they auto-sync via LDAP full sync above):"
info "     docker exec rentoption-samba /scripts/create-user.sh <username> -f <first> -l <last>"
info "  2. Test SSO login in Keycloak with an AD user"
info "  3. [Optional] Add AD group -> Keycloak group sync (manual, may break KC26 user sync):"
info "     ./keycloak/scripts/mapper-group.sh"
echo ""
info "DNS Records Required:"
info "  ${KEYCLOAK_HOSTNAME}  A  <this-server-ip>"
echo ""
log "To view logs: docker compose logs -f [service]"
log "To stop: docker compose down"
