#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
"$ROOT_DIR/scripts/dev-build.sh"
APP_PATH="$ROOT_DIR/.build/xcode/Build/Products/Debug/Konserve.app"

RUNNING_PIDS="$(/usr/bin/pgrep -x Konserve || true)"
if [[ -n "$RUNNING_PIDS" ]]; then
  while IFS= read -r PID; do
    if /bin/kill -0 "$PID" 2>/dev/null; then
      /bin/kill -TERM "$PID"
    fi
  done <<< "$RUNNING_PIDS"
  /bin/sleep 1
  while IFS= read -r PID; do
    if /bin/kill -0 "$PID" 2>/dev/null; then
      echo "Konserve process $PID did not stop." >&2
      exit 1
    fi
  done <<< "$RUNNING_PIDS"
fi

/usr/bin/open -n -a "$APP_PATH"
