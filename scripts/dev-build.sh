#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
HOST_ARCH="$(uname -m)"

xcodebuild \
  -quiet \
  -project "$ROOT_DIR/Konserve.xcodeproj" \
  -scheme Konserve \
  -configuration Debug \
  -destination "platform=macOS,arch=$HOST_ARCH" \
  -derivedDataPath "$DERIVED_DATA" \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO \
  ONLY_ACTIVE_ARCH=NO \
  build
