#!/bin/bash
cd "$(dirname "$0")"

if [ -f .flask.pid ]; then
  kill $(cat .flask.pid) 2>/dev/null || true
  rm -f .flask.pid
fi

if [ -f .cloudflared.pid ]; then
  kill $(cat .cloudflared.pid) 2>/dev/null || true
  rm -f .cloudflared.pid
fi

echo "openMail stopped"
