#!/bin/bash
set -e

cd "$(dirname "$0")"
source .venv/bin/activate

HOST="${FLASK_HOST:-0.0.0.0}"
PORT="${FLASK_PORT:-5005}"

# For development: enable reloader so code changes are reflected immediately.
# The Cloudflare tunnel is NOT started here; use start.sh for the public tunnel.
PYTHONPATH=src:. FLASK_DEBUG=true python app.py
