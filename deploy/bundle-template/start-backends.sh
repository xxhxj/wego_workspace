#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS=(sso mockup quiz)
NAMES=(wego-sso-api wego-mockup-api wego-quiz-api)

chmod 600 "$ROOT"/backend/*/.env "$ROOT"/config/deploy.env 2>/dev/null || true

command -v node >/dev/null 2>&1 || { echo "未安装 Node.js"; exit 1; }

for app in "${APPS[@]}"; do
  [ -f "$ROOT/backend/$app/src/index.js" ] || { echo "缺少 backend/$app/src/index.js"; exit 1; }
  [ -f "$ROOT/backend/$app/.env" ] || { echo "缺少 backend/$app/.env"; exit 1; }
  [ -d "$ROOT/backend/$app/node_modules" ] || {
    echo "backend/$app/node_modules 不存在，请先执行 ./install-backends.sh"
    exit 1
  }
done

if command -v pm2 >/dev/null 2>&1; then
  echo "使用 pm2 启动三个后端"
  (cd "$ROOT" && pm2 startOrReload ecosystem.config.cjs --update-env && pm2 save)
  if [ -f "$ROOT/update-app-urls.sh" ]; then
    echo "更新 SSO 系统入口地址"
    (cd "$ROOT" && bash update-app-urls.sh) || echo "警告：SSO 入口地址更新失败（数据库可能尚未 seed）。"
  fi
  echo "pm2 status 可查看状态；pm2 logs 可查看日志。"
  exit 0
fi

echo "未安装 pm2，使用 nohup 启动；生产环境建议安装 pm2。"
mkdir -p "$ROOT/logs"

start_one() {
  local app="$1"
  local dir="$ROOT/backend/$app"
  local pidfile="$ROOT/logs/$app.pid"
  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "$app 已在运行，PID $(cat "$pidfile")"
    return
  fi
  (
    cd "$dir"
    nohup node src/index.js > "$ROOT/logs/$app.log" 2>&1 &
    echo $! > "$pidfile"
  )
  echo "已启动 $app，日志 logs/$app.log"
}

start_one sso
sleep 1
start_one mockup
start_one quiz

if [ -f "$ROOT/update-app-urls.sh" ]; then
  echo "更新 SSO 系统入口地址"
  (cd "$ROOT" && bash update-app-urls.sh) || echo "警告：SSO 入口地址更新失败（数据库可能尚未 seed）。"
fi
