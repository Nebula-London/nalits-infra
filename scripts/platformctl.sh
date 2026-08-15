#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; REG="$ROOT/registry/tenancies.yaml"; PLATFORM="$ROOT/registry/platform.yaml"
cmd="${1:-}"; sub="${2:-}"
case "$cmd/$sub" in
  tenancy/onboard) name="${3:-}"; [[ "$name" == --name ]] || { echo 'usage: platformctl.sh tenancy onboard --name NAME --purpose PURPOSE --environment ENV'; exit 2; }; name="${4:-}"; python3 "$ROOT/scripts/validate-registry.py" validate --file "$REG" --platform "$PLATFORM"; echo "Onboarding is declarative: add $name to registry, authorize its OCI tenancy, then run terraform/stacks/tenancy." ;;
  validate/) python3 "$ROOT/scripts/validate-registry.py" validate --file "$REG" --platform "$PLATFORM" ;;
  *) echo 'commands: tenancy onboard | validate'; exit 2;;
esac
