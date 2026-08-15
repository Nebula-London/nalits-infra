#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if grep -RInE '(BEGIN (RSA|OPENSSH|EC|PRIVATE) KEY|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN)' "$ROOT_DIR" --exclude-dir=.git --exclude='*.md' --exclude='*.example.*' --exclude='security-check.sh'; then
  echo 'Potential secret material found.' >&2; exit 1
fi
echo 'security checks: OK'
