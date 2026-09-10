#!/bin/bash
# ===========================================
# Certbot Renewal Script
# Runs via cron to renew Let's Encrypt certificates
# ===========================================

set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Load environment
if [[ -f /.env ]]; then
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        value="${value%\"}"; value="${value#\"}"; value="${value%\'}"; value="${value#\'}"
        export "${key}=${value}"
    done < /.env
fi

CERTBOT_EMAIL="${CERTBOT_EMAIL:-admin@rentoption.com}"
CERTBOT_DOMAINS="${CERTBOT_DOMAINS:-sso.rentoption.com}"
CERTBOT_STAGING="${CERTBOT_STAGING:-1}"

# Build certbot command
CERTBOT_CMD="certbot certonly --webroot --webroot-path=/var/www/certbot"
CERTBOT_CMD+=" --email ${CERTBOT_EMAIL}"
CERTBOT_CMD+=" --agree-tos --no-eff-email --non-interactive"

if [[ "${CERTBOT_STAGING}" == "1" ]]; then
    CERTBOT_CMD+=" --staging"
fi

for DOMAIN in ${CERTBOT_DOMAINS}; do
    CERTBOT_CMD+=" -d ${DOMAIN}"
done

log "Checking certificate renewal for: ${CERTBOT_DOMAINS}"

# Run renewal
if ${CERTBOT_CMD} --renew-by-default; then
    log "Certificate renewal successful"
    
    # Reload nginx to pick up new certificates
    log "Reloading nginx..."
    if docker kill --signal=HUP rentoption-nginx 2>/dev/null; then
        log "Nginx reloaded successfully"
    else
        log "Warning: Could not reload nginx (container not found)"
    fi
else
    log "ERROR: Certificate renewal failed"
    exit 1
fi