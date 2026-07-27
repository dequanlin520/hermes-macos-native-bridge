# Hermes Release Candidate Assembly

M12-001 adds one reproducible local release-candidate assembly flow:

```sh
HERMES_RC_VERSION=0.1.0-rc.1 Scripts/m12_001_release_candidate_assembly.sh
```

The script reuses the existing release foundation under `Scripts/release/` and the
existing `HermesBridgeServiceLifecycle` installer logic. It does not create a
new installer framework.

## Outputs

Generated RC files are written under `artifacts/m12-001/rc/`:

- `staging/Payload/Hermes Bridge.app`
- `staging/Payload/bin/HermesBridgeService`
- `HermesBridge-<version>-unsigned-rc.tar.gz`
- `staging/ReleaseEvidence/version-manifest.json`
- `staging/ReleaseEvidence/checksums.sha256`
- `staging/ReleaseEvidence/sbom.spdx.json`
- `staging/ReleaseEvidence/release-manifest.json`
- `staging/ReleaseEvidence/upgrade-rollback-metadata.json`

The machine-readable milestone result is written to
`artifacts/m12-001/result.txt`.

No generated RC artifacts are committed.

## Versioning

The harness supplies one RC version through `HERMES_RC_VERSION`; when unset, the
local default is `0.1.0-rc.1`. The assembly validates that the same version is
present in the app bundle, component manifest, upgrade metadata, rollback
metadata, and archive name.

## Validation

The assembly validates bundle shape, executable permissions, Info.plist content,
bundle identifiers, minimum macOS version, XPC protocol 1.7 compatibility,
duplicate app/service absence, production-only payload isolation, deterministic
checksums, SPDX JSON SBOM creation, release manifest creation, and security scan
results.

Installation smoke uses only artifact-owned roots. The lifecycle CLI performs
isolated install/uninstall checks with fake launchctl state, while XPC smoke uses
a temporary artifact-owned LaunchAgent plist and removes it during cleanup.

Signing state is assessed as `valid`, `adhoc`, `unsigned`, or `invalid`.
Unsigned and ad-hoc release candidates are allowed for this local milestone when
reported accurately. The script does not create, import, or request signing
identities, and it does not claim notarization when absent.
