#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${DEPLOY_ENV:-$SCRIPT_DIR/deploy.env}"
SERVER_ROOT="${2:-${SERVER_ROOT:-/opt/wego}}"
FORCE_BUNDLE="${FORCE_BUNDLE:-0}"

log() { printf '\n== %s ==\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

to_unix_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1 && { [[ "$p" =~ ^[A-Za-z]:[\\/] ]] || [[ "$p" == \\\\* ]]; }; then
    cygpath -u "$p"
  else
    printf '%s' "$p"
  fi
}

OUT_ARG="${1:-${BUNDLE_OUT:-$SCRIPT_DIR/dist}}"
OUT="$(to_unix_path "$OUT_ARG")"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd -P)"
BUNDLE="$OUT/wego-bundle"
TARBALL="$OUT/wego-bundle.tar.gz"

[ -f "$ENV_FILE" ] || die "缺少 $ENV_FILE"
# shellcheck disable=SC1090
set -a
. "$ENV_FILE"
set +a

for key in BASE_DOMAIN MYSQL_HOST MYSQL_PORT MYSQL_USER MYSQL_PASSWORD SSO_DB MOCKUP_DB QUIZ_DB MINIO_ENDPOINT MINIO_PORT MINIO_ACCESS_KEY MINIO_SECRET_KEY MINIO_BUCKET QUIZ_TOKEN_SECRET; do
  [ -n "${!key:-}" ] || die "deploy.env 缺少 $key"
done
[ "$BASE_DOMAIN" != "your-domain.com" ] || die "请先把 deploy.env 的 BASE_DOMAIN 改成正式域名。"
[ "$QUIZ_TOKEN_SECRET" != "change-me-too" ] || die "请把 QUIZ_TOKEN_SECRET 改成强随机值。"
[[ "$SERVER_ROOT" == /* ]] || die "服务器部署目录必须是绝对路径，例如 /opt/wego（当前：$SERVER_ROOT）"

case "$BUNDLE" in
  / | "$HOME" | "$ROOT" | "$SCRIPT_DIR") die "输出目录不安全：$BUNDLE" ;;
esac
if [ -e "$BUNDLE" ]; then
  if [ "$FORCE_BUNDLE" != 1 ]; then
    die "输出目录已存在：$BUNDLE；确认覆盖请设置 FORCE_BUNDLE=1"
  fi
  if [ ! -f "$BUNDLE/.wego-bundle" ] && [ -n "$(ls -A "$BUNDLE" 2>/dev/null)" ]; then
    die "目标不是上次生成的 bundle，拒绝清空：$BUNDLE"
  fi
fi

SSO_DOMAIN="${SSO_DOMAIN:-sso.$BASE_DOMAIN}"
MOCKUP_DOMAIN="${MOCKUP_DOMAIN:-mockup.$BASE_DOMAIN}"
CAD_DOMAIN="${CAD_DOMAIN:-cad.$BASE_DOMAIN}"
QUIZ_DOMAIN="${QUIZ_DOMAIN:-quiz.$BASE_DOMAIN}"
FILES_DOMAIN="${FILES_DOMAIN:-files.$BASE_DOMAIN}"
ENABLE_TLS="${ENABLE_TLS:-0}"
SCHEME="http"
[ "$ENABLE_TLS" = 1 ] && SCHEME="https"
SSO_PUBLIC_URL="$SCHEME://$SSO_DOMAIN"
MOCKUP_PUBLIC_URL="$SCHEME://$MOCKUP_DOMAIN"
CAD_PUBLIC_URL="$SCHEME://$CAD_DOMAIN"
QUIZ_PUBLIC_URL="$SCHEME://$QUIZ_DOMAIN"
FILES_PUBLIC_URL="$SCHEME://$FILES_DOMAIN"
ALLOWED_HOSTS="$SSO_DOMAIN,$MOCKUP_DOMAIN,$CAD_DOMAIN,$QUIZ_DOMAIN"

MINIO_PUBLIC_BASE="${MINIO_PUBLIC_BASE:-}"
MINIO_PROXY="${MINIO_PROXY:-0}"
if [ -z "$MINIO_PUBLIC_BASE" ]; then
  [ "$MINIO_PROXY" = 1 ] || die "MINIO_PUBLIC_BASE 为空时必须设置 MINIO_PROXY=1。"
  MINIO_PUBLIC_BASE="$FILES_PUBLIC_URL/$MINIO_BUCKET"
fi
if [ "$MINIO_PROXY" = 1 ] && [ -z "${MINIO_PROXY_TARGET:-}" ]; then
  MINIO_SCHEME="http"
  [ "${MINIO_USE_SSL:-false}" = "true" ] && MINIO_SCHEME="https"
  MINIO_PROXY_TARGET="$MINIO_SCHEME://$MINIO_ENDPOINT:$MINIO_PORT"
fi
if [ "$MINIO_PROXY" = 1 ] && [ "$MINIO_ENDPOINT" != "127.0.0.1" ] && [[ "$MINIO_PROXY_TARGET" == *"127.0.0.1"* ]]; then
  printf '警告：MINIO_PROXY_TARGET=%s 指向本机，但 MINIO_ENDPOINT=%s；服务器上图片代理会 502，请改成可访问的 MinIO 地址。\n' "$MINIO_PROXY_TARGET" "$MINIO_ENDPOINT" >&2
fi

for dir in wego_sso wego_3d_texture wego_fingertip_3d_web wego_quiz_3d; do
  [ -d "$ROOT/$dir" ] || die "找不到 $ROOT/$dir"
done
command -v node >/dev/null 2>&1 || die "未安装 Node.js"
command -v npm >/dev/null 2>&1 || die "未安装 npm"

ensure_frontend_deps() {
  local dir="$1"
  local skip_electron="${2:-0}"
  local full="$ROOT/$dir"
  [ -d "$full/node_modules" ] && return
  log "安装前端依赖：$dir"
  (
    cd "$full"
    if [ "$skip_electron" = 1 ]; then
      ELECTRON_SKIP_BINARY_DOWNLOAD=1 npm ci || npm install
    else
      npm ci || npm install
    fi
  )
}

ensure_frontend_deps wego_sso/frontend
ensure_frontend_deps wego_3d_texture/frontend
ensure_frontend_deps wego_fingertip_3d_web 1
ensure_frontend_deps wego_quiz_3d/frontend

log "构建单点登录前端"
(
  cd "$ROOT/wego_sso/frontend"
  VITE_ALLOWED_REDIRECT_HOSTS="$ALLOWED_HOSTS" \
  VITE_APP_MOCKUP_URL="$MOCKUP_PUBLIC_URL/" \
  VITE_APP_CAD_URL="$CAD_PUBLIC_URL/" \
  VITE_APP_QUIZ_URL="$QUIZ_PUBLIC_URL/" \
  npm run build
)

log "构建包装样机前端"
(
  cd "$ROOT/wego_3d_texture/frontend"
  VITE_SSO_WEB="$SSO_PUBLIC_URL" \
  VITE_SSO_API="$SSO_PUBLIC_URL" \
  VITE_PUBLIC_SHARE_BASE="$MOCKUP_PUBLIC_URL" \
  npm run build
)

log "构建三维建模前端"
(
  cd "$ROOT/wego_fingertip_3d_web"
  VITE_SSO_WEB="$SSO_PUBLIC_URL" \
  VITE_SSO_API="$SSO_PUBLIC_URL" \
  npm run build
)

log "构建答题闯关前端"
(
  cd "$ROOT/wego_quiz_3d/frontend"
  VITE_SSO_WEB="$SSO_PUBLIC_URL" \
  npm run build
)

log "组织 bundle"
rm -rf "$BUNDLE"
rm -f "$TARBALL"
mkdir -p "$BUNDLE"/frontend/{sso,mockup,cad,quiz}
mkdir -p "$BUNDLE"/backend/{sso,mockup,quiz}
mkdir -p "$BUNDLE"/config "$BUNDLE"/nginx "$BUNDLE"/logs
touch "$BUNDLE/.wego-bundle"

cp -R "$SCRIPT_DIR/bundle-template/." "$BUNDLE/"
cp -R "$ROOT/wego_sso/frontend/dist/." "$BUNDLE/frontend/sso/"
cp -R "$ROOT/wego_3d_texture/frontend/dist/." "$BUNDLE/frontend/mockup/"
cp -R "$ROOT/wego_fingertip_3d_web/dist/." "$BUNDLE/frontend/cad/"
cp -R "$ROOT/wego_quiz_3d/frontend/dist/." "$BUNDLE/frontend/quiz/"

copy_backend() {
  local src="$1"
  local dst="$2"
  cp -R "$src/src" "$dst/src"
  cp "$src/package.json" "$dst/package.json"
  if [ -f "$src/package-lock.json" ]; then cp "$src/package-lock.json" "$dst/package-lock.json"; fi
}
copy_backend "$ROOT/wego_sso/backend" "$BUNDLE/backend/sso"
copy_backend "$ROOT/wego_3d_texture/backend" "$BUNDLE/backend/mockup"
copy_backend "$ROOT/wego_quiz_3d/backend" "$BUNDLE/backend/quiz"

log "写入后端 .env"
write_env() {
  local file="$1"
  umask 077
  cat > "$file"
  chmod 600 "$file"
}
write_env "$BUNDLE/backend/sso/.env" <<EOF
PORT=3001
MYSQL_HOST=$MYSQL_HOST
MYSQL_PORT=$MYSQL_PORT
MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_DATABASE=$SSO_DB
JWT_EXPIRES=${JWT_EXPIRES:-12h}
EOF
write_env "$BUNDLE/backend/mockup/.env" <<EOF
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
SSO_API_URL=${SSO_API_URL:-http://127.0.0.1:3001}
SSO_DATABASE=$SSO_DB
EOF
write_env "$BUNDLE/backend/quiz/.env" <<EOF
PORT=3002
MYSQL_HOST=$MYSQL_HOST
MYSQL_PORT=$MYSQL_PORT
MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_DATABASE=$QUIZ_DB
MYSQL_TIMEZONE=${MYSQL_TIMEZONE:-+08:00}
SSO_API_URL=${SSO_API_URL:-http://127.0.0.1:3001}
SSO_DATABASE=$SSO_DB
QUIZ_TOKEN_SECRET=$QUIZ_TOKEN_SECRET
EOF

cp "$ENV_FILE" "$BUNDLE/config/deploy.env"
chmod 600 "$BUNDLE/config/deploy.env"

log "生成单文件 Nginx 配置"
sed \
  -e "s|__ROOT__|$SERVER_ROOT|g" \
  -e "s|__SSO_DOMAIN__|$SSO_DOMAIN|g" \
  -e "s|__MOCKUP_DOMAIN__|$MOCKUP_DOMAIN|g" \
  -e "s|__CAD_DOMAIN__|$CAD_DOMAIN|g" \
  -e "s|__QUIZ_DOMAIN__|$QUIZ_DOMAIN|g" \
  -e "s|__FILES_DOMAIN__|$FILES_DOMAIN|g" \
  -e "s|__MINIO_PROXY_TARGET__|${MINIO_PROXY_TARGET:-http://127.0.0.1:9000}|g" \
  "$BUNDLE/nginx/wego.conf.template" | awk -v proxy="$MINIO_PROXY" '
    /^[[:space:]]*# __FILES_BEGIN__/ { infiles=1; next }
    /^[[:space:]]*# __FILES_END__/   { infiles=0; next }
    infiles && proxy != 1 { next }
    { print }
  ' > "$BUNDLE/nginx/wego.conf"

chmod +x "$BUNDLE"/*.sh 2>/dev/null || true
tar -czf "$TARBALL" --exclude=.wego-bundle -C "$BUNDLE" .

log "打包完成"
printf 'bundle 目录：%s\n压缩包：%s\n' "$BUNDLE" "$TARBALL"
if command -v cygpath >/dev/null 2>&1; then
  printf 'Windows 路径：%s\n' "$(cygpath -w "$TARBALL")"
fi
cat <<EOF

服务器上：
  mkdir -p $SERVER_ROOT
  tar -xzf wego-bundle.tar.gz -C $SERVER_ROOT
  cd $SERVER_ROOT
  ./centos-start.sh          # 装依赖并后台启动三个后端
  ./install-nginx.sh         # 安装 nginx/wego.conf 到 /etc/nginx/conf.d/

如果只想手工放 Nginx 配置，把包里的 nginx/wego.conf 复制到 /etc/nginx/conf.d/ 后执行 nginx -t && systemctl reload nginx。
EOF
