#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
"$ROOT_DIR/scripts/dev-build.sh"
APP_PATH="$ROOT_DIR/.build/xcode/Build/Products/Debug/Konserve.app"

if [[ ! -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]]; then
  echo "Built app is missing Contents/Resources/AppIcon.icns: $APP_PATH" >&2
  exit 1
fi

ICON_NAME="$(/usr/bin/plutil -extract CFBundleIconName raw -o - "$APP_PATH/Contents/Info.plist")"
if [[ "$ICON_NAME" != "AppIcon" ]]; then
  echo "Built app has unexpected CFBundleIconName '$ICON_NAME' (expected AppIcon)." >&2
  exit 1
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$APP_PATH" >/dev/null 2>&1 || true
  "$LSREGISTER" -f "$APP_PATH" >/dev/null
fi

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
