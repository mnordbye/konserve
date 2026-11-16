# VS Code Starter Prompt — Konserve

Use the following prompt in the VS Code planning or agent workflow.

```text
We are building a small native macOS application called Konserve.

This is an internal application that will be distributed as a signed and notarized macOS package. It will not be submitted to the Mac App Store.

The application helps users connect to local SMB file servers. It must be secure, small, understandable, and maintainable rather than a general-purpose file manager.

## Development environment

Use:

- Swift
- SwiftUI for the primary interface
- AppKit only where macOS-specific functionality is required
- Xcode for the macOS application target, SwiftUI previews, debugging, signing, archiving, and release builds
- VS Code for most source editing, tests, scripts, Git work, and terminal-based development
- Swift Package Manager for reusable core logic and testable services where practical
- XCTest or Swift Testing for automated tests

The repository must build successfully from Xcode and from the command line with `xcodebuild`.

Do not assume this is an iOS or Mac Catalyst application. It is a native macOS application.

## Product behavior

When opened, the application should display one compact, stable panel.

The panel should not navigate through multiple windows for the MVP.

The main content area should contain:

1. A configured-server selector when configured servers exist.
2. A server-address input when no sidecar configuration exists.
3. A username input.
4. A password input.
5. A `Connect` button.
6. Loading and status feedback.
7. A share list after successful authentication.
8. Controls for selecting and mounting shares.

The bottom of the panel should contain a small server availability area. It should show each configured server with a compact status indicator:

- Green: reachable.
- Gray: not checked or unavailable.
- Yellow: checking.
- Red: connection error.

The status indicator only represents server reachability. It must not imply that the current credentials are authorized to access shares.

When the user presses `Connect`:

1. Validate the inputs.
2. Show a spinner and status message.
3. Check server reachability.
4. Authenticate against the SMB server.
5. Discover the shares visible to the authenticated user.
6. Display the shares inside the application.
7. Allow the user to select one or more shares.
8. Mount selected shares at standard macOS locations such as `/Volumes/<share-name>`.

Use clear progress states:

- `Checking server…`
- `Authenticating…`
- `Finding available shares…`
- `Mounting selected shares…`

If authentication fails, show a clear error and allow retrying.

If authentication succeeds but no shares are available, show:

`No shares are available for this account on this server.`

The application should remain on the same panel while moving between credentials, loading, share-list, empty, success, and error states.

## Finder versus in-app SMB behavior

Do not automate Finder's Connect to Server dialog as the primary user flow. The product needs to show loading states, available shares, empty states, and errors inside its own panel.

Create an `SMBService` abstraction. The initial implementation may use macOS system tools such as `smbutil` and `mount_smbfs` if required, but this must be isolated behind the abstraction so that the implementation can be replaced later.

Use `Process` with an explicit executable URL and argument array. Do not invoke a shell unnecessarily. Never build shell command strings from user input.

Never pass passwords as command-line arguments. Never log passwords, credential objects, or unredacted command output.

If a supported native macOS mechanism is more appropriate for a specific operation, prefer it over shelling out.

## Server sidecar configuration

The server configuration must be optional and external to the application bundle.

Use this recommended shared location:

`/Users/Shared/Konserve/servers.json`

This allows an administrator to deploy the configuration without changing the signed application bundle, and allows the app to edit it without administrator prompts.

Example configuration:

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

Do not put credentials in this file.

If the file does not exist, the application must still work. Show a server-address field and allow the user to enter a hostname or IP address manually.

Create a `ConfigurationService` protocol so another configuration source can be added later.

The app provides a gear button for adding, editing, reordering, and deleting
servers. Endpoints are tried from top to bottom; the first reachable endpoint
is used for the current connection.

## Credentials

Use macOS Keychain Services for locally stored SMB credentials.

Credentials may belong to a dedicated SMB user and must not be inferred from the currently logged-in macOS account.

Never store passwords in:

- JSON files
- Property lists
- UserDefaults
- Source code
- Logs
- Process arguments
- URLs
- Package installation scripts

Create a testable `KeychainService` abstraction.

## Architecture

Create these models and service boundaries:

- `SMBServer`
- `SMBShare`
- `SMBCredentials`
- `SMBConnectionState`
- `SMBService`
- `KeychainService`
- `ConfigurationService`
- `ServerReachabilityService`
- `MountService`

Suggested structure:

```text
Konserve/
├── Konserve.xcodeproj
├── Konserve/
│   ├── App/
│   ├── Features/
│   │   ├── ServerStatus/
│   │   ├── Credentials/
│   │   ├── ShareBrowser/
│   │   └── Mounts/
│   ├── Services/
│   ├── Models/
│   └── Resources/
├── Packages/
│   └── KonserveCore/
├── Tests/
├── scripts/
│   ├── dev-build.sh
│   ├── dev-run.sh
│   └── test.sh
├── docs/
└── README.md
```

Keep the UI independent from the real SMB implementation. Add a mock SMB service so the entire UI can be developed and tested without a live server.

## Development workflow

The user is experienced with React, React Native, TypeScript, and VS Code but is new to Swift and Xcode. Explain unfamiliar Swift/Xcode concepts briefly when they become relevant.

Set up live local development early.

The normal workflow should be:

1. Edit Swift files in VS Code.
2. Run a repository build or run task.
3. Launch the built macOS app.
4. Use Xcode when SwiftUI previews or reliable macOS debugging is needed.
5. Run tests from VS Code or the command line.

Create scripts that support:

```bash
./scripts/dev-build.sh
./scripts/dev-run.sh
./scripts/test.sh
```

The development run script should build the Debug application, stop an older running instance, and open the new `.app`.

Use mock data first. Do not block UI development on SMB connectivity.

Create a short README section explaining:

- How to install Xcode.
- How to select Xcode with `xcode-select`.
- How to open the project in VS Code.
- How to open it in Xcode.
- How to run the app.
- How to run tests.
- How to switch between mock and real SMB services.

## Signing and distribution constraints

The release target must support:

- Developer ID Application signing.
- Hardened Runtime.
- arm64 and x86_64 builds.
- Signed and notarized PKG packaging for macOS deployment.
- Apple notarization using `notarytool`.
- Verification using `codesign` and `spctl`.

App Sandbox is not required for this internal, non-App-Store application. Do not add unnecessary entitlements.

Keep signing identities and notarization credentials out of source control.

## Testing requirements

Add tests for:

- Sidecar configuration parsing.
- Missing sidecar configuration.
- Invalid server definitions.
- Keychain save, read, update, and delete.
- Server reachability state changes.
- Share-list parsing.
- Empty share lists.
- Invalid credentials.
- Unreachable servers.
- Share names containing spaces.
- Mount state transitions.
- Redaction of sensitive process output.
- Ensuring passwords never appear in logs or process arguments.

Use mocks for most automated tests. Add a documented manual test procedure for a real SMB server.

## Implementation order

Start with the following sequence:

1. Create the native macOS Xcode project.
2. Confirm it builds and launches on `My Mac`.
3. Add VS Code build, run, and test scripts.
4. Add the core models and service protocols.
5. Implement the compact panel with mock data.
6. Implement server status indicators.
7. Implement the server-address fallback field.
8. Implement the credential form and loading states.
9. Implement the mock share browser, empty state, and error states.
10. Implement Keychain storage.
11. Implement sidecar configuration loading.
12. Implement the real SMB service behind the existing protocol.
13. Test discovery and mounting against a real SMB server.
14. Add release signing, packaging, notarization, and macOS deployment documentation.

Do not add Active Directory integration, cloud services, user accounts, analytics, background agents, or unrelated file-manager functionality.

Before making an architectural change or adding a dependency, explain the reason, alternatives, and impact on signing, deployment, and long-term maintenance.
```
