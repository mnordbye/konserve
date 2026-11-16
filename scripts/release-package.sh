#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
PRODUCTS="$ROOT_DIR/.build/release"
ARCHIVE_PATH="$PRODUCTS/Konserve.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/Konserve.app"
COMPONENT_PKG="$PRODUCTS/Konserve-component.pkg"
PACKAGE_PATH="$PRODUCTS/Konserve.pkg"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the Developer ID Application identity}"
: "${DEVELOPER_ID_INSTALLER:?Set DEVELOPER_ID_INSTALLER to the Developer ID Installer identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile name}"

mkdir -p "$PRODUCTS"
xcodebuild \
  -quiet \
  -project "$ROOT_DIR/Konserve.xcodeproj" \
  -scheme Konserve \
  -configuration Release \
  -derivedDataPath "$ROOT_DIR/.build/xcode-release" \
  -archivePath "$ARCHIVE_PATH" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  archive

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
/usr/sbin/pkgbuild --component "$APP_PATH" --install-location /Applications \
  --identifier com.internal.konserve "$COMPONENT_PKG"
/usr/bin/productbuild --package "$COMPONENT_PKG" \
  --sign "$DEVELOPER_ID_INSTALLER" "$PACKAGE_PATH"
pkgutil --check-signature "$PACKAGE_PATH"
xcrun notarytool submit "$PACKAGE_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$PACKAGE_PATH"
xcrun stapler validate "$PACKAGE_PATH"
/usr/sbin/spctl --assess --type install --verbose=2 "$PACKAGE_PATH"

ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_PATH/Contents/MacOS/Konserve")"
if [[ " $ARCHITECTURES " != *" arm64 "* || " $ARCHITECTURES " != *" x86_64 "* ]]; then
  echo "Expected arm64 and x86_64 slices; found: $ARCHITECTURES" >&2
  exit 1
fi
echo "Signed and notarized package: $PACKAGE_PATH"
