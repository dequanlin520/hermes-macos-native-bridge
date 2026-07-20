# Hermes macOS Native Bridge

Native, bidirectional macOS integration for Hermes Agent.

## Real Hermes Compatibility

M9-001 validates a real installed Hermes executable from an isolated
artifact-owned environment without using the normal Hermes profile:

```zsh
Scripts/integration/m9-001-real-hermes-compatibility.zsh
```

See `Docs/HermesIntegration/RealBackendCompatibility.md`,
`Docs/HermesIntegration/SupportedVersions.md`, and
`Docs/HermesIntegration/IsolatedBackendTesting.md`.

## Release Candidate Acceptance

The M8 release-candidate harness composes the app, menu bar, XPC client,
service, XPC service, request orchestrator, and an artifact-owned fake Hermes
backend end to end:

```zsh
Scripts/integration/m8-001-release-candidate-acceptance.zsh
```

Evidence is written under `artifacts/m8-001`.

## CI and release pipeline

M8-002 adds reproducible CI and release packaging workflows under
`.github/workflows/`.

- CI builds and tests the Swift package, builds `HermesBridgeApp` with Xcode,
  validates scripts, scans privacy/action-surface markers, and retains failure
  logs.
- Release-candidate builds run M8-001 once, generate a staged bundle, SPDX
  SBOM, checksums, manifest, gate summary, artifact attestation, and an
  unsigned/ad-hoc conditional artifact when Apple credentials are unavailable.
- Production releases require Developer ID signing, hardened runtime,
  notarization acceptance, staple verification, Gatekeeper assessment, and a
  final `PASS` gate before publication.

See `Docs/Release/CI.md`, `Docs/Release/ReleasePipeline.md`,
`Docs/Release/GitHubSecrets.md`, and `Docs/Release/ReleaseRunbook.md`.

## Project status

Pre-alpha. Technical validation has not started.

## Core scope

- Hermes lifecycle management
- Siri and Shortcuts to Hermes
- Hermes to approved macOS Shortcuts
- macOS event bridge
- Permissions Doctor
- Native menu bar
- Pause, stop, emergency stop, audit and diagnostics

## Explicit non-goals

- GUI computer use
- Browser automation
- General-purpose AppleScript or JXA
- Arbitrary shell execution
- Hermes Desktop replacement
- Knowledge base or workspace
- Manufacturing-specific functionality
- Remote control API

## Project relationship

This is currently an independent community project.

It is not an official Nous Research, Hermes Agent, Apple, GitHub, or OpenAI
project.
