#!/bin/bash
# ===========================================
# RentOption Infrastructure Restore Script
# Restores from backup created by backup.sh
# ===========================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
BACKUP_DIR="${PROJECT_DIR}/backups"

cd "${PROJECT_DIR}"

# Check arguments
if [[ $# -lt 1 ]]; then
    error "Usage: $0 <backup-name|latest>"
    echo ""
    echo "Available backups:"
    ls -1 "${BACKUP_DIR}"/rentoption-backup-* 2>/dev/null | xargs -n1 basename | sort -r || echo "  No backups found"
    exit 1
fi

BACKUP_NAME="$1"

if [[ "${BACKUP_NAME}" == "latest" ]]; then
    BACKUP_NAME=$(ls -1 "${BACKUP_DIR}"/rentoption-backup-* 2>/dev/null | xargs -n1 basename | sort -r | head -1)
    if [[ -z "${BACKUP_NAME}" ]]; then
        error "No backups found"
        exit 1
    fi
    log "Using latest backup: ${BACKUP_NAME}"
fi

BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

if [[ ! -d "${BACKUP_PATH}" ]]; then
    error "Backup not found: ${BACKUP_PATH}"
    exit 1
fi

# Confirm
echo -e "${YELLOW}WARNING: This will restore data from ${BACKUP_NAME}${NC}"
echo -e "${YELLOW}All current data will be OVERWRITTEN!${NC}"
read -p "Are you sure? Type 'yes' to continue: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    log "Restore cancelled"
    exit 0
fi

# Stop services
log "Stopping services..."
docker compose down -v 2>/dev/null || true

# ===========================================
# Restore Docker Volumes
# ===========================================
log "Restoring Docker volumes..."

VOLUMES=(
    "rentoption-keycloak-data"
    "rentoption-samba-data"
    "rentoption-samba-etc"
    "rentoption-lam-config"
)

for volume in "${VOLUMES[@]}"; do
    BACKUP_FILE="${BACKUP_PATH}/${volume}.tar.gz"
    if [[ -f "${BACKUP_FILE}" ]]; then
        log "Restoring volume: ${volume}"
        # Create volume if not exists
        docker volume create "${volume}" 2>/dev/null || true
        docker run --rm \
            -v "${volume}:/data" \
            -v "${BACKUP_PATH}:/backup" \
            alpine tar xzf "/backup/${volume}.tar.gz" -C /data 2>/dev/null || warn "Failed to restore ${volume}"
    else
        warn "Backup file not found for ${volume}"
    fi
done

# ===========================================
# Restore Certificates
# ===========================================
log "Restoring SSL certificates..."
if [[ -f "${BACKUP_PATH}/certbot-conf.tar.gz" ]]; then
    tar xzf "${BACKUP_PATH}/certbot-conf.tar.gz" -C nginx/certbot 2>/dev/null || warn "Failed to restore certificates"
fi

# ===========================================
# Restore Configuration Files
# ===========================================
log "Restoring configuration files..."
if [[ -f "${BACKUP_PATH}/config.tar.gz" ]]; then
    tar xzf "${BACKUP_PATH}/config.tar.gz" 2>/dev/null || warn "Failed to restore config files"
fi

# ===========================================
# Restore Samba AD
# ===========================================
log "Restoring Samba AD..."
if [[ -f "${BACKUP_PATH}/samba-ad-ldif.tar.gz" ]]; then
    # Start samba temporarily
    docker compose up -d samba
    sleep 30
    
    # Copy backup to container
    docker cp "${BACKUP_PATH}/samba-ad-ldif.tar.gz" rentoption-samba:/tmp/
    
    # Restore
    docker compose exec -T samba tar xzf /tmp/samba-ad-ldif.tar.gz -C /tmp 2>/dev/null || true
    docker compose exec -T samba samba-tool domain backup online --targetdir=/tmp/ad-restore 2>/dev/null || true
    
    log "Samba AD restore initiated (may require manual completion)"
fi

# ===========================================
# Start Services
# ===========================================
log "Starting services..."
docker compose up -d

# Wait for services
log "Waiting for services to start..."
sleep 30

# Health check
for service in keycloak samba; do
    for i in {1..20}; do
        if docker compose ps ${service} | grep -q "healthy"; then
            log "${service} is healthy"
            break
        fi
        sleep 5
    done
done

log "Restore completed: ${BACKUP_NAME}"
log "Verify services are working correctly"