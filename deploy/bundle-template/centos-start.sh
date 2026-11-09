#!/usr/bin/env bash
# CentOS 一键启动：校验环境 -> 首次安装后端依赖 -> 后台启动三个 Node 服务 -> 健康检查
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ENV_FILE="$ROOT/config/deploy.env"
[ -f "$ENV_FILE" ] || { echo "缺少 config/deploy.env"; exit 1; }
chmod 600 "$ENV_FILE" "$ROOT"/backend/*/.env 2>/dev/null || true
chmod +x "$ROOT"/*.sh 2>/dev/null || true
# Windows/SFTP 上传的文件可能变成 600，Nginx 读不到会报 500
chmod -R u+rwX,go+rX "$ROOT/frontend" 2>/dev/null || true

command -v node >/dev/null 2>&1 || { echo "未安装 Node.js（建议 22 LTS）"; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "未安装 npm"; exit 1; }
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$NODE_MAJOR" -lt 20 ]; then
  echo "需要 Node.js 20+（建议 22 LTS），当前：$(node -v)"
  exit 1
fi

need_install=0
for app in sso mockup quiz; do
  [ -f "$ROOT/backend/$app/src/index.js" ] || { echo "缺少 backend/$app/src/index.js"; exit 1; }
  [ -f "$ROOT/backend/$app/.env" ] || { echo "缺少 backend/$app/.env"; exit 1; }
  [ -d "$ROOT/backend/$app/node_modules" ] || need_install=1
done

if [ "$need_install" = 1 ] || [ "${FORCE_INSTALL:-0}" = 1 ]; then
  echo "安装后端生产依赖（只装后端，不在服务器构建前端）"
  FORCE_INSTALL="$FORCE_INSTALL" bash "$ROOT/install-backends.sh"
fi

bash "$ROOT/start-backends.sh"

if command -v curl >/dev/null 2>&1; then
  echo
  echo "健康检查："
  for port in 3001 3000 3002; do
    ok=0
    for _ in $(seq 1 20); do
      if curl -fsS "http://127.0.0.1:$port/api/health" >/dev/null 2>&1; then
        ok=1
        break
      fi
      sleep 1
    done
    if [ "$ok" = 1 ]; then
      echo "  127.0.0.1:$port 正常"
    else
      echo "  127.0.0.1:$port 未就绪，查看日志：pm2 logs 或 tail -f logs/*.log"
    fi
  done
fi

# shellcheck disable=SC1090
set -a
. "$ENV_FILE"
set +a
SCHEME="http"
[ "${ENABLE_TLS:-0}" = 1 ] && SCHEME="https"
echo
echo "后端已后台启动："
echo "  单点登录  $SCHEME://${SSO_DOMAIN:-sso.$BASE_DOMAIN}   接口 3001"
echo "  包装样机  $SCHEME://${MOCKUP_DOMAIN:-mockup.$BASE_DOMAIN}   接口 3000"
echo "  三维建模  $SCHEME://${CAD_DOMAIN:-cad.$BASE_DOMAIN}"
echo "  答题闯关  $SCHEME://${QUIZ_DOMAIN:-quiz.$BASE_DOMAIN}   接口 3002"
echo "Nginx 未安装时执行：./install-nginx.sh"
echo "停止：./stop-backends.sh    日志：pm2 logs 或 tail -f logs/*.log"
