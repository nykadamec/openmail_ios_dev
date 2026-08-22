#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"

MODE="cloudflare"
HOST="${FLASK_HOST:-0.0.0.0}"
PORT="${FLASK_PORT:-5005}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: ./start.sh [cloudflare|tailscale] [host] [port] [--dry-run]
Without arguments the cloudflare mode is used. Host and port default to
FLASK_HOST/FLASK_PORT (or 0.0.0.0/5005).
EOF
}

POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY_RUN=true ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done
if ((${#POSITIONAL[@]} > 3)); then echo "Chyba: příliš mnoho argumentů." >&2; usage >&2; exit 2; fi
if ((${#POSITIONAL[@]} > 0)); then
  [[ ${POSITIONAL[0]} == cloudflare || ${POSITIONAL[0]} == tailscale ]] || { echo "Chyba: režim musí být cloudflare nebo tailscale." >&2; exit 2; }
  MODE="${POSITIONAL[0]}"
fi
[[ ${#POSITIONAL[@]} -lt 2 ]] || HOST="${POSITIONAL[1]}"
[[ ${#POSITIONAL[@]} -lt 3 ]] || PORT="${POSITIONAL[2]}"
[[ -n "$HOST" && "$HOST" =~ ^[A-Za-z0-9_.:-]+$ ]] || { echo "Chyba: neplatný bind host: $HOST" >&2; exit 2; }
[[ "$PORT" =~ ^[0-9]+$ ]] && ((PORT >= 1 && PORT <= 65535)) || { echo "Chyba: port musí být celé číslo 1–65535." >&2; exit 2; }

FLASK_PID_FILE=".flask.pid"
CLOUDFLARED_PID_FILE=".cloudflared.pid"
CONFIG="${CLOUDFLARED_CONFIG:-$HOME/.cloudflared/config.yml}"
pid_alive() { [[ -s "$1" ]] && kill -0 "$(<"$1")" 2>/dev/null; }
port_busy() { command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | grep -q .; }

if [[ "$DRY_RUN" == true ]]; then
  echo "DRY-RUN: režim=$MODE host=$HOST port=$PORT"
  echo "DRY-RUN: Flask -> PYTHONPATH=src:. python app.py"
  [[ "$MODE" == cloudflare ]] && echo "DRY-RUN: cloudflared tunnel --config $CONFIG run"
  exit 0
fi

if pid_alive "$FLASK_PID_FILE" || pid_alive "$CLOUDFLARED_PID_FILE"; then
  echo "Chyba: openMail již běží (PID soubor). Použijte ./stop.sh." >&2; exit 1
fi
if port_busy; then echo "Chyba: port $PORT již používá jiný proces; nespouštím duplicitní Flask." >&2; exit 1; fi
if [[ "$MODE" == cloudflare ]] && pgrep -f "cloudflared tunnel --config .* run" >/dev/null 2>&1; then
  echo "Chyba: cloudflared tunnel již běží; nespouštím duplicitní tunnel." >&2; exit 1
fi
if [[ "$MODE" == cloudflare ]]; then
  command -v cloudflared >/dev/null 2>&1 || { echo "Chyba: cloudflared není v PATH." >&2; exit 1; }
  [[ -f "$CONFIG" ]] || { echo "Chyba: chybí konfigurace cloudflared: $CONFIG" >&2; exit 1; }
fi
[[ -f .venv/bin/activate ]] || { echo "Chyba: chybí .venv/bin/activate." >&2; exit 1; }
mkdir -p logs
source .venv/bin/activate

FLASK_HOST="$HOST" FLASK_PORT="$PORT" PYTHONPATH=src:. python app.py >logs/app.log 2>&1 &
echo "$!" >"$FLASK_PID_FILE"
if [[ "$MODE" == cloudflare ]]; then
  sleep 2
  cloudflared tunnel --config "$CONFIG" run >logs/cloudflared.log 2>&1 &
  CLOUDFLARED_PID=$!
  echo "$CLOUDFLARED_PID" >"$CLOUDFLARED_PID_FILE"
fi
echo "openMail started ($MODE)"
echo "Local:  http://127.0.0.1:$PORT"
[[ "$MODE" == cloudflare ]] && echo "Public: https://email.adamec.pro"
if [[ "$MODE" == cloudflare ]]; then
  echo "Logs:   logs/app.log, logs/cloudflared.log"
else
  echo "Logs:   logs/app.log"
fi
