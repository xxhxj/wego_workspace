#!/usr/bin/env bash
# 从项目根目录启动四个系统。没有 node_modules 时先 npm install。
# Linux 用 pm2 托管进程：本机有 pm2 就用它，没有则用 npx pm2，不要求 sudo。
# 用法：chmod +x start.sh stop.sh && ./start.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "未找到 Node.js 或 npm。请先安装 Node.js 18 或更高版本。"
  exit 1
fi

pm2cmd() {
  if command -v pm2 >/dev/null 2>&1; then
    pm2 "$@"
  else
    npx --yes pm2 "$@"
  fi
}

ensure_deps() {
  local dir="$1"
  if [[ ! -f "$dir/package.json" ]]; then
    echo "找不到 $dir/package.json"
    exit 1
  fi
  if [[ -f "$dir/.env.example" && ! -f "$dir/.env" ]]; then
    cp "$dir/.env.example" "$dir/.env"
    echo "已复制 $dir/.env，请先填写数据库等配置。"
  fi
  if [[ ! -d "$dir/node_modules" ]]; then
    echo "首次启动，正在安装依赖：$dir"
    (cd "$dir" && npm install)
  fi
}

start_one() {
  local name="$1"
  local dir="$2"
  shift 2
  if pm2cmd describe "$name" >/dev/null 2>&1; then
    pm2cmd delete "$name" >/dev/null 2>&1 || true
  fi
  pm2cmd start npm --name "$name" --cwd "$ROOT/$dir" -- "$@"
}

ensure_deps wego_sso/backend
ensure_deps wego_sso/frontend
ensure_deps wego_3d_texture/backend
ensure_deps wego_3d_texture/frontend
ensure_deps wego_fingertip_3d_web
ensure_deps wego_quiz_3d/backend
ensure_deps wego_quiz_3d/frontend

start_one wego-sso-api wego_sso/backend start
start_one wego-sso-web wego_sso/frontend run dev
start_one wego-mockup-api wego_3d_texture/backend start
start_one wego-mockup-web wego_3d_texture/frontend run dev
start_one wego-cad-web wego_fingertip_3d_web run dev
start_one wego-quiz-api wego_quiz_3d/backend start
start_one wego-quiz-web wego_quiz_3d/frontend run dev

echo
echo "单点登录  http://127.0.0.1:5174   接口 3001"
echo "包装样机  http://127.0.0.1:5173   接口 3000"
echo "三维建模  http://127.0.0.1:5175"
echo "答题闯关  http://127.0.0.1:5176   接口 3002"
echo "日志：pm2 logs    停止：./stop.sh"
echo "若希望开机自启，再执行：pm2 save && pm2 startup"
