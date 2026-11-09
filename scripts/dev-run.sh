#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
"$ROOT_DIR/scripts/dev-build.sh"
APP_PATH="$ROOT_DIR/.build/xcode/Build/Products/Debug/SMBConnector.app"

RUNNING_PIDS="$(/usr/bin/pgrep -x SMBConnector || true)"
if [[ -n "$RUNNING_PIDS" ]]; then
  while IFS= read -r PID; do
    if /bin/kill -0 "$PID" 2>/dev/null; then
      /bin/kill -TERM "$PID"
    fi
  done <<< "$RUNNING_PIDS"
  /bin/sleep 1
  while IFS= read -r PID; do
    if /bin/kill -0 "$PID" 2>/dev/null; then
      echo "SMB Connector process $PID did not stop." >&2
      exit 1
    fi
  done <<< "$RUNNING_PIDS"
fi

/usr/bin/open -n "$APP_PATH" --args "$@"
