#!/bin/bash
set -e

cd "$(dirname "$0")"
source .venv/bin/activate

# Kill any existing instances
lsof -ti:5005 | xargs kill 2>/dev/null || true

# Start Flask app (without reloader for tunnel stability)
HOST="${FLASK_HOST:-127.0.0.1}"
PORT="${FLASK_PORT:-5005}"
python -c "from app import app; app.run(host='$HOST', port=$PORT, debug=False, use_reloader=False)" > logs/app.log 2>&1 &
echo $! > .flask.pid

sleep 2

# Start Cloudflare tunnel
cloudflared tunnel --config ~/.cloudflared/config.yml run > logs/cloudflared.log 2>&1 &
echo $! > .cloudflared.pid

echo "Adamec.pro Mail started"
echo "Local:  http://127.0.0.1:5005"
echo "Public: https://email.adamec.pro"
echo "Logs:   logs/app.log, logs/cloudflared.log"
