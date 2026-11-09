#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/config/deploy.env"
[ -f "$ENV_FILE" ] || { echo "缺少 config/deploy.env"; exit 1; }
chmod 600 "$ENV_FILE" "$ROOT"/backend/*/.env 2>/dev/null || true
# shellcheck disable=SC1090
set -a
. "$ENV_FILE"
set +a

SSO_DOMAIN="${SSO_DOMAIN:-sso.$BASE_DOMAIN}"
MOCKUP_DOMAIN="${MOCKUP_DOMAIN:-mockup.$BASE_DOMAIN}"
CAD_DOMAIN="${CAD_DOMAIN:-cad.$BASE_DOMAIN}"
QUIZ_DOMAIN="${QUIZ_DOMAIN:-quiz.$BASE_DOMAIN}"
FILES_DOMAIN="${FILES_DOMAIN:-files.$BASE_DOMAIN}"
SCHEME="http"
[ "${ENABLE_TLS:-0}" = 1 ] && SCHEME="https"
SERVER_ROOT="${SERVER_ROOT:-$ROOT}"

if [ "${MINIO_PROXY:-0}" = 1 ] && [ -z "${MINIO_PROXY_TARGET:-}" ]; then
  MINIO_SCHEME="http"
  [ "${MINIO_USE_SSL:-false}" = "true" ] && MINIO_SCHEME="https"
  MINIO_PROXY_TARGET="$MINIO_SCHEME://$MINIO_ENDPOINT:$MINIO_PORT"
fi

command -v nginx >/dev/null 2>&1 || { echo "未安装 Nginx"; exit 1; }
if [ "${ENABLE_TLS:-0}" = 1 ]; then
  [ -n "${LETSENCRYPT_EMAIL:-}" ] || { echo "ENABLE_TLS=1 时必须填写 LETSENCRYPT_EMAIL"; exit 1; }
  command -v certbot >/dev/null 2>&1 || { echo "未安装 certbot"; exit 1; }
fi

if [ "$(id -u)" = 0 ]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
else
  echo "需要 root 或 sudo 才能安装 Nginx 配置。"; exit 1
fi

if "${SUDO[@]}" test -f /etc/nginx/conf.d/wego.conf && \
   "${SUDO[@]}" grep -q "ssl_certificate" /etc/nginx/conf.d/wego.conf && \
   [ "${FORCE_NGINX:-0}" != 1 ]; then
  echo "检测到 /etc/nginx/conf.d/wego.conf 已启用 HTTPS，拒绝用 HTTP 配置覆盖。"
  echo "确需覆盖请设置 FORCE_NGINX=1 后重试。"
  exit 1
fi

TEMPLATE="$ROOT/nginx/wego.conf.template"
RENDERED="$ROOT/nginx/wego.conf"
[ -f "$TEMPLATE" ] || { echo "缺少 nginx/wego.conf.template"; exit 1; }

sed \
  -e "s|__ROOT__|$SERVER_ROOT|g" \
  -e "s|__SSO_DOMAIN__|$SSO_DOMAIN|g" \
  -e "s|__MOCKUP_DOMAIN__|$MOCKUP_DOMAIN|g" \
  -e "s|__CAD_DOMAIN__|$CAD_DOMAIN|g" \
  -e "s|__QUIZ_DOMAIN__|$QUIZ_DOMAIN|g" \
  -e "s|__FILES_DOMAIN__|$FILES_DOMAIN|g" \
  -e "s|__MINIO_PROXY_TARGET__|${MINIO_PROXY_TARGET:-http://127.0.0.1:9000}|g" \
  "$TEMPLATE" | awk -v proxy="${MINIO_PROXY:-0}" '
    /^[[:space:]]*# __FILES_BEGIN__/ { infiles=1; next }
    /^[[:space:]]*# __FILES_END__/   { infiles=0; next }
    infiles && proxy != 1 { next }
    { print }
  ' > "$RENDERED"

echo "安装单文件 Nginx 配置到 /etc/nginx/conf.d/wego.conf"
"${SUDO[@]}" install -d /etc/nginx/conf.d
# 清理旧版按系统拆分的配置，避免重复 server_name
for old in wego-sso.conf wego-mockup.conf wego-cad.conf wego-quiz.conf wego-files.conf; do
  "${SUDO[@]}" rm -f "/etc/nginx/conf.d/$old"
done
"${SUDO[@]}" install -m 644 "$RENDERED" /etc/nginx/conf.d/wego.conf
"${SUDO[@]}" nginx -t
if ! "${SUDO[@]}" systemctl reload nginx 2>/dev/null; then
  "${SUDO[@]}" nginx -s reload
fi

if [ "${ENABLE_TLS:-0}" = 1 ]; then
  CERT_DOMAINS=(-d "$SSO_DOMAIN" -d "$MOCKUP_DOMAIN" -d "$CAD_DOMAIN" -d "$QUIZ_DOMAIN")
  if [ "${MINIO_PROXY:-0}" = 1 ]; then CERT_DOMAINS+=(-d "$FILES_DOMAIN"); fi
  "${SUDO[@]}" certbot --nginx "${CERT_DOMAINS[@]}" --non-interactive --agree-tos -m "$LETSENCRYPT_EMAIL" --redirect
  "${SUDO[@]}" nginx -t
  if ! "${SUDO[@]}" systemctl reload nginx 2>/dev/null; then
    "${SUDO[@]}" nginx -s reload
  fi
fi

echo "Nginx 完成。配置：$RENDERED -> /etc/nginx/conf.d/wego.conf"
printf '访问：%s://%s  %s://%s  %s://%s  %s://%s\n' "$SCHEME" "$SSO_DOMAIN" "$SCHEME" "$MOCKUP_DOMAIN" "$SCHEME" "$CAD_DOMAIN" "$SCHEME" "$QUIZ_DOMAIN"
