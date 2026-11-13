#!/usr/bin/env bash
# orca.yaml scripts.setup — runs INSIDE the per-workspace environment.
# Installs openmail's Python dependencies into a local venv.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

if [ ! -f requirements.txt ]; then
  echo "setup.sh: requirements.txt not found in $repo_root" >&2
  exit 1
fi

if [ ! -x .venv/bin/python ]; then
  python3 -m venv .venv
fi
.venv/bin/pip install --quiet -r requirements.txt

.venv/bin/python -c "import flask" 2>/dev/null || {
  echo "setup.sh: flask import failed after install" >&2
  exit 1
}
echo "openmail setup: ok (venv at .venv)"
