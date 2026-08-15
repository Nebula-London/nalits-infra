#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/scripts/validate-registry.py" validate --file "$ROOT/registry/tenancies.yaml" --platform "$ROOT/registry/platform.yaml"
python3 "$ROOT/scripts/validate-registry.py" cidr --file "$ROOT/registry/tenancies.yaml" --tenancy production | grep -qx '10.64.48.0/20'
echo 'registry tests: OK'
