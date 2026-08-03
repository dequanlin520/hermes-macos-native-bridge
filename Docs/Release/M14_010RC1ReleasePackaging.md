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
readiness only. It reports unsigned status honestly and must not be described as
notarized or production-ready.

`signed-notarized-release` requires explicit Developer ID identities and an
explicit notarization opt-in. Missing credentials produce `BLOCKED`, not
`FAIL`.

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
HERMES_RELEASE_INSTALLER_IDENTITY="Developer ID Installer: Example" \
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

The package type is `app-distribution-bundle`, archived as a deterministic zip
under `artifacts/m14-010/output/`. A privileged macOS installer package is not
used for RC1 because the validated product contract is user scoped. The bundle
contains the app, embedded XPC service, LaunchAgent asset, command-line helpers,
installer/uninstaller tooling, checksums, and a privacy-safe release manifest.

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

Signing categories are typed as `unsigned`, `ad-hoc`,
`developer-id-application`, `developer-id-installer`, `invalid`, or
`unavailable`. Identity inspection may count Developer ID categories, but
release evidence must not include identity names, certificate hashes, usernames,
tokens, or Apple account data.

Production entitlements are minimal:

- App: sandbox and user-selected read/write file access.
- Service: no entitlements.

The release policy rejects `get-task-allow`, debug entitlements,
`disable-library-validation`, unsigned executable memory, unrestricted file
access, and broad automation exceptions. Developer ID signing uses hardened
runtime.

## Notarization

Notarization only runs with `HERMES_M14_010_NOTARIZE=YES` and explicit
credentials. The sequence submits the exact acceptance-owned package, waits for
the result, captures sanitized status, staples, validates stapling, and assesses
with `spctl`. The construction workflow must not upload automatically.

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

