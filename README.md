# Hermes macOS Native Bridge

Native macOS control plane and system bridge for Hermes Agent.

## Project Status

Release-candidate engineering validation in progress.

This repository is validating a narrow, service-owned product path. It does not
claim production readiness or external adoption.

## Verified Architecture

```text
Native App / Menu Bar / App Intents
  -> versioned XPC 1.8
  -> HermesBridgeService
  -> service-owned isolated Hermes supervisor
  -> dynamic loopback endpoint ownership
  -> /api/status
  -> typed capability/status snapshot
  -> UI presentation
```

The UI does not own Agent processes, endpoints, or protocol clients.

## Current Supported Capability Boundary

| Capability | RC status |
| --- | --- |
| Native app launch | supported |
| Menu-bar status | supported |
| Service connection state | supported |
| XPC protocol compatibility | supported |
| Hermes executable/version discovery | supported |
| Isolated Agent start | supported |
| Agent readiness/status | supported |
| Dynamic endpoint ownership | supported |
| Controlled service restart/reconnect | supported |
| App exit without accidental runtime destruction | supported |
| Exact Agent shutdown | supported |
| Diagnostics, permissions, audit/security | supported |
| Emergency stop | supported |
| Installation/uninstallation | supported |

## Unsupported Capability Boundary

| Capability | RC status | Reason |
| --- | --- | --- |
| Request submission | unsupported | `transport.route-unsupported` |
| Request status | unsupported | `transport.route-unsupported` |
| Request cancellation | unsupported | `transport.route-unsupported` |
| Approval response | unsupported | `transport.route-unsupported` |
| Arbitrary prompts | unsupported | `rc.scope-unsupported` |
| Arbitrary shell | unsupported | `security.boundary-unsupported` |
| GUI Computer Use | unsupported | `rc.scope-unsupported` |
| Browser automation | unsupported | `rc.scope-unsupported` |
| Arbitrary AppleScript/JXA | unsupported | `rc.scope-unsupported` |
| Broad process control | unsupported | `security.boundary-unsupported` |
| Private `/api/ws` assumptions | unsupported | `private-route.not-assumed` |

Unsupported controls must be disabled with factual typed reasons.

## Safety Boundaries

- No arbitrary shell execution API.
- No GUI computer use or browser automation.
- No general AppleScript or JXA execution.
- No arbitrary executable paths.
- No UI-owned Agent processes or endpoint discovery.
- No raw endpoint ports, PIDs, paths, tokens, or internal URLs in UI status.
- No private Hermes route guessing.

## Tested Baseline

- Apple Silicon baseline
- macOS 13+ package baseline
- Hermes Agent 0.18.2
- XPC protocol 1.8
- Status-only Hermes integration through `/api/status`

See [RC1Scope.md](Docs/Release/RC1Scope.md).

## Operator Quick Start

```zsh
swift build
swift test
Scripts/m14_009_product_e2e_acceptance.sh inspect
```

Opt-in product acceptance is explicit:

```zsh
HERMES_M14_009_ACCEPTANCE=YES Scripts/m14_009_product_e2e_acceptance.sh run
Scripts/m14_009_product_e2e_acceptance.sh cleanup
```

Evidence is written under `artifacts/m14-009` and is ignored by git.

## Developer Notes

The product capability snapshot is `HermesProductCapabilitySnapshot`. It is
delivered through the existing XPC 1.8 capabilities response so UI and App
Intents consume typed capability evidence rather than inferring support from
operation failures.

## Project Relationship

This is currently an independent community project.

It is not an official Nous Research, Hermes Agent, Apple, GitHub, or OpenAI
project.
