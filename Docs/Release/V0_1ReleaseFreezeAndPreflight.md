# V0.1 Release Freeze and Real-System Preflight

M14-001 freezes the V0.1 scope at the end of M13. The release line is no
longer accepting new Centers or product features. The native product baseline is:

```text
Native UI -> versioned XPC 1.8 -> HermesBridgeService -> service-owned Runtime -> Hermes Agent
```

## Frozen V0.1 Scope

The frozen scope is recorded in the machine-readable manifest at
`Docs/Release/V0_1ReleaseFreezeManifest.json`. It covers M0 through M13,
including onboarding, recovery, update, notifications, timeline, search,
feedback, privacy, policy, administration, compliance, health, operations,
analytics and reporting.

## Deferred Scope

Deferred work includes new product centers, production distribution, production
Developer ID signing without an explicit identity, notarization without an
explicit notary profile, automatic repair actions from preflight, uploads and
network notarization submission.

## Preflight Checks

`Scripts/m14_001_release_freeze_preflight.sh` performs a non-destructive local
preflight. It records macOS version, Apple Silicon architecture, Xcode and Swift
availability, builds Release, assembles an artifact-owned app bundle, validates
the app executable, Bridge Service, Control and Lifecycle executables, Info.plist,
bundle identifiers, minimum macOS version, XPC protocol 1.8, LaunchAgent template
validity, update and rollback assets, production target isolation, entitlements,
current signing state and explicit signing/notary prerequisites.

The script writes runtime evidence under `artifacts/m14-001/`, including
`result.txt` and a runtime freeze manifest with the current source commit.
`artifacts/` remains ignored by Git.

## Real-System Boundaries

The preflight does not install the app, modify `/Applications`, modify
`~/Applications`, modify `/Library`, modify `~/Library/LaunchAgents`, load or
unload LaunchAgents, modify real `~/.hermes`, use `sudo`, use `killall` or
`pkill`, start a permanent service, submit notarization or upload anything.

Hermes Agent readiness is probed through the narrowly scoped
`HermesReleaseAgentPreflight` helper, which uses the existing service-owned
`HermesDiscovery` behavior. Result output is limited to `available`,
`unavailable`, `incompatible` or `unknown`; executable paths, command lines,
environment variables and PIDs are not emitted.

## Signing and Notarization Prerequisites

Signing identity discovery is explicit and scoped to `HERMES_SIGNING_IDENTITY`.
Notary profile discovery is explicit and scoped to `HERMES_NOTARY_PROFILE`.
Credential absence is reported honestly and does not by itself fail local beta
readiness. The freeze manifest does not claim production signing or notarization.

## Local Beta Criteria

Local beta readiness requires the frozen scope, source commit recording, Apple
Silicon on a supported macOS version, Swift and Xcode availability, a successful
Release build, valid production bundle layout, XPC 1.8, safe entitlements,
production target isolation, no exposed secrets or developer paths, and no
permanent system mutation.

## Production Release Criteria

Production release requires local beta readiness plus an explicitly available
Developer ID signing identity, an explicitly available notary profile, nested
component signing with hardened runtime, Team ID consistency, notarization
acceptance, stapling and Gatekeeper verification in the signing pipeline.

## Known Blockers

Production signing and notarization remain blocked when
`HERMES_SIGNING_IDENTITY` or `HERMES_NOTARY_PROFILE` are absent or unavailable.
Hermes Agent readiness may be `unavailable` on systems where the real Hermes
Agent is not installed at the service-owned allowlisted locations.
