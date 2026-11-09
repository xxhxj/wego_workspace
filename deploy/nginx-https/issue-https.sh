#!/usr/bin/env bash
# 一键签发 wego 的 HTTPS 证书，并切换到 HTTPS 配置。
# 用法：./issue-https.sh 你的邮箱@example.com
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_DOMAIN="${BASE_DOMAIN:-xzyang.cn}"
DOMAIN_NAMES="${DOMAINS:-sso mockup cad quiz files}"
EMAIL="${1:-${EMAIL:-}}"
NGINX_BIN="${NGINX_BIN:-/opt/others/sound_sea_party/front/nginx-1.28.2/sbin/nginx}"
NGINX_CONF="${NGINX_CONF:-/opt/others/sound_sea_party/front/nginx-1.28.2/conf/nginx.conf}"
CONF_DIR="${CONF_DIR:-$(dirname "$NGINX_CONF")/conf.d}"
WEBROOT="${WEBROOT:-/var/www/certbot}"
WEB_ROOT="${WEB_ROOT:-/opt/others/deployWego/wego}"
CERT_NAME="${CERT_NAME:-sso.$BASE_DOMAIN}"
LOG_FILE="${LOG_FILE:-/var/log/wego-issue-https.log}"
HOOK_FILE="/etc/letsencrypt/renewal-hooks/deploy/reload-wego-nginx.sh"
CRON_FILE="/etc/cron.d/wego-cert-renew"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "请用 root 运行"
[ -n "$EMAIL" ] || die "用法：./issue-https.sh 你的邮箱@example.com"
[[ "$EMAIL" == *@*.* ]] || die "邮箱格式不对：$EMAIL"
[ -x "$NGINX_BIN" ] || die "找不到 Nginx：$NGINX_BIN"
[ -f "$NGINX_CONF" ] || die "找不到 Nginx 配置：$NGINX_CONF"
[ -f "$SCRIPT_DIR/wego.conf.http-first" ] || die "缺少 $SCRIPT_DIR/wego.conf.http-first"
[ -f "$SCRIPT_DIR/wego.conf" ] || die "缺少 $SCRIPT_DIR/wego.conf"
[ -f "$SCRIPT_DIR/renew-https.sh" ] || die "缺少 $SCRIPT_DIR/renew-https.sh"
command -v certbot >/dev/null 2>&1 || die "未安装 certbot，先执行 yum install -y certbot"
command -v getent >/dev/null 2>&1 || die "缺少 getent 命令"

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

read -r -a NAMES <<< "$DOMAIN_NAMES"
FQDNS=()
for name in "${NAMES[@]}"; do
  FQDNS+=("$name.$BASE_DOMAIN")
done
[ "${#FQDNS[@]}" -gt 0 ] || die "DOMAINS 为空"

log "===== 签发开始，域名：${FQDNS[*]} ====="

log "检查 DNS 解析"
MISSING=()
for fqdn in "${FQDNS[@]}"; do
  ip="$(getent hosts "$fqdn" | awk '{print $1; exit}')"
  if [ -n "$ip" ]; then
    log "  $fqdn -> $ip"
  else
    MISSING+=("$fqdn")
  fi
done
if [ "${#MISSING[@]}" -gt 0 ]; then
  printf '错误：以下域名未解析：\n' >&2
  printf '  %s\n' "${MISSING[@]}" >&2
  exit 1
fi

mkdir -p "$CONF_DIR" "$WEBROOT"
chmod 755 "$WEBROOT"

render_conf() {
  sed \
    -e "s|xzyang\.cn|$BASE_DOMAIN|g" \
    -e "s|/opt/others/deployWego/wego|$WEB_ROOT|g" \
    -e "s|/etc/letsencrypt/live/sso\.$BASE_DOMAIN|/etc/letsencrypt/live/$CERT_NAME|g" \
    "$1"
}

install_conf() {
  local src="$1"
  local tmp="$CONF_DIR/.wego.conf.tmp"
  render_conf "$src" > "$tmp"
  chmod 644 "$tmp"
  mv -f "$tmp" "$CONF_DIR/wego.conf"
}

reload_nginx() {
  "$NGINX_BIN" -t -c "$NGINX_CONF"
  "$NGINX_BIN" -s reload -c "$NGINX_CONF"
}

log "安装 HTTP 配置：$CONF_DIR/wego.conf"
install_conf "$SCRIPT_DIR/wego.conf.http-first"
reload_nginx

if ! "$NGINX_BIN" -T -c "$NGINX_CONF" 2>/dev/null | grep -Fq "server_name ${FQDNS[0]};"; then
  die "wego.conf 没有被 Nginx 加载：请在 $NGINX_CONF 的 http {} 中加入 include $CONF_DIR/*.conf;"
fi
log "确认 wego.conf 已被加载"

log "申请证书（certbot webroot）"
CERTBOT_ARGS=(
  certonly
  --webroot -w "$WEBROOT"
  --cert-name "$CERT_NAME"
  --agree-tos
  --no-eff-email
  --non-interactive
  --expand
  -m "$EMAIL"
)
for fqdn in "${FQDNS[@]}"; do
  CERTBOT_ARGS+=(-d "$fqdn")
done
if ! certbot "${CERTBOT_ARGS[@]}"; then
  log "证书校验失败，60 秒后自动重试一次（常见于 DNS 偶发 SERVFAIL）"
  sleep 60
  certbot "${CERTBOT_ARGS[@]}"
fi

[ -f "/etc/letsencrypt/live/$CERT_NAME/fullchain.pem" ] || die "证书未生成：/etc/letsencrypt/live/$CERT_NAME/"

log "安装 HTTPS 配置"
install_conf "$SCRIPT_DIR/wego.conf"
reload_nginx

if ! "$NGINX_BIN" -T -c "$NGINX_CONF" 2>/dev/null | grep -Fq "ssl_certificate"; then
  die "HTTPS 配置未生效，请执行 $NGINX_BIN -T -c $NGINX_CONF 检查"
fi

log "安装续期后自动重载 Nginx 的钩子：$HOOK_FILE"
mkdir -p "$(dirname "$HOOK_FILE")"
cat > "$HOOK_FILE" <<EOF
#!/usr/bin/env bash
set -euo pipefail
"$NGINX_BIN" -t -c "$NGINX_CONF"
"$NGINX_BIN" -s reload -c "$NGINX_CONF"
EOF
chmod 755 "$HOOK_FILE"

log "安装每日续期任务：$CRON_FILE（每天 03:17 检查）"
mkdir -p /etc/cron.d
cat > "$CRON_FILE" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/snap/bin:/sbin:/bin
MAILTO=""
17 3 * * * root /bin/bash "$SCRIPT_DIR/renew-https.sh" >> /var/log/wego-cert-renew.log 2>&1
EOF
chmod 644 "$CRON_FILE"
if command -v pgrep >/dev/null 2>&1 && ! pgrep -x crond >/dev/null 2>&1; then
  log "警告：crond 未运行，定时续期不会生效，请执行 systemctl enable --now crond"
fi

log "手动执行一次续期检查（未到期不会重复签发）"
bash "$SCRIPT_DIR/renew-https.sh" || log "续期检查返回非 0，请查看 /var/log/wego-cert-renew.log"

if command -v curl >/dev/null 2>&1; then
  log "HTTPS 访问检查"
  for fqdn in "${FQDNS[@]}"; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$fqdn/" || true)"
    log "  https://$fqdn -> ${code:-失败}"
  done
fi

log "完成。证书：/etc/letsencrypt/live/$CERT_NAME/"
log "续期日志：/var/log/wego-cert-renew.log"
log "别忘了：前端要用 BASE_DOMAIN=$BASE_DOMAIN、ENABLE_TLS=1 重新打包并重启后端。"
