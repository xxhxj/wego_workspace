#!/usr/bin/env bash
# 定期续期 wego 的 Let's Encrypt 证书。
# 由 /etc/cron.d/wego-cert-renew 每天调用；也可以手动执行。
set -euo pipefail

NGINX_BIN="${NGINX_BIN:-/opt/others/sound_sea_party/front/nginx-1.28.2/sbin/nginx}"
NGINX_CONF="${NGINX_CONF:-/opt/others/sound_sea_party/front/nginx-1.28.2/conf/nginx.conf}"
HOOK_FILE="/etc/letsencrypt/renewal-hooks/deploy/reload-wego-nginx.sh"
LOG_FILE="${LOG_FILE:-/var/log/wego-cert-renew.log}"

[ "$(id -u)" = 0 ] || { echo "请用 root 运行" >&2; exit 1; }
command -v certbot >/dev/null 2>&1 || { echo "未安装 certbot" >&2; exit 1; }
mkdir -p "$(dirname "$LOG_FILE")"

{
  echo "===== $(date '+%F %T') 开始检查续期 ====="
  certbot renew --quiet
  if [ ! -x "$HOOK_FILE" ]; then
    # 钩子缺失时兜底：手动校验并重载，避免续期后 Nginx 仍用旧证书
    "$NGINX_BIN" -t -c "$NGINX_CONF"
    "$NGINX_BIN" -s reload -c "$NGINX_CONF"
    echo "未找到续期钩子，已手动重载 Nginx"
  fi
  echo "===== $(date '+%F %T') 完成 ====="
} >> "$LOG_FILE" 2>&1
