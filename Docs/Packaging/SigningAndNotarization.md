# Signing And Notarization

## Scope

M3-002 adds a deterministic release-packaging pipeline for
`HermesBridgeService`. It builds and signs a staged release archive for local
verification by default. It does not install the service, bootstrap a
LaunchAgent, submit anything to Apple automatically, or claim public
distribution readiness.

## Release Layout

`Scripts/packaging/build-release.zsh` writes only under a caller-supplied
directory inside `artifacts/`:

```text
HermesBridgeRelease/
├── Payload/
│   ├── HermesBridgeService
│   └── com.hermes.bridge.plist
├── Metadata/
│   ├── release-manifest.json
│   ├── checksums.sha256
│   └── build-info.json
└── HermesBridgeRelease.zip
```

The archive contains the `HermesBridgeRelease/` directory with only the
allowlisted payload and metadata files. It does not include `.build`, source
files, test fixtures, runtime state, logs, prompt data, backend tokens, user
configuration, or private absolute paths.

The staged LaunchAgent plist keeps the fixed production label and Mach service:

```text
Label: com.hermes.bridge
MachServices: com.hermes.bridge.xpc
```

The release plist uses a deterministic future install path for
`ProgramArguments`. A future installer or lifecycle operation remains
responsible for placing the binary and final LaunchAgent in the real per-user
location.

## Entitlement Policy

The Bridge service entitlement policy is intentionally empty:

```text
Packaging/Entitlements/HermesBridgeService.entitlements
```

The current service is a non-App-Sandbox per-user LaunchAgent executable. In
that model, the user-domain Mach service, local process supervision, and local
network client behavior do not require explicit App Sandbox entitlements.

No release entitlement is enabled for:

- arbitrary Apple Events;
- broad file access;
- application groups;
- network server access;
- debugging;
- disabling library validation.

`verify-release.zsh` extracts the signed entitlements from the binary and
compares them to this policy.

`Hermes Bridge.app` has a separate M5-004 sandbox policy:

```text
Packaging/Entitlements/HermesBridgeApp.entitlements
```

It contains only:

- `com.apple.security.app-sandbox = true`;
- `com.apple.security.files.user-selected.read-write = true`.

M5-004 automated validation ad-hoc signs the app bundle with that entitlement
file and verifies the embedded entitlements with `codesign`. The sandboxed app
bundle remains a menu bar app with `LSUIElement=true`, retains App Intents
metadata, and uses typed XPC bookmark handoff. The validation does not claim
Developer ID signing, notarization, or release distribution readiness.

## Signing Modes

Ad-hoc signing is the default validation mode for local builds:

```sh
Scripts/packaging/build-release.zsh \
  --output-dir artifacts/m3-002/release-a \
  --signing-mode adhoc
```

Ad-hoc mode uses `codesign --sign -` with the hardened runtime option and the
minimal entitlement file. It supports local signature verification only. It is
not a distribution trust path and is not notarization-eligible.

Developer ID signing is explicit:

```sh
Scripts/packaging/build-release.zsh \
  --output-dir artifacts/m3-002/developer-id \
  --signing-mode developer-id \
  --identity "Developer ID Application: Example Name (TEAMID)"
```

The script accepts exactly one identity value, requires it to match
`Developer ID Application:`, and verifies it appears in
`security find-identity -v -p codesigning`. It does not accept arbitrary
codesign flags and does not print private certificate material.

## Verification

`Scripts/packaging/verify-release.zsh` checks:

- the exact release directory layout;
- the allowlisted file set;
- executable Mach-O type;
- plist syntax;
- fixed `Label` and `MachServices` values;
- strict code signature verification;
- hardened runtime presence;
- signed entitlement policy match;
- manifest fields and checksums;
- absence of token, prompt, private path, state, runtime, and log markers;
- archive contents;
- archive extraction verification.

The integration script deliberately tampers with a copied payload and confirms
verification fails.

## Notarization Preflight

`Scripts/packaging/notarization-preflight.zsh` reports local readiness without
uploading:

```sh
Scripts/packaging/notarization-preflight.zsh \
  --release-dir artifacts/m3-002/release-a/HermesBridgeRelease \
  --archive artifacts/m3-002/release-a/HermesBridgeRelease.zip
```

It checks Xcode command-line tools, `xcrun notarytool`, signing mode, Developer
ID signature presence, hardened runtime presence, archive validity, and whether
credentials are configured. It prints machine-readable fields:

```text
NOTARYTOOL_AVAILABLE=yes|no
DEVELOPER_ID_SIGNED=yes|no
HARDENED_RUNTIME_ENABLED=yes|no
ARCHIVE_READY=yes|no
NOTARIZATION_READY=yes|no
NOTARIZATION_BLOCKERS=<comma-separated-safe-values>
```

On this Mac, ad-hoc artifacts are expected to report
`NOTARIZATION_READY=no` with `not-developer-id-signed` as a blocker. Missing
notarization credentials are also reported without printing secrets.

## Credential Handling

Do not commit certificates, provisioning profiles, Apple accounts, app-specific
passwords, API keys, or keychain profile secrets.

The submission script supports either:

- a keychain profile name via `--keychain-profile`; or
- App Store Connect key metadata through `--asc-key-id`, `--asc-issuer-id`,
  and `--asc-key`, or the matching environment variables.

Secret values are not echoed. The script references a key path but does not
copy key material into the repository or release archive.

## Explicit Submission

`Scripts/packaging/submit-notarization.zsh` is never run automatically. It
requires `--archive`, one credential mode, and an explicit `--submit` flag:

```sh
Scripts/packaging/submit-notarization.zsh \
  --archive artifacts/m3-002/developer-id/HermesBridgeRelease.zip \
  --submit \
  --keychain-profile "<profile-name>"
```

It refuses ad-hoc signed artifacts before calling Apple. When allowed, it calls
only:

```text
xcrun notarytool submit ... --wait
```

Stapling is optional and skipped for ZIP archives because stapling does not
apply to this artifact type.

## Public Release Blockers

Public distribution remains blocked until:

- a real Developer ID Application identity is available on the release Mac;
- Developer ID signing succeeds with hardened runtime;
- notarization credentials are configured securely;
- Apple notarization succeeds for the exact release artifact;
- the sandboxed app bundle is validated under the release signing identity;
- manual `NSOpenPanel`/TCC user-selection evidence is recorded for the signed
  app;
- a future installer or lifecycle issue owns final per-user placement,
  LaunchAgent installation, upgrade, removal, and user-facing controls.
