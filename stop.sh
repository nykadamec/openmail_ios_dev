#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"

usage() { echo "Usage: ./stop.sh [--help]"; }
case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Chyba: neznámý argument: $1" >&2; usage >&2; exit 2 ;;
esac

stop_owned() {
  local file="$1" kind="$2" pid cmd
  [[ -f "$file" ]] || return 0
  pid="$(<"$file")"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    # PID files can outlive a process. Never kill a reused PID belonging to
    # an unrelated command.
    if { [[ "$kind" == flask && "$cmd" == *app.py* ]]; } ||
       { [[ "$kind" == cloudflared && "$cmd" == *cloudflared* && "$cmd" == *tunnel* ]]; }; then
      kill -TERM "$pid" 2>/dev/null || true
      echo "Zastaven $kind (PID $pid)."
    else
      echo "PID $pid není vlastněný openMail; nekončím cizí proces." >&2
    fi
  fi
  rm -f "$file"
}

stop_owned .flask.pid flask
stop_owned .cloudflared.pid cloudflared
echo "openMail stopped"
