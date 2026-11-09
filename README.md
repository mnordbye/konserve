# SMB Connector

SMB Connector is a compact native macOS app for connecting to SMB servers and mounting selected shares. It is intended for internal JAMF distribution.

## Development

Install Xcode from the Mac App Store or Apple Developer downloads, launch it once to install components and accept the license, then select its toolchain:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

Open the repository folder in VS Code for editing and terminal work. Open [`SMBConnector.xcodeproj`](./SMBConnector.xcodeproj) in Xcode for SwiftUI previews, debugging, signing, and archiving.

```bash
./scripts/dev-build.sh
./scripts/dev-run.sh
./scripts/test.sh
```

By default, the app uses mock SMB, reachability, and mount services so the UI can be exercised without a server. To use the system SMB services during a development launch:

```bash
./scripts/dev-run.sh --use-real-smb
```

Mock UX variants are also available without a server: `./scripts/dev-run.sh --mock-empty`, `--mock-invalid-credentials`, `--mock-unreachable`, or `--mock-mount-failure`.

The app reads optional server definitions from `/Library/Application Support/SMBConnector/servers.json`. Without that file, enter a hostname or IP address manually. Passwords are never stored in the sidecar; the “Remember” option saves them in the macOS login Keychain only after a successful connection. After entering a username, press Return to load a previously remembered credential; unchecking “Remember” and connecting removes its saved Keychain item.

See [the development flow](./docs/development-flow.md) and [manual SMB test procedure](./docs/smb-manual-testing.md). Release packaging and notarization are described in [JAMF distribution](./docs/jamf-distribution.md).
