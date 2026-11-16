# Konserve

Konserve is a compact native macOS app for connecting to SMB servers and mounting selected shares. It is distributed as a signed and notarized macOS package.

## Development

Install Xcode from the Mac App Store or Apple Developer downloads, launch it once to install components and accept the license, then select its toolchain:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

Open the repository folder in VS Code for editing and terminal work. Open [`Konserve.xcodeproj`](./Konserve.xcodeproj) in Xcode for SwiftUI previews, debugging, signing, and archiving.

```bash
./scripts/dev-build.sh
./scripts/dev-run.sh
./scripts/test.sh
```

The app always uses the system SMB, reachability, and mount services. Run the application with:

```bash
./scripts/dev-run.sh
```

The app reads and edits the shared server definition file at `/Users/Shared/Konserve/servers.json`. Without that file, enter a hostname or IP address manually. Passwords are never stored in the sidecar; the “Remember” option saves them in the macOS login Keychain only after a successful connection. After entering a username, press Return to load a previously remembered credential; unchecking “Remember” and connecting removes its saved Keychain item.

Use the gear button in the server availability section to add, edit, reorder, or delete configured servers. Each server can contain multiple endpoints; they are tried from top to bottom and the first reachable endpoint is used.

Real SMB share discovery has a 30-second timeout. A manually entered server can be added to the shared configuration after a successful connection; credentials are never stored in that configuration.

See [the development flow](./docs/development-flow.md) and [manual SMB test procedure](./docs/smb-manual-testing.md). Release packaging and notarization are described in [macOS distribution](./docs/macos-distribution.md).
