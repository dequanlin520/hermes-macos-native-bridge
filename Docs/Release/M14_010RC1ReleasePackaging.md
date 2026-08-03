# M14-010 RC1 Release Packaging

M14-010 creates a reproducible RC1 packaging-readiness pipeline for Hermes
macOS Native Bridge. It does not publish a GitHub Release, upload to Apple, or
claim production readiness.

## Authoritative Version

The authoritative release values live in
`Sources/HermesReleaseVersion/HermesReleaseVersion.swift` and are exposed by
`HermesReleaseVersionPrinter` and `HermesReleaseAgentPreflight m14-010-version`.

- Product version: `0.1.0-rc.1`
- Release tag target: `v0.1.0-rc.1`
- XPC protocol: `1.8`
- Tested Hermes Agent: `0.18.2`
- Minimum macOS: `13.0`

Packaging, generated bundle metadata, release manifests, diagnostics, and docs
consume those values. Do not add duplicate release constants to packaging
scripts.

## Release Modes

`unsigned-local-validation` builds a privacy-safe local package for packaging
readiness only. It must not be described as notarized or production-ready.

`signed-notarized-release` requires the identity categories for the selected
artifact type and an explicit notarization opt-in. For RC1
`app-distribution-bundle` ZIP distribution, signed mode requires only
`HERMES_RELEASE_APPLICATION_IDENTITY`. `HERMES_RELEASE_INSTALLER_IDENTITY` is
not applicable because RC1 does not produce a signed flat `.pkg`. Missing
required credentials produce `BLOCKED`, not `FAIL`.

## Commands

Read-only inspection:

```sh
Scripts/m14_010_rc1_release.sh inspect
```

Unsigned local validation:

```sh
HERMES_M14_010_ACCEPTANCE=YES Scripts/m14_010_rc1_release.sh build-unsigned
Scripts/m14_010_rc1_release.sh verify
Scripts/m14_010_rc1_release.sh cleanup
```

Signed release packaging:

```sh
HERMES_M14_010_ACCEPTANCE=YES \
HERMES_RELEASE_APPLICATION_IDENTITY="Developer ID Application: Example" \
Scripts/m14_010_rc1_release.sh build-signed
```

Notarization:

```sh
HERMES_M14_010_NOTARIZE=YES \
HERMES_RELEASE_NOTARY_KEYCHAIN_PROFILE="profile-name" \
Scripts/m14_010_rc1_release.sh notarize
```

Alternatively, supply App Store Connect API key inputs explicitly:
`HERMES_RELEASE_NOTARY_KEY`, `HERMES_RELEASE_NOTARY_KEY_ID`, and
`HERMES_RELEASE_NOTARY_ISSUER`.

## Package Type

The package type is `app-distribution-bundle`, archived as a deterministic ZIP
under `artifacts/m14-010/output/`. RC1 distribution is a ZIP containing a signed
app distribution bundle. A privileged macOS installer package is intentionally
deferred because the validated product contract is user scoped. Developer ID
Installer is not used in RC1 and may only become required for a future
`installer-package` mode that produces a signed flat `.pkg`.

The bundle contains the app, embedded XPC service, LaunchAgent asset,
command-line helpers, installer/uninstaller tooling, checksums, and a
privacy-safe release manifest.

## Contents

The staging allowlist is:

- `Hermes macOS Native Bridge.app`
- `HermesBridgeService.xpc` embedded under the app bundle
- `Library/LaunchAgents/com.hermes.bridge.plist`
- `bin/HermesBridgeControl`
- `bin/HermesBridgeServiceLifecycle`
- `Scripts/install-hermes-bridge-app.zsh`
- `Scripts/uninstall-hermes-bridge-app.zsh`
- entitlement evidence files

Source code, tests, logs, credentials, tokens, local paths, acceptance fixtures,
generated acceptance state, and private `/api/ws` claims are denied.

## Signing And Entitlements

Signing requirements are modeled by artifact type:

- `app-distribution-bundle`: Developer ID Application signs the app, service,
  and nested executable code. Developer ID Installer is not applicable.
- `disk-image`: Developer ID Application signs embedded code. Developer ID
  Installer is not applicable.
- `installer-package`: Developer ID Application signs embedded code and
  Developer ID Installer signs the flat package.

App and service signing categories are typed as `ad-hoc`,
`developer-id-application`, `invalid`, or `unavailable`. Installer signing may
only be `developer-id-installer` for `installer-package`; it is
`not-applicable` for RC1 `app-distribution-bundle`. Identity inspection may
count Developer ID categories, but release evidence must not include identity
names, certificate hashes, usernames, tokens, or Apple account data. The release
manifest must not claim installer signing, installer identity, or a signed ZIP
container for `app-distribution-bundle`.

Production entitlements are minimal:

- App: sandbox and user-selected read/write file access.
- Service: no entitlements.

The release policy rejects `get-task-allow`, debug entitlements,
`disable-library-validation`, unsigned executable memory, unrestricted file
access, and broad automation exceptions. Developer ID signing uses hardened
runtime.

## Notarization

Notarization only runs with `HERMES_M14_010_NOTARIZE=YES` and explicit
credentials. For RC1, notarization accepts the ZIP as the submission container;
the ZIP itself is not signed and is not stapled. The sequence is:

1. Build the release app.
2. Sign nested code from the inside out using Developer ID Application.
3. Sign the outer app using Developer ID Application with hardened runtime.
4. Verify all nested code and the outer app.
5. Create the ZIP using a metadata-preserving macOS archive method.
6. Submit that ZIP to `notarytool` only under explicit notarization opt-in.
7. Staple the notarization ticket to the `.app`.
8. Recreate the final distribution ZIP after stapling.
9. Validate the stapled app and final ZIP manifest.

The construction workflow must not upload automatically.

## Gatekeeper Expectations

Unsigned local validation may fail Gatekeeper assessment and must be reported as
unsigned. Signed-notarized release mode requires Developer ID signatures,
hardened runtime, accepted notarization, successful stapling, and accepted
`spctl` assessment.

## Privacy-Safe Evidence

Generated files live under `artifacts/m14-010/` and are ignored by git. The
release manifest includes product version, tag target, git commit, build
configuration, architectures, minimum macOS, XPC protocol, tested Hermes
version, package type, signing category, hardened runtime status, notarization
status, stapling status, SHA-256 values, RC capability summary, and
reproducibility category.

It excludes absolute paths, identity names, certificate hashes, usernames,
tokens, and Apple account data.

## Security API Compatibility Debt

The current release build can warn about deprecated Security APIs in
`HermesAuditSigning.swift`:

- `kSecUseAuthenticationUIFail`
- `SecTrustedApplicationCreateFromPath`
- `SecAccessCreate`
- `SecKeychainCopyDefault`
- `SecKeychainGetStatus`

These warnings do not by themselves block unsigned packaging readiness. They
should be treated as release compatibility debt unless they break release
builds, signing validation, runtime validation, or notarization. Severity:
medium. Migration target: replace legacy Keychain access-control construction
with supported Security framework access-control APIs before a post-RC public
distribution readiness milestone.

## Rollback

Use the bundled uninstall script or remove the acceptance-owned staged install
targets. Do not modify real Hermes profile data. If a signed/notarized attempt
is blocked or fails, discard `artifacts/m14-010/` and rebuild from source.
