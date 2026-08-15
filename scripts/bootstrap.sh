#!/usr/bin/env bash
set -euo pipefail
log(){ printf '[bootstrap] %s\n' "$*"; }
need(){ command -v "$1" >/dev/null || { echo "missing tool: $1" >&2; exit 1; }; }
for x in curl openssl; do need "$x"; done
[[ "$(uname -s)" == Linux ]] || { echo 'Ubuntu/Linux required' >&2; exit 1; }
log 'Bootstrap is intentionally convergent: install packages only when absent, preserve persistent data, render configuration from registry/outputs, then health-check services.'
