# Native First-Run Onboarding

M13-001 adds production-native onboarding to `HermesBridgeApp`.

## State machine

The onboarding coordinator owns a typed deterministic state machine:

1. `welcome`
2. `checkingService`
3. `serviceUnavailable`
4. `checkingAgent`
5. `agentUnavailable`
6. `checkingPermissions`
7. `permissionsRequired`
8. `testingConnection`
9. `connectionFailed`
10. `ready`

Success advances from service to agent to permissions to connection to ready. Blocking checks stop at the matching remediation state. Retry resumes from the blocking state and re-runs the relevant provider check.

## First-run policy

`HermesBridgeApp` opens the onboarding route on normal launch when the versioned completion record is missing or stale. Completion is written only from the `ready` state after service, agent, permission, and connection readiness pass.

Failed or cancelled onboarding remains incomplete. Completed onboarding does not block normal launches. Settings, Diagnostics, and the menu bar can reopen onboarding manually.

## Readiness providers

`HermesOnboardingCoordinator` depends on `HermesOnboardingReadinessProviding`. Tests inject deterministic providers. Production uses `HermesOnboardingProductionReadinessProvider`.

The app does not construct a concrete Runtime graph. Production readiness goes through the app's client-safe XPC adapter.

## Service and XPC boundary

Service readiness uses:

- `protocolVersion`
- `capabilities`
- protocol compatibility with HermesBridgeXPC 1.8 and backward compatibility with 1.7
- safe health classification

The connection test uses `connect` plus non-destructive `listSessions`. It does not create or start a Runtime session.

## Agent discovery

HermesBridgeXPC protocol 1.8 introduces the `agentDiscovery` capability, the `discoverAgent` operation, and the sanitized `HermesBridgeAgentDiscoveryPayload` DTO. Protocol 1.7 services predate this operation.

Agent readiness is independent from Runtime sessions. Session summaries, active session counts, and persisted Runtime session records are not evidence of Hermes Agent installation or compatibility.

Production discovery flows through the client-safe onboarding adapter to `HermesBridgeRuntimeClientAdapter`, `HermesBridgeXPCClient`, the HermesBridgeXPC 1.8 `discoverAgent` operation, `HermesBridgeService`, and the service-owned `HermesDiscovery` component. The app does not instantiate the concrete discovery implementation and does not inspect the filesystem directly.

A 1.8 client must check the advertised `agentDiscovery` capability before sending `discoverAgent`. If the connected service is protocol 1.7 or omits `agentDiscovery`, onboarding maps agent readiness to the typed safe `unknown` state and does not call `discoverAgent`. It must not infer agent availability from `listSessions` or any historical Runtime session data.

The UI receives only a sanitized discovery DTO. Public states are available, unavailable, incompatible, and unknown. Safe compatibility metadata may include a sanitized semantic version and compatibility state. The DTO does not expose executable paths, filesystem paths, PIDs, command lines, tokens, environment variables, raw discovery errors, or stack traces.

Generated M13-001 acceptance evidence is written at execution time under `artifacts/m13-001/result.txt`. `artifacts/` is ignored by Git, and generated acceptance evidence is not committed.

The machine-readable M13-001 result has a fixed key set and order. Every expected key must appear exactly once, no unexpected key may appear, and `M13_001_RESULT` must appear exactly once as the final key. The result may be `PASS` only when all expected safety values pass and the uniqueness checks succeed.

## Permission behavior

Permission readiness reuses the typed `HermesPermissionsDoctor` snapshot.
First Run blocks only on permission rows classified `required-for-core` with
`blocksFirstRun=true`. RC1 has no core privacy permission grants, so a clean
user can advance from Permissions to Connection and Ready when the Bridge
Service and Hermes Agent discovery checks pass.

For RC1, Input Monitoring, Accessibility, Screen Recording, Full Disk Access,
microphone and camera are not required by the supported product path.
Automation is feature-triggered and must not block First Run before an actual
approved Shortcut or Apple Event operation is invoked. Optional or
feature-triggered permissions remain visible in diagnostics with their exact
classification and status.

System Settings remediation is limited to existing macOS System Settings panes. Onboarding does not automate dialogs, use AppleScript, or claim a permission is granted unless the system report says it is granted.

## Completion persistence

Completion is stored as a versioned `HermesOnboardingCompletionRecord` under a namespaced UserDefaults key:

`com.hermes.bridge.onboarding.completion.v1`

The record contains schema version, completion time, and completed step names. It does not store credentials, tokens, executable paths, PIDs, or private filesystem paths. Future schema versions can require selected steps again by raising the required completion schema.

## Security boundary

Onboarding avoids:

- concrete Runtime graph construction in the app
- generic process execution APIs
- arbitrary shell commands
- arbitrary URLs
- arbitrary file paths
- sudo
- package download execution
- raw error stacks

Messages are redacted before entering the UI snapshot.

## User remediation

Remediation is typed:

- retry
- continue
- open System Settings for a supported permission
- open Diagnostics
- reopen Onboarding
- finish

No remediation action contains user-provided command text, executable paths, or arbitrary URLs.
