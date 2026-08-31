#!/bin/bash
# ===========================================
# RentOption Infrastructure Backup Script
# Backups all persistent volumes and configurations
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
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

cd "${PROJECT_DIR}"

# Load environment
if [[ -f .env ]]; then
    export $(grep -v '^#' .env | xargs)
fi

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_NAME="rentoption-backup-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

log "Starting backup: ${BACKUP_NAME}"

# Create backup directory
mkdir -p "${BACKUP_PATH}"

# ===========================================
# Backup Docker Volumes
# ===========================================
log "Backing up Docker volumes..."

VOLUMES=(
    "rentoption-keycloak-data"
    "rentoption-samba-data"
    "rentoption-samba-etc"
    "rentoption-lam-config"
)

for volume in "${VOLUMES[@]}"; do
    log "Backing up volume: ${volume}"
    docker run --rm \
        -v "${volume}:/data:ro" \
        -v "${BACKUP_PATH}:/backup" \
        alpine tar czf "/backup/${volume}.tar.gz" -C /data . 2>/dev/null || warn "Failed to backup ${volume}"
done

# ===========================================
# Backup Certificates
# ===========================================
log "Backing up SSL certificates..."
if [[ -d "nginx/certbot/conf" ]]; then
    tar czf "${BACKUP_PATH}/certbot-conf.tar.gz" -C nginx/certbot conf 2>/dev/null || warn "Failed to backup certificates"
fi

# ===========================================
# Backup Configuration Files
# ===========================================
log "Backing up configuration files..."
tar czf "${BACKUP_PATH}/config.tar.gz" \
    .env \
    docker-compose.yml \
    nginx/ \
    keycloak/ \
    samba/ \
    lam/ \
    certbot/ \
    scripts/ \
    2>/dev/null || warn "Failed to backup config files"

# ===========================================
# Backup Samba AD (ldif export)
# ===========================================
log "Exporting Samba AD LDIF..."
if docker compose ps samba | grep -q "Up"; then
    docker compose exec -T samba samba-tool domain backup online --targetdir=/tmp/ad-backup 2>/dev/null || true
    docker compose exec -T samba tar czf /tmp/ad-backup.tar.gz -C /tmp ad-backup 2>/dev/null || true
    docker cp rentoption-samba:/tmp/ad-backup.tar.gz "${BACKUP_PATH}/samba-ad-ldif.tar.gz" 2>/dev/null || warn "Failed to export Samba AD"
fi

# ===========================================
# Create manifest
# ===========================================
cat > "${BACKUP_PATH}/MANIFEST.txt" <<EOF
RentOption Infrastructure Backup
================================
Date: $(date)
Hostname: $(hostname)
Backup Name: ${BACKUP_NAME}
Retention: ${RETENTION_DAYS} days

Contents:
EOF

for file in "${BACKUP_PATH}"/*; do
    if [[ -f "${file}" ]]; then
        size=$(du -h "${file}" | cut -f1)
        echo "  $(basename "${file}") - ${size}" >> "${BACKUP_PATH}/MANIFEST.txt"
    fi
done

# ===========================================
# Cleanup old backups
# ===========================================
log "Cleaning up backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -maxdepth 1 -type d -name "rentoption-backup-*" -mtime +${RETENTION_DAYS} -exec rm -rf {} \; 2>/dev/null || true

# ===========================================
# Summary
# ===========================================
BACKUP_SIZE=$(du -sh "${BACKUP_PATH}" | cut -f1)
log "Backup completed: ${BACKUP_PATH} (${BACKUP_SIZE})"
log "Manifest:"
cat "${BACKUP_PATH}/MANIFEST.txt"