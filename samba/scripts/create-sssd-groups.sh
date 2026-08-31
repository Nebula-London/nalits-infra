#!/bin/bash
# ===========================================
# Create SSSD AD groups for SSH access control
# root-sssd: SSH + sudo (full access)
# non-root-sssd: SSH only (no sudo)
# ===========================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"; }

SAMBA_ADMIN_PASS="${SAMBA_ADMIN_PASS:-ChangeMe_SambaAdmin_2024!}"

log "Creating SSSD AD groups..."

samba-tool group add "root-sssd" --group-scope=Global --group-type=Security \
    -U administrator --password="${SAMBA_ADMIN_PASS}" 2>/dev/null && \
    log "Created group 'root-sssd' (SSH + sudo)" || \
    warn "Group 'root-sssd' may already exist"

samba-tool group add "non-root-sssd" --group-scope=Global --group-type=Security \
    -U administrator --password="${SAMBA_ADMIN_PASS}" 2>/dev/null && \
    log "Created group 'non-root-sssd' (SSH only)" || \
    warn "Group 'non-root-sssd' may already exist"

log "SSSD groups ready. Assign users with:"
log "  samba-tool group addmembers root-sssd <username>      # SSH + sudo"
log "  samba-tool group addmembers non-root-sssd <username>  # SSH only"
