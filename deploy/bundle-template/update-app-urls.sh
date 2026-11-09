#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/config/deploy.env"
[ -f "$ENV_FILE" ] || { echo "缺少 config/deploy.env"; exit 1; }
# shellcheck disable=SC1090
set -a
. "$ENV_FILE"
set +a
cd "$ROOT"
node update-app-urls.mjs
