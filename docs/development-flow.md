# SMB Connector — Development Flow

## 1. Purpose

SMB Connector is a small native macOS application for internal distribution through JAMF.

The application will:

- Open as a compact, fixed-size panel.
- Display configured SMB servers and their availability.
- Ask the user for an SMB username and password.
- Store credentials locally in the macOS Keychain.
- Discover shares available to the authenticated user.
- Display the available shares inside the application.
- Let the user choose which shares to mount.
- Mount selected shares at standard macOS paths such as `/Volumes/ShareName`.

The application will not use Active Directory integration initially and will not be distributed through the Mac App Store.

## 2. Recommended technical approach

Use a native SwiftUI macOS application with AppKit integration where macOS-specific APIs are needed.

The first implementation should use a dedicated `SMBService` abstraction. The initial adapter may use macOS system tools such as `smbutil` and `mount_smbfs`, but all process execution must be isolated in that service.

Do not automate Finder's Connect to Server window as the primary implementation. Finder is useful as a fallback, but an in-app SMB service gives us better control over loading states, share discovery, error handling, and mounting selected shares.

The implementation should remain replaceable if a better supported SMB mechanism becomes available.

## 3. User experience

The application has one primary panel. It should remain visually stable while the content changes.

### Main panel

The main content area contains:

1. Server selection or server address input.
2. Username input.
3. Password input.
4. `Connect` button.
5. Loading and status feedback.
6. Available-share list after successful authentication.
7. Controls for selecting and mounting shares.

The window should be compact and non-resizable, or have a tightly constrained minimum and maximum size. Avoid introducing a multi-window workflow for the MVP.

### Connection flow

When the user selects `Connect`:

1. Validate the server address and credentials locally.
2. Show a progress indicator.
3. Check that the server is reachable.
4. Authenticate against SMB.
5. Discover the shares visible to that user.
6. Replace the credential content area with the share list.
7. Allow the user to select one or more shares.
8. Mount the selected shares under `/Volumes/<share-name>`.

Use clear progress messages such as:

- `Checking server…`
- `Authenticating…`
- `Finding available shares…`
- `Mounting selected shares…`

If authentication fails, show a useful error and allow the user to try again.

If authentication succeeds but no shares are available, show:

> No shares are available for this account on this server.

The bottom of the panel should contain a compact server-status area. Each configured server may show:

- Green: reachable.
- Gray: not checked or unavailable.
- Yellow: checking.
- Red: connection error.

Availability means that the server can be reached. It does not imply that the current user has permission to access shares.

## 4. Server sidecar configuration

Server configuration must not be embedded in the signed application bundle. This allows the same application build to be deployed to different environments through JAMF.

Recommended machine-wide path:

```text
/Library/Application Support/SMBConnector/servers.json
```

This path is preferable to modifying the application bundle because JAMF can update the configuration without changing the application signature.

Example:

```json
{
  "servers": [
    {
      "id": "media",
      "displayName": "Media Server",
      "host": "media.example.local",
      "port": 445
    },
    {
      "id": "archive",
      "displayName": "Archive Server",
      "host": "archive.example.local",
      "port": 445
    }
  ]
}
```

The configuration must never contain passwords.

If the sidecar file does not exist, the application must remain usable. It should show a server-address field and allow the user to enter a hostname or IP address manually.

The configuration layer should be protocol-based so that a user-level configuration source can be added later without changing the UI.

## 5. Credential storage

Use macOS Keychain Services.

Suggested Keychain identity:

```text
service: SMBConnector/<server-id-or-host>
account: <SMB username>
```

The password must not be stored in:

- `servers.json`
- UserDefaults
- Application logs
- Process arguments
- URLs
- Source code
- JAMF package scripts

The user should be able to choose whether successful credentials are remembered. The default should be secure and clearly explained.

## 6. Repository and project structure

Use an Xcode macOS application project, with reusable logic separated into a Swift Package where practical:

```text
SMBConnector/
├── SMBConnector.xcodeproj
├── SMBConnector/
│   ├── App/
│   ├── Features/
│   │   ├── ServerStatus/
│   │   ├── Credentials/
│   │   ├── ShareBrowser/
│   │   └── Mounts/
│   ├── Services/
│   │   ├── SMBService.swift
│   │   ├── KeychainService.swift
│   │   └── ConfigurationService.swift
│   ├── Models/
│   └── Resources/
├── Packages/
│   └── SMBConnectorCore/
├── Tests/
├── scripts/
│   ├── dev-build.sh
│   ├── dev-run.sh
│   └── verify-release.sh
├── docs/
│   ├── development-flow.md
│   └── vscode-starter-prompt.md
└── README.md
```

## 7. VS Code and Xcode workflow

VS Code is suitable for most source editing, Swift Package development, tests, Git work, scripts, and terminal-based builds.

Xcode is still required for:

- Creating and maintaining the macOS application target.
- SwiftUI previews and visual inspection.
- Reliable macOS application debugging.
- Signing configuration.
- Archive creation.
- Developer ID export.
- Notarization and release verification.

This is not exactly like React Native hot reload. The normal development loop is:

```text
Edit in VS Code
  ↓
Run xcodebuild task
  ↓
Launch the built .app
  ↓
Inspect logs or debug in Xcode
```

SwiftUI previews should be used in Xcode for fast visual iteration. The Swift extension for VS Code provides completion, diagnostics, navigation, tests, and LLDB support, but support for `.xcodeproj` projects is more limited than support for Swift Package Manager projects.

## 8. Initial Mac setup

On the development Mac:

1. Install the current stable Xcode.
2. Open Xcode once and accept the license.
3. Install the required components.
4. Select Xcode as the active developer directory:

   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   ```

5. Verify the toolchain:

   ```bash
   xcodebuild -version
   swift --version
   ```

6. Install the official Swift extension in VS Code.
7. Open the repository in VS Code.
8. Open the Xcode project once and confirm that the application runs on `My Mac`.

## 9. Fast local development commands

The repository should provide scripts so the user does not need to remember long Xcode commands.

Example development build:

```bash
xcodebuild \
  -project SMBConnector.xcodeproj \
  -scheme SMBConnector \
  -configuration Debug \
  -derivedDataPath .build/xcode \
  build
```

The development run script should build the application, stop an older running instance, and open the new `.app`.

The initial scripts should support:

```bash
./scripts/dev-build.sh
./scripts/dev-run.sh
./scripts/test.sh
```

Use a mock SMB service during early UI development so the panel, loading state, share list, empty state, and error states can be tested without a live server.

## 10. Development phases

### Phase 1 — Toolchain and shell

- Create the Xcode project.
- Confirm it runs on the development Mac.
- Configure VS Code.
- Add build, run, and test scripts.
- Commit the clean starting project.

### Phase 2 — Mock-first UI

- Build the compact fixed panel.
- Add server status indicators.
- Add server address fallback field.
- Add username and password fields.
- Add Connect button.
- Add loading states.
- Add share list, empty state, and error states.

### Phase 3 — Configuration and Keychain

- Implement `servers.json` loading.
- Add configuration validation.
- Implement Keychain storage.
- Add tests for both.

### Phase 4 — Real SMB integration

- Implement server reachability checks.
- Implement authenticated share discovery.
- Implement selected-share mounting.
- Verify clean `/Volumes/<share-name>` mounts.
- Test dedicated SMB credentials rather than assuming the logged-in macOS account.

### Phase 5 — Release engineering

- Add Developer ID signing settings.
- Enable Hardened Runtime.
- Build arm64 and x86_64 binaries.
- Create a signed PKG.
- Notarize with `notarytool`.
- Staple and verify the notarization ticket.
- Deploy through JAMF to a test group.

## 11. Testing strategy

Automated tests should cover:

- Configuration parsing and validation.
- Missing sidecar configuration.
- Keychain save, read, update, and delete.
- Share-list parsing.
- Empty share lists.
- Invalid credentials.
- Unreachable servers.
- Share names containing spaces.
- Mount state transitions.
- Sanitized process output.
- Passwords never appearing in logs or process arguments.

Manual testing must cover a real SMB server and both Apple Silicon and Intel Macs if both are present in the organization.

## 12. Release model

Daily development builds should use normal development signing.

Release builds should use:

1. Developer ID Application signing.
2. Hardened Runtime.
3. Signed PKG packaging.
4. Developer ID Installer signing where applicable.
5. Apple notarization.
6. Stapling and verification.
7. JAMF deployment.

Keep signing credentials and notarization credentials out of the repository. Store them in the secure build environment used for release builds.
