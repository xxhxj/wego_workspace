#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat <<'WARN'
注意：seed 会写入/更新演示账号，SSO 和答题闯关的演示密码可能被重置。
如果数据库已有正式数据，请先备份，不要随意执行。
WARN
printf '继续请按 Enter，取消请 Ctrl+C：'
read -r _

for app in sso mockup quiz; do
  dir="$ROOT/backend/$app"
  [ -f "$dir/.env" ] || { echo "缺少 backend/$app/.env"; exit 1; }
  [ -d "$dir/node_modules" ] || { echo "请先执行 ./install-backends.sh"; exit 1; }
  echo "初始化：$app"
  (cd "$dir" && npm run seed)
done
echo "数据库初始化完成。"
