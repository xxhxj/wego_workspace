#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v pm2 >/dev/null 2>&1; then
  for name in wego-sso-api wego-mockup-api wego-quiz-api; do
    if pm2 describe "$name" >/dev/null 2>&1; then
      pm2 delete "$name" >/dev/null 2>&1 || true
      echo "已停止 pm2 进程：$name"
    fi
  done
fi

for app in sso mockup quiz; do
  pidfile="$ROOT/logs/$app.pid"
  if [ -f "$pidfile" ]; then
    pid="$(cat "$pidfile")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      echo "已停止 $app（PID $pid）"
    fi
    rm -f "$pidfile"
  fi
done
