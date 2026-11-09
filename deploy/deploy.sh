#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/deploy.env"
NGINX_DIR="$SCRIPT_DIR/nginx"
ECOSYSTEM="$SCRIPT_DIR/ecosystem.config.cjs"

log() { printf '\n== %s ==\n' "$*"; }
warn() { printf '警告：%s\n' "$*" >&2; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

[ -f "$ENV_FILE" ] || die "缺少 $ENV_FILE，请先复制 deploy.env.example 为 deploy.env 并填写。"
# shellcheck disable=SC1090
set -a
. "$ENV_FILE"
set +a

require() { [ -n "${!1:-}" ] || die "deploy.env 缺少 $1"; }
for key in BASE_DOMAIN MYSQL_HOST MYSQL_PORT MYSQL_USER MYSQL_PASSWORD SSO_DB MOCKUP_DB QUIZ_DB MINIO_ENDPOINT MINIO_PORT MINIO_ACCESS_KEY MINIO_SECRET_KEY MINIO_BUCKET QUIZ_TOKEN_SECRET; do
  require "$key"
done

[ "$BASE_DOMAIN" != "your-domain.com" ] || die "请把 deploy.env 的 BASE_DOMAIN 改成正式域名。"
[ "$QUIZ_TOKEN_SECRET" != "change-me-too" ] || die "请把 QUIZ_TOKEN_SECRET 改成强随机值。"
case "${ENABLE_TLS:-0}" in
  0|1) ;;
  *) die "ENABLE_TLS 只能是 0 或 1" ;;
esac

SSO_DOMAIN="${SSO_DOMAIN:-sso.$BASE_DOMAIN}"
MOCKUP_DOMAIN="${MOCKUP_DOMAIN:-mockup.$BASE_DOMAIN}"
CAD_DOMAIN="${CAD_DOMAIN:-cad.$BASE_DOMAIN}"
QUIZ_DOMAIN="${QUIZ_DOMAIN:-quiz.$BASE_DOMAIN}"
FILES_DOMAIN="${FILES_DOMAIN:-files.$BASE_DOMAIN}"
SCHEME="http"
[ "${ENABLE_TLS:-0}" = 1 ] && SCHEME="https"

SSO_PUBLIC_URL="$SCHEME://$SSO_DOMAIN"
MOCKUP_PUBLIC_URL="$SCHEME://$MOCKUP_DOMAIN"
CAD_PUBLIC_URL="$SCHEME://$CAD_DOMAIN"
QUIZ_PUBLIC_URL="$SCHEME://$QUIZ_DOMAIN"
FILES_PUBLIC_URL="$SCHEME://$FILES_DOMAIN"
ALLOWED_HOSTS="$SSO_DOMAIN,$MOCKUP_DOMAIN,$CAD_DOMAIN,$QUIZ_DOMAIN"

MINIO_PUBLIC_BASE="${MINIO_PUBLIC_BASE:-}"
if [ -z "$MINIO_PUBLIC_BASE" ]; then
  [ "${MINIO_PROXY:-0}" = 1 ] || die "MINIO_PUBLIC_BASE 为空时必须设置 MINIO_PROXY=1，或填写一个浏览器可访问的 HTTPS 地址。"
  MINIO_PUBLIC_BASE="$FILES_PUBLIC_URL/$MINIO_BUCKET"
fi
if [ "${ENABLE_TLS:-0}" = 1 ] && [[ "$MINIO_PUBLIC_BASE" == http://* ]]; then
  die "HTTPS 页面的图片地址不能是 http://，请把 MINIO_PUBLIC_BASE 改成 https 或使用 MINIO_PROXY=1。"
fi
if [ "${MINIO_PROXY:-0}" = 1 ] && [ -z "${MINIO_PROXY_TARGET:-}" ]; then
  MINIO_SCHEME="http"
  [ "${MINIO_USE_SSL:-false}" = "true" ] && MINIO_SCHEME="https"
  MINIO_PROXY_TARGET="$MINIO_SCHEME://$MINIO_ENDPOINT:$MINIO_PORT"
fi

SSO_API_URL="${SSO_API_URL:-http://127.0.0.1:3001}"
JWT_EXPIRES="${JWT_EXPIRES:-12h}"
RUN_SEED="${RUN_SEED:-0}"
FORCE_INSTALL="${FORCE_INSTALL:-0}"
PM2_CMD="${PM2_CMD:-pm2}"

log "目标"
printf 'ROOT=%s\n' "$ROOT"
printf 'SSO=%s\nMOCKUP=%s\nCAD=%s\nQUIZ=%s\nFILES=%s\n' \
  "$SSO_PUBLIC_URL" "$MOCKUP_PUBLIC_URL" "$CAD_PUBLIC_URL" "$QUIZ_PUBLIC_URL" "$FILES_PUBLIC_URL"
printf 'MySQL=%s:%s/%s\nMinIO=%s:%s/%s\nTLS=%s SEED=%s\n' \
  "$MYSQL_HOST" "$MYSQL_PORT" "$SSO_DB" "$MINIO_ENDPOINT" "$MINIO_PORT" "$MINIO_BUCKET" "$ENABLE_TLS" "$RUN_SEED"

command -v node >/dev/null 2>&1 || die "未安装 Node.js"
command -v npm >/dev/null 2>&1 || die "未安装 npm"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 20 ] || die "需要 Node.js 20 或更高版本（建议 22 LTS）"
command -v nginx >/dev/null 2>&1 || die "未安装 Nginx"
command -v "$PM2_CMD" >/dev/null 2>&1 || die "未安装 pm2，请先执行 npm install -g pm2"
if [ "${ENABLE_TLS:-0}" = 1 ]; then
  [ -n "${LETSENCRYPT_EMAIL:-}" ] || die "ENABLE_TLS=1 时必须填写 LETSENCRYPT_EMAIL"
  command -v certbot >/dev/null 2>&1 || die "未安装 certbot，请先安装 certbot 和 python3-certbot-nginx"
fi

for dir in wego_sso wego_3d_texture wego_fingertip_3d_web wego_quiz_3d; do
  [ -d "$ROOT/$dir" ] || die "找不到 $ROOT/$dir，请先把四个仓库 clone 到这个目录（名称保持不变）。"
done

check_tcp() {
  local host="$1"
  local port="$2"
  local label="$3"
  command -v timeout >/dev/null 2>&1 || return 0
  if timeout 3 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
    printf 'OK  %s %s:%s\n' "$label" "$host" "$port"
  else
    warn "$label 连不上 $host:$port，请检查地址、防火墙和安全组。"
  fi
}
check_tcp "$MYSQL_HOST" "$MYSQL_PORT" "MySQL"
check_tcp "$MINIO_ENDPOINT" "$MINIO_PORT" "MinIO"

if [ "${PREFLIGHT_ONLY:-0}" = 1 ]; then
  log "预检通过（PREFLIGHT_ONLY=1，未修改任何文件）"
  exit 0
fi

backup_env() {
  local file="$1"
  if [ -f "$file" ]; then
    cp -p "$file" "$file.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

write_env() {
  local file="$1"
  backup_env "$file"
  umask 077
  cat > "$file"
  chmod 600 "$file"
}

log "写入后端 .env"
write_env "$ROOT/wego_sso/backend/.env" <<EOF
PORT=3001
MYSQL_HOST=$MYSQL_HOST
MYSQL_PORT=$MYSQL_PORT
MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_DATABASE=$SSO_DB
JWT_EXPIRES=$JWT_EXPIRES
JWT_KEYS_DIR=$ROOT/wego_sso/backend/keys
EOF

write_env "$ROOT/wego_3d_texture/backend/.env" <<EOF
PORT=3000
MYSQL_HOST=$MYSQL_HOST
MYSQL_PORT=$MYSQL_PORT
MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_DATABASE=$MOCKUP_DB
MINIO_ENDPOINT=$MINIO_ENDPOINT
MINIO_PORT=$MINIO_PORT
MINIO_USE_SSL=${MINIO_USE_SSL:-false}
MINIO_ACCESS_KEY=$MINIO_ACCESS_KEY
MINIO_SECRET_KEY=$MINIO_SECRET_KEY
MINIO_BUCKET=$MINIO_BUCKET
MINIO_PUBLIC_BASE=$MINIO_PUBLIC_BASE
SSO_API_URL=$SSO_API_URL
SSO_DATABASE=$SSO_DB
EOF

write_env "$ROOT/wego_quiz_3d/backend/.env" <<EOF
PORT=3002
MYSQL_HOST=$MYSQL_HOST
MYSQL_PORT=$MYSQL_PORT
MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_DATABASE=$QUIZ_DB
MYSQL_TIMEZONE=${MYSQL_TIMEZONE:-+08:00}
SSO_API_URL=$SSO_API_URL
SSO_DATABASE=$SSO_DB
QUIZ_TOKEN_SECRET=$QUIZ_TOKEN_SECRET
EOF

install_app() {
  local dir="$1"
  local skip_electron="${2:-0}"
  local full="$ROOT/$dir"
  if [ "$FORCE_INSTALL" != 1 ] && [ -d "$full/node_modules" ]; then
    printf '依赖已存在，跳过：%s\n' "$dir"
    return
  fi
  log "安装依赖：$dir"
  (
    cd "$full"
    if [ -f package-lock.json ]; then
      if [ "$skip_electron" = 1 ]; then
        ELECTRON_SKIP_BINARY_DOWNLOAD=1 npm ci || npm install
      else
        npm ci || npm install
      fi
    else
      npm install
    fi
  )
}

install_app wego_sso/backend
install_app wego_sso/frontend
install_app wego_3d_texture/backend
install_app wego_3d_texture/frontend
install_app wego_fingertip_3d_web 1
install_app wego_quiz_3d/backend
install_app wego_quiz_3d/frontend

if [ "$RUN_SEED" = 1 ]; then
  log "初始化数据库（会写入演示账号，请确认这是空库或允许覆盖）"
  (cd "$ROOT/wego_sso/backend" && npm run seed)
  (cd "$ROOT/wego_3d_texture/backend" && npm run seed)
  (cd "$ROOT/wego_quiz_3d/backend" && npm run seed)
else
  log "跳过 seed（RUN_SEED=0）；空库首次部署请设为 1"
fi

log "构建前端"
(
  cd "$ROOT/wego_sso/frontend"
  VITE_ALLOWED_REDIRECT_HOSTS="$ALLOWED_HOSTS" \
  VITE_APP_MOCKUP_URL="$MOCKUP_PUBLIC_URL/" \
  VITE_APP_CAD_URL="$CAD_PUBLIC_URL/" \
  VITE_APP_QUIZ_URL="$QUIZ_PUBLIC_URL/" \
  npm run build
)
(
  cd "$ROOT/wego_3d_texture/frontend"
  VITE_SSO_WEB="$SSO_PUBLIC_URL" \
  VITE_SSO_API="$SSO_PUBLIC_URL" \
  VITE_PUBLIC_SHARE_BASE="$MOCKUP_PUBLIC_URL" \
  npm run build
)
(
  cd "$ROOT/wego_quiz_3d/frontend"
  VITE_SSO_WEB="$SSO_PUBLIC_URL" npm run build
)
(
  cd "$ROOT/wego_fingertip_3d_web"
  VITE_SSO_WEB="$SSO_PUBLIC_URL" \
  VITE_SSO_API="$SSO_PUBLIC_URL" \
  npm run build
)

log "更新 SSO 应用入口地址"
APP_ROOT="$ROOT" \
MOCKUP_PUBLIC_URL="$MOCKUP_PUBLIC_URL" \
CAD_PUBLIC_URL="$CAD_PUBLIC_URL" \
QUIZ_PUBLIC_URL="$QUIZ_PUBLIC_URL" \
node "$SCRIPT_DIR/update-app-urls.mjs" || warn "SSO 应用入口更新失败（数据库可能尚未 seed）。"

log "写入 PM2 配置并启动后端"
cat > "$ECOSYSTEM" <<EOF
module.exports = {
  apps: [
    { name: 'wego-sso-api', cwd: '$ROOT/wego_sso/backend', script: 'src/index.js', interpreter: 'node', env: { NODE_ENV: 'production' }, autorestart: true, max_memory_restart: '512M', time: true },
    { name: 'wego-mockup-api', cwd: '$ROOT/wego_3d_texture/backend', script: 'src/index.js', interpreter: 'node', env: { NODE_ENV: 'production' }, autorestart: true, max_memory_restart: '512M', time: true },
    { name: 'wego-quiz-api', cwd: '$ROOT/wego_quiz_3d/backend', script: 'src/index.js', interpreter: 'node', env: { NODE_ENV: 'production' }, autorestart: true, max_memory_restart: '512M', time: true }
  ]
};
EOF
"$PM2_CMD" startOrReload "$ECOSYSTEM" --update-env
"$PM2_CMD" save

log "生成单文件 Nginx 配置"
mkdir -p "$NGINX_DIR"
rm -f "$NGINX_DIR"/wego-sso.conf "$NGINX_DIR"/wego-mockup.conf "$NGINX_DIR"/wego-cad.conf "$NGINX_DIR"/wego-quiz.conf "$NGINX_DIR"/wego-files.conf
NGINX_TEMPLATE="$SCRIPT_DIR/bundle-template/nginx/wego.conf.template"
[ -f "$NGINX_TEMPLATE" ] || die "缺少 $NGINX_TEMPLATE"
sed \
  -e "s|__ROOT__/frontend/sso|$ROOT/wego_sso/frontend/dist|g" \
  -e "s|__ROOT__/frontend/mockup|$ROOT/wego_3d_texture/frontend/dist|g" \
  -e "s|__ROOT__/frontend/cad|$ROOT/wego_fingertip_3d_web/dist|g" \
  -e "s|__ROOT__/frontend/quiz|$ROOT/wego_quiz_3d/frontend/dist|g" \
  -e "s|__ROOT__|$ROOT|g" \
  -e "s|__SSO_DOMAIN__|$SSO_DOMAIN|g" \
  -e "s|__MOCKUP_DOMAIN__|$MOCKUP_DOMAIN|g" \
  -e "s|__CAD_DOMAIN__|$CAD_DOMAIN|g" \
  -e "s|__QUIZ_DOMAIN__|$QUIZ_DOMAIN|g" \
  -e "s|__FILES_DOMAIN__|$FILES_DOMAIN|g" \
  -e "s|__MINIO_PROXY_TARGET__|${MINIO_PROXY_TARGET:-http://127.0.0.1:9000}|g" \
  "$NGINX_TEMPLATE" | awk -v proxy="${MINIO_PROXY:-0}" '
    /^[[:space:]]*# __FILES_BEGIN__/ { infiles=1; next }
    /^[[:space:]]*# __FILES_END__/   { infiles=0; next }
    infiles && proxy != 1 { next }
    { print }
  ' > "$NGINX_DIR/wego.conf"

log "安装 Nginx 配置并重载"
sudo install -d /etc/nginx/conf.d
for old in wego-sso.conf wego-mockup.conf wego-cad.conf wego-quiz.conf wego-files.conf; do
  sudo rm -f "/etc/nginx/conf.d/$old"
done
sudo install -m 644 "$NGINX_DIR/wego.conf" /etc/nginx/conf.d/wego.conf
sudo nginx -t
sudo systemctl reload nginx

if [ "${ENABLE_TLS:-0}" = 1 ]; then
  log "申请/续期 HTTPS 证书"
  CERT_DOMAINS=(-d "$SSO_DOMAIN" -d "$MOCKUP_DOMAIN" -d "$CAD_DOMAIN" -d "$QUIZ_DOMAIN")
  if [ "${MINIO_PROXY:-0}" = 1 ]; then CERT_DOMAINS+=(-d "$FILES_DOMAIN"); fi
  sudo certbot --nginx "${CERT_DOMAINS[@]}" --non-interactive --agree-tos -m "$LETSENCRYPT_EMAIL" --redirect
  sudo nginx -t
  sudo systemctl reload nginx
fi

wait_backend() {
  local name="$1"
  local url="$2"
  for _ in $(seq 1 30); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      printf 'OK  %s %s\n' "$name" "$url"
      return 0
    fi
    sleep 1
  done
  warn "$name 健康检查失败：$url"
  return 1
}

log "健康检查"
wait_backend "SSO API" "http://127.0.0.1:3001/api/health" || true
wait_backend "Mockup API" "http://127.0.0.1:3000/api/health" || true
wait_backend "Quiz API" "http://127.0.0.1:3002/api/health" || true

for url in "$SSO_PUBLIC_URL" "$MOCKUP_PUBLIC_URL" "$CAD_PUBLIC_URL" "$QUIZ_PUBLIC_URL"; do
  code="$(curl -k -s -o /dev/null -w '%{http_code}' "$url" || true)"
  printf '%s -> %s\n' "$url" "$code"
done

log "完成"
printf 'SSO      %s\nMockup   %s\nCAD      %s\nQuiz     %s\n' "$SSO_PUBLIC_URL" "$MOCKUP_PUBLIC_URL" "$CAD_PUBLIC_URL" "$QUIZ_PUBLIC_URL"
printf '日志：%s logs\n进程：%s status\n' "$PM2_CMD" "$PM2_CMD"
printf '首次使用请确认 DNS 已解析、防火墙放行 80/443，并执行 %s save 与 %s startup。\n' "$PM2_CMD" "$PM2_CMD"
