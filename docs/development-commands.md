# Konserve development commands

This document describes the normal workflow for editing, testing, building, and
running Konserve.

Konserve is a native macOS application, not a web server. There is no browser
dev server or hot reload. After changing Swift code, rebuild and relaunch the
app to see the change.

## Prerequisites

Install Xcode from the Mac App Store or Apple Developer downloads. Open it once
to install its components and accept the license.

Select the Xcode command-line toolchain:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
swift --version
```

Open the repository in VS Code for editing and terminal work:

```bash
code .
```

Open the Xcode project when you need SwiftUI previews, macOS debugging,
signing, archiving, or release configuration:

```bash
open Konserve.xcodeproj
```

## Where to edit the UI

Most visible text and controls are in:

- [`Konserve/Features/ConnectorView.swift`](../Konserve/Features/ConnectorView.swift)
- [`Konserve/App/ConnectorViewModel.swift`](../Konserve/App/ConnectorViewModel.swift)

`ConnectorView.swift` contains labels, buttons, placeholders, and layout.
`ConnectorViewModel.swift` contains connection progress messages and state
handling.

## Build the Debug app

From the repository root:

```bash
./scripts/dev-build.sh
```

The script builds the native macOS app with `xcodebuild` and places it at:

```text
.build/xcode/Build/Products/Debug/Konserve.app
```

The app icon is sourced from `Konserve/Assets.xcassets/AppIcon.appiconset`
and the target uses the explicit `Konserve/Info.plist` for both Debug and
Release builds. The build should produce:

```text
Konserve.app/Contents/Resources/AppIcon.icns
Konserve.app/Contents/Resources/Assets.car
```

To verify the bundle metadata:

```bash
APP_PATH=".build/xcode/Build/Products/Debug/Konserve.app"
test -f "$APP_PATH/Contents/Resources/AppIcon.icns"
plutil -p "$APP_PATH/Contents/Info.plist" | grep -E 'CFBundleIcon(File|Name)'
```

`dev-run.sh` unregisters and force-registers this exact rebuilt bundle with
Launch Services before opening it. The app also assigns the bundled
`AppIcon.icns` to the macOS application at startup. These two steps keep the
Dock icon stable when development builds recreate the app at the same path.

You can also run the equivalent command directly:

```bash
xcodebuild \
  -project Konserve.xcodeproj \
  -scheme Konserve \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath .build/xcode \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO \
  ONLY_ACTIVE_ARCH=NO \
  build
```

## Build and run during development

The usual command is:

```bash
./scripts/dev-run.sh
```

This command:

1. Builds the Debug app.
2. Stops an older Konserve process, if one is running.
3. Opens the newly built app.

After changing Swift source files, run the command again. This is the
replacement for a web application's hot reload workflow.

The application always uses the real macOS SMB and NetFS services:

```bash
./scripts/dev-run.sh
```

The real implementation uses:

- `/usr/bin/smbutil view` for authenticated share discovery.
- The public NetFS mounting API for mounting shares.
- TCP port `445` for the supported SMB connection path.

Real-server testing requires an authorized server and credentials. Do not put
passwords in shell history, command-line arguments, configuration files, or
source code.

For the detailed real-server test procedure, see
[`smb-manual-testing.md`](./smb-manual-testing.md).

## Run automated tests

Run the core package tests:

```bash
./scripts/test.sh
```

This is equivalent to:

```bash
swift test --package-path Packages/KonserveCore
```

The automated tests use mocks and do not connect to a real SMB server.

## Server sidecar configuration

The optional machine-wide configuration file is:

```text
/Users/Shared/Konserve/servers.json
```

Example:

```json
{
  "servers": [
    {
      "id": "media",
      "displayName": "Media Server",
      "endpoints": [
        { "host": "media-wifi.example.local", "port": 445 },
        { "host": "media-wired.example.local", "port": 445 }
      ]
    }
  ]
}
```

The file contains server metadata only. Never put usernames or passwords in
it. If the file does not exist, Konserve displays a manual server-address
field.

The sidecar can be created and edited from the app using the gear button in the
server availability section. It is shared by local users, so the directory and
file must be writable by the intended users.

## Swift package development

Reusable models and services are in:

```text
Packages/KonserveCore/
```

Run package tests directly while working on those services:

```bash
swift test --package-path Packages/KonserveCore
```

The macOS application imports the package as `KonserveCore`.

## Clean build output

If build artifacts appear stale, remove only the generated build directory:

```bash
rm -rf .build
```

Then rebuild:

```bash
./scripts/dev-build.sh
```

Do not remove the Xcode project, source files, or the sidecar configuration
when cleaning build output.

## Release build and packaging

Release packaging requires organization-specific Developer ID certificates and
a configured `notarytool` Keychain profile. Keep those credentials outside the
repository. The complete repeatable release procedure—including certificate
checks, notarization setup, package verification, and clean-Mac testing—is in
[`macos-distribution.md`](./macos-distribution.md).

The release command produces:

```text
.build/release/Konserve.pkg
```

From the repository root, run:

```bash
./scripts/release-package.sh
open .build/release
```

Set the required environment variables:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Example Organization (TEAMID)"
export DEVELOPER_ID_INSTALLER="Developer ID Installer: Example Organization (TEAMID)"
export NOTARY_PROFILE="konserve-notary"
```

Run the release package script:

```bash
./scripts/release-package.sh
```

The script:

1. Archives a Release build.
2. Verifies the application signature.
3. Builds and signs a deployment-ready PKG.
4. Submits the package to Apple notarization.
5. Staples and validates the notarization ticket.
6. Runs `spctl` verification.
7. Checks for both `arm64` and `x86_64` slices.

Release output is written under:

```text
.build/release/
```

The release script should only be run on an authorized signing machine with
valid certificates and notarization access.

## Useful verification commands

Inspect the built app's identity:

```bash
plutil -p .build/xcode/Build/Products/Debug/Konserve.app/Contents/Info.plist
```

Verify a locally built app's signature:

```bash
codesign --verify --deep --strict --verbose=2 \
  .build/xcode/Build/Products/Debug/Konserve.app
```

Check whether the development app is running:

```bash
pgrep -x Konserve
```

## Normal edit-to-test workflow

For a wording or layout change:

1. Edit `Konserve/Features/ConnectorView.swift` in VS Code.
2. Run `./scripts/dev-run.sh` against an authorized SMB server.
3. Check the updated app panel.
4. Run `./scripts/test.sh` after service or model changes.

For a service or parsing change:

1. Edit the relevant file under `Packages/KonserveCore/`.
2. Run `./scripts/test.sh`.
3. Run `./scripts/dev-run.sh` to verify the app still builds and launches.
