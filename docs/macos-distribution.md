# macOS distribution and release

This document describes how to build a new signed and notarized version of
Konserve for direct macOS deployment.

The Release configuration uses the Hardened Runtime and produces universal
`arm64` and `x86_64` binaries. The package is built by
[`scripts/release-package.sh`](../scripts/release-package.sh).

## One-time release-machine setup

Perform these steps on the Mac that creates releases.

### Required tools

Install Xcode, open it once, accept the license, and select its command-line
tools:

```bash
sudo -A xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

### Required certificates

The login Keychain must contain both certificates and their private keys:

- `Developer ID Application: ...`
- `Developer ID Installer: ...`

Check the installed identities:

```bash
security find-identity -v -p basic
```

The output must include both the Developer ID Application and Developer ID
Installer identities. The installer identity may not appear in the
`codesigning` policy because it signs installer packages rather than the
application binary. To check the login Keychain explicitly:

```bash
security find-identity -v -p basic \
  "$HOME/Library/Keychains/login.keychain-db"
security find-certificate -a \
  -c "Developer ID Installer" \
  "$HOME/Library/Keychains/login.keychain-db"
```

Both certificates must have their private keys on this Mac. In Keychain
Access, expand each certificate under **My Certificates** and confirm that a
private key is nested beneath it. If the certificate appears but
`find-identity` does not list it as valid, install the certificate on the Mac
that created its certificate signing request, or import the matching private
key.

If `productbuild` reports `CSSMERR_CSP_USER_CANCELED`, macOS canceled access
to the installer private key. Open Keychain Access, locate the
`Developer ID Installer` certificate under **My Certificates**, expand it,
and allow `/usr/bin/productbuild` to access its private key. Retry the build
and choose **Always Allow** if macOS asks again.

### Notarization credentials

Create an Apple app-specific password and store it in a Keychain profile. Run
this interactively so the password is not placed in shell history or the
repository:

```bash
xcrun notarytool store-credentials konserve-notary \
  --apple-id "your-apple-id@example.com" \
  --team-id "YOUR_TEAM_ID"
```

Verify the profile:

```bash
xcrun notarytool history --keychain-profile konserve-notary
```

The profile is stored in the user's Keychain. It is not stored in the
repository and must be configured separately on each release Mac.

Never commit certificates, private keys, passwords, or notarization
credentials.

## Preparing a new version

Before creating a release:

1. Update `MARKETING_VERSION` in
   [`Konserve.xcodeproj/project.pbxproj`](../Konserve.xcodeproj/project.pbxproj).
2. Increment `CURRENT_PROJECT_VERSION`.
3. Confirm the bundle identifier remains `com.gunzdev.konserve`.
4. Run the automated tests:

   ```bash
   ./scripts/test.sh
   ```

5. Test the app manually with:

   ```bash
   ./scripts/dev-run.sh
   ```

The version and build number are embedded in the resulting app's
`Info.plist`. Do not modify the signed app after packaging.

## Building the release package

From the repository root, set the exact certificate names and the Keychain
profile name:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAMID)"
export NOTARY_PROFILE="konserve-notary"
```

Confirm that the certificate names match the identities reported by
`security find-identity -v -p basic`:

```bash
printf '%s\n' "$DEVELOPER_ID_APPLICATION"
printf '%s\n' "$DEVELOPER_ID_INSTALLER"
printf '%s\n' "$NOTARY_PROFILE"
```

Run the complete release pipeline:

```bash
./scripts/release-package.sh
```

The script:

1. Archives a Release build.
2. Signs the app with Developer ID Application.
3. Verifies the app signature.
4. Builds a component package.
5. Signs the installer with Developer ID Installer.
6. Submits the package to Apple's notarization service.
7. Staples the notarization ticket.
8. Validates the stapled ticket.
9. Runs Gatekeeper assessment.
10. Confirms both `arm64` and `x86_64` slices are present.

The final deliverable is:

```text
.build/release/Konserve.pkg
```

The package can be opened in Finder from the repository root with:

```bash
open .build/release
```

Intermediate files in the same directory include:

```text
.build/release/Konserve.xcarchive
.build/release/Konserve-component.pkg
```

The script waits for Apple's notarization result. If it fails, inspect the
`notarytool` output before retrying; do not distribute a package unless the
notarization, stapling, and Gatekeeper steps all succeed.

## Verifying the deliverable

Run these checks after a successful build:

```bash
pkgutil --check-signature .build/release/Konserve.pkg
spctl --assess --type install --verbose=2 .build/release/Konserve.pkg
shasum -a 256 .build/release/Konserve.pkg
```

The expected result is a package signed by Apple-issued Developer ID Installer
credentials, trusted by the Apple notary service, and accepted by Gatekeeper.
Record the SHA-256 checksum and the notarization submission ID with the release.

To inspect the archived app's version, icon metadata, and architectures:

```bash
APP_PATH=".build/release/Konserve.xcarchive/Products/Applications/Konserve.app"

plutil -p "$APP_PATH/Contents/Info.plist" | \
  grep -E 'CFBundle(ShortVersionString|Version|Icon(File|Name))'

test -f "$APP_PATH/Contents/Resources/AppIcon.icns"
lipo -archs "$APP_PATH/Contents/MacOS/Konserve"
```

The expected version and build must match the release being published, the
icon resource must exist, and the architecture output must contain both
`arm64` and `x86_64`.

Install the package on a clean test Mac and verify:

- The app launches without a Gatekeeper warning.
- The expected version is shown.
- SMB server reachability works.
- Shares mount with the expected permissions.
- Both Apple Silicon and Intel Macs can run the app when available.

## Optional server configuration

The default machine-wide file is:

```text
/Users/Shared/Konserve/servers.json
```

The location can be changed in the app's server settings; the chosen path is
stored per user in the app's preferences and used on later launches.

It contains server metadata only. Never put usernames, passwords, signing
credentials, or notarization credentials in it.

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

Endpoints are tried in array order. The app preserves compatibility with the
earlier single `host` and `port` format.
