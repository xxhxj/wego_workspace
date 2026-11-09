#!/usr/bin/env bash
# 停止 start.sh 交给 pm2 的七个进程。
set -euo pipefail
pm2cmd() {
  if command -v pm2 >/dev/null 2>&1; then
    pm2 "$@"
  else
    npx --yes pm2 "$@"
  fi
}
for name in wego-sso-api wego-sso-web wego-mockup-api wego-mockup-web wego-cad-web wego-quiz-api wego-quiz-web; do
  if pm2cmd describe "$name" >/dev/null 2>&1; then
    pm2cmd delete "$name"
  fi
done
echo "已停止。"
