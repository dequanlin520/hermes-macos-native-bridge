# M12-003 Signing and Notarization Pipeline

M12-003 promotes an M12-002 release candidate into either a production signed
and notarized artifact or a readiness-only report. It never fabricates signing,
notarization, stapling, or Gatekeeper success.

## Inputs

The pipeline uses explicit non-secret inputs:

- `HERMES_RELEASE_VERSION`
- `HERMES_UNSIGNED_RC`
- `HERMES_UNSIGNED_RC_SHA256`
- `HERMES_SIGNING_IDENTITY`
- `HERMES_TEAM_ID`
- `HERMES_NOTARY_PROFILE`

`HERMES_NOTARY_PROFILE` must name a pre-existing `notarytool` Keychain profile.
Raw Apple ID passwords are not accepted as command-line arguments and are not
needed by the script.

## Credential Discovery

Credential checks are narrowly scoped:

- `security find-certificate -c "$HERMES_SIGNING_IDENTITY"` checks only the
  explicitly named certificate.
- `xcrun notarytool history --keychain-profile "$HERMES_NOTARY_PROFILE"`
  checks only the explicitly named profile.
- `HERMES_TEAM_ID` must be provided explicitly.

The script does not enumerate all signing identities, import certificates,
create accounts, install applications, load LaunchAgents, use `sudo`, or touch
the real Hermes home.

## Readiness-Only Mode

When credentials are absent or unavailable, the script performs all structural
checks that do not require credentials:

- unsigned RC checksum verification
- M12-002 provenance and `READY_FOR_SIGNING_PROMOTION=yes` verification
- nested executable discovery
- signing order generation
- entitlement inventory generation
- hardened runtime configuration policy
- production component isolation scan
- sensitive data scan
- post-signing provenance placeholder linking the unsigned RC

The result is `RELEASE_STATE=readiness-only` only when these checks pass and all
signing/notarization fields truthfully report `not-run` or `no`.

## Production Mode

Production mode runs only when all explicit credentials are available. Signing
is inside-out:

1. nested bundles and executable components
2. `HermesBridgeService`
3. `HermesBridgeControl`
4. `HermesBridgeServiceLifecycle`
5. `Hermes Bridge.app`

The script reuses existing entitlement files under `Packaging/Entitlements`.
It applies `codesign --options runtime --timestamp` and rejects
`get-task-allow`, library validation disablement, unrestricted temporary
exceptions, acceptance/test entitlements, and unexpected acceptance content.

After signing, it verifies:

- `codesign --verify --deep --strict`
- metadata for each executable component
- Team ID consistency
- designated requirements where available
- absence of unsigned nested executables
- post-signing checksums

The unsigned RC remains unchanged. All M12-003 outputs are written under
`artifacts/m12-003/`.

## Notarization and Gatekeeper

The notarization artifact is a supported zip created with `ditto`. Production
mode submits with:

```sh
xcrun notarytool submit --keychain-profile "$HERMES_NOTARY_PROFILE" --team-id "$HERMES_TEAM_ID" --wait
```

The script records the submission ID, retrieves the log, staples the ticket,
validates stapling, and runs `spctl` assessment. It sets
`RELEASE_STATE=production-notarized` only after notarization acceptance,
stapling validation, Gatekeeper assessment, and signature verification all pass.

## Machine-Readable Result

The canonical result is:

```text
artifacts/m12-003/result.txt
```

`M12_003_RESULT=PASS` means either:

- `RELEASE_STATE=production-notarized` with real production evidence, or
- `RELEASE_STATE=readiness-only` with credentials unavailable and all readiness
  checks passing.

`production-signed` is a failure state for this milestone unless notarization,
stapling, and Gatekeeper assessment also pass.
