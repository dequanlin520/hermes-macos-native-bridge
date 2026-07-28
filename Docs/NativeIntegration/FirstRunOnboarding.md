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
- protocol compatibility with HermesBridgeXPC 1.7
- safe health classification

The connection test uses `connect` plus non-destructive `listSessions`. It does not create or start a Runtime session.

## Agent discovery

Agent readiness uses service-reported session summaries through the XPC client. The UI reports only safe states: available, unavailable, incompatible, or unknown. It does not display executable paths and does not download or install Hermes Agent.

## Permission behavior

Permission readiness reuses `HermesPermissionsDoctor` status for Accessibility, Automation, Screen Recording, and Notifications. The UI shows only macOS-reported safe states.

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
