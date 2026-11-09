# JAMF distribution and release

The Release configuration uses Hardened Runtime and the standard macOS architecture set (arm64 and x86_64). No App Sandbox entitlement is enabled. Keep signing identities and notarization credentials in the secure release environment, never in the repository.

Create a `notarytool` Keychain profile on the signing machine, then provide the identity names and profile when packaging:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Example Organization (TEAMID)"
export DEVELOPER_ID_INSTALLER="Developer ID Installer: Example Organization (TEAMID)"
export NOTARY_PROFILE="smb-connector-notary"
./scripts/release-package.sh
```

The script archives the app, verifies code signing, builds and signs a component PKG, submits it for notarization, staples the ticket, and checks the package with `spctl`. It checks that both Intel and Apple Silicon slices are present.

Before JAMF deployment:

1. Confirm both Developer ID certificates and the notary profile are valid on the release machine.
2. Run the package script and retain the notarization submission ID and build logs in the approved release system.
3. Verify the PKG on a clean test Mac with `pkgutil --check-signature SMBConnector.pkg` and `spctl --assess --type install --verbose=2 SMBConnector.pkg`.
4. Deploy the PKG and optional `/Library/Application Support/SMBConnector/servers.json` sidecar through a JAMF test group.
5. Confirm the installed app launches, reaches the intended SMB servers, and mounts shares with the expected permissions before broad deployment.

The sidecar file contains server metadata only. Never place passwords, signing credentials, or notarization credentials in the PKG scripts or configuration file.
