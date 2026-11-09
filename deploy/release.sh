#!/usr/bin/env bash
# wego 发版脚本：放在 /opt/others/deployWego/wego/release.sh
# 用法：把 wego-bundle.tar.gz 放到当前目录，然后 ./release.sh
#       也可以指定包：./release.sh /path/to/wego-bundle.tar.gz
set -euo pipefail

ROOT="${APP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
TAR="${1:-$ROOT/wego-bundle.tar.gz}"
BACKUP_DIR="${BACKUP_DIR:-$(dirname "$ROOT")/wego-backups}"
KEEP_BACKUPS="${KEEP_BACKUPS:-5}"
LOG_FILE="${LOG_FILE:-/var/log/wego-release.log}"

FAILED=0
ok() { printf '[OK]   %s\n' "$*"; }
bad() { printf '[FAIL] %s\n' "$*"; FAILED=$((FAILED + 1)); }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "请用 root 运行"
[ -f "$ROOT/centos-start.sh" ] || die "当前目录不是 wego 运行目录：$ROOT"
[ -f "$TAR" ] || die "找不到压缩包：$TAR"
command -v curl >/dev/null 2>&1 || die "缺少 curl"
command -v pm2 >/dev/null 2>&1 || die "缺少 pm2"
command -v tar >/dev/null 2>&1 || die "缺少 tar"

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { printf '\n== %s ==\n' "$*"; }
log "开始发版 $(date '+%F %T')"
printf '目录：%s\n压缩包：%s\n' "$ROOT" "$TAR"

TAR_LIST="$(mktemp)"
trap 'rm -f "$TAR_LIST"' EXIT
tar -tzf "$TAR" > "$TAR_LIST" 2>/dev/null || die "压缩包损坏或不是 tar.gz：$TAR"
for item in ./centos-start.sh ./config/deploy.env ./frontend/sso/index.html ./backend/sso/src/index.js; do
  grep -qx "$item" "$TAR_LIST" || die "压缩包缺少 $item，可能打错包了"
done

AVAIL_KB="$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')"
NEED_KB=$(( $(stat -c %s "$TAR") / 1024 * 3 + 51200 ))
[ "$AVAIL_KB" -ge "$NEED_KB" ] || die "磁盘剩余不足：需要约 $((NEED_KB / 1024))MB，当前 $((AVAIL_KB / 1024))MB"

log "备份当前版本"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
STAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP="$BACKUP_DIR/wego-$STAMP.tar.gz"
tar -czf "$BACKUP" -C "$ROOT" \
  --exclude='./node_modules' \
  --exclude='./backend/*/node_modules' \
  --exclude='./logs' \
  --exclude='./wego-bundle.tar.gz' \
  . || die "备份失败"
ok "备份：$BACKUP（$(( $(stat -c %s "$BACKUP") / 1024 / 1024 ))MB）"
ls -1t "$BACKUP_DIR"/wego-*.tar.gz 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -f

log "解压覆盖"
tar -xzf "$TAR" -C "$ROOT"
chmod +x "$ROOT"/*.sh 2>/dev/null || true
chmod -R u+rwX,go+rX "$ROOT/frontend" 2>/dev/null || true
ok "已解压到 $ROOT"

log "执行 centos-start.sh"
if ! bash "$ROOT/centos-start.sh"; then
  bad "centos-start.sh 执行失败"
  printf '可使用备份回滚：\n  cd %s && tar -xzf %s && bash centos-start.sh\n' "$ROOT" "$BACKUP"
  exit 1
fi

log "读取发版配置"
# shellcheck disable=SC1091
set -a
. "$ROOT/config/deploy.env"
set +a
SCHEME="http"
[ "${ENABLE_TLS:-0}" = 1 ] && SCHEME="https"
SSO_DOMAIN="${SSO_DOMAIN:-sso.$BASE_DOMAIN}"
MOCKUP_DOMAIN="${MOCKUP_DOMAIN:-mockup.$BASE_DOMAIN}"
CAD_DOMAIN="${CAD_DOMAIN:-cad.$BASE_DOMAIN}"
QUIZ_DOMAIN="${QUIZ_DOMAIN:-quiz.$BASE_DOMAIN}"
FILES_DOMAIN="${FILES_DOMAIN:-files.$BASE_DOMAIN}"
printf 'BASE_DOMAIN=%s ENABLE_TLS=%s\n' "$BASE_DOMAIN" "${ENABLE_TLS:-0}"
printf 'MINIO_PUBLIC_BASE=%s\n' "${MINIO_PUBLIC_BASE:-未设置}"

log "进程检查"
for name in wego-sso-api wego-mockup-api wego-quiz-api; do
  pid="$(pm2 pid "$name" 2>/dev/null | head -n1 | tr -d '[:space:]')"
  if [ -n "$pid" ] && [ "$pid" != "0" ]; then
    ok "$name 运行中，PID $pid"
  else
    bad "$name 未运行"
  fi
done

log "接口检查"
check_http() {
  local label="$1" url="$2" expect="$3" code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$url" || true)"
  if [ "$code" = "$expect" ]; then
    ok "$label  $url -> $code"
  else
    bad "$label  $url -> ${code:-无响应}（期望 $expect）"
  fi
}
check_http "SSO 接口"    "http://127.0.0.1:3001/api/health" 200
check_http "样机接口"    "http://127.0.0.1:3000/api/health" 200
check_http "闯关接口"    "http://127.0.0.1:3002/api/health" 200

log "页面检查"
check_http "单点登录" "$SCHEME://$SSO_DOMAIN/"    200
check_http "包装样机" "$SCHEME://$MOCKUP_DOMAIN/" 200
check_http "三维建模" "$SCHEME://$CAD_DOMAIN/"    200
check_http "答题闯关" "$SCHEME://$QUIZ_DOMAIN/"   200
check_http "分享页面" "$SCHEME://$MOCKUP_DOMAIN/share" 200

FILES_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$SCHEME://$FILES_DOMAIN/" || true)"
if [ -n "$FILES_CODE" ] && [ "$FILES_CODE" != "000" ]; then
  ok "图片域名  $SCHEME://$FILES_DOMAIN -> $FILES_CODE（403 为 MinIO 禁止列目录，正常）"
else
  bad "图片域名  $SCHEME://$FILES_DOMAIN 无响应"
fi

log "前端构建地址检查"
if grep -Rqs "$SCHEME://$SSO_DOMAIN" "$ROOT/frontend/sso/assets"; then
  ok "前端包内包含 $SCHEME://$SSO_DOMAIN"
else
  bad "前端包内没找到 $SCHEME://$SSO_DOMAIN，可能是旧环境打的包"
fi

printf '\n===== 发版结果 =====\n'
if [ "$FAILED" -eq 0 ]; then
  printf '全部检查通过。备份：%s\n' "$BACKUP"
else
  printf '有 %s 项失败，请查看上面的 [FAIL]、pm2 logs 和 Nginx error.log。\n' "$FAILED"
  printf '备份位置：%s\n' "$BACKUP"
  printf '回滚命令：cd %s && tar -xzf %s && bash centos-start.sh\n' "$ROOT" "$BACKUP"
  exit 1
fi
