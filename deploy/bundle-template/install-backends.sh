#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE_INSTALL="${FORCE_INSTALL:-0}"

command -v node >/dev/null 2>&1 || { echo "未安装 Node.js"; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "未安装 npm"; exit 1; }
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 20 ] || { echo "需要 Node.js 20+（建议 22 LTS）"; exit 1; }

for app in sso mockup quiz; do
  dir="$ROOT/backend/$app"
  [ -d "$dir" ] || { echo "缺少 $dir"; exit 1; }
  if [ -d "$dir/node_modules" ] && [ "$FORCE_INSTALL" != 1 ]; then
    echo "依赖已存在，跳过：$app"
    continue
  fi
  echo "安装后端依赖：$app"
  (
    cd "$dir"
    if [ -f package-lock.json ]; then
      NODE_OPTIONS=--max-old-space-size=512 npm ci --omit=dev --no-audit --no-fund || \
      NODE_OPTIONS=--max-old-space-size=512 npm install --omit=dev --no-audit --no-fund
    else
      NODE_OPTIONS=--max-old-space-size=512 npm install --omit=dev --no-audit --no-fund
    fi
  )
done
echo "后端依赖安装完成。"
