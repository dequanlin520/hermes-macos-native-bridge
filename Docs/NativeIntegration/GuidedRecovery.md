# Guided Recovery and Repair Center

M13-002 adds a typed recovery layer for known readiness and diagnostic failures. It sits between Onboarding or Diagnostics and the existing XPC, service lifecycle, permissions, and audit boundaries.

## Supported Issue Classes

- `bridgeServiceUnavailable`
- `xpcConnectionFailed`
- `protocolIncompatible`
- `agentUnavailable`
- `agentIncompatible`
- `accessibilityPermissionMissing`
- `automationPermissionMissing`
- `screenRecordingPermissionMissing`
- `notificationsPermissionMissing`
- `unknownReadinessFailure`

## Typed Remediation Actions

Recovery actions are fixed enum cases:

- `retryConnection`
- `restartBridgeService`
- `refreshAgentDiscovery`
- `rerunPermissionsCheck`
- `openSystemSettings(permission)`
- `openDiagnostics`
- `showUpgradeRequired`
- `rerunReadiness`
- `dismiss`

The model does not contain arbitrary command strings, executable paths, URLs, file paths, process identifiers, or raw process metadata.

## State Machine

Recovery uses deterministic states:

- `idle`
- `evaluating`
- `actionAvailable`
- `executing`
- `verifying`
- `recovered`
- `stillBlocked`
- `failed`

Each action declares the issue it applies to, whether it is automatic or user-directed, whether typed confirmation is required, a safe explanation, and the expected verification category.

## Confirmation Policy

Actions that change service state require typed confirmation. `restartBridgeService` is the only M13-002 service-changing action. If confirmation is missing, recovery remains at `actionAvailable` and does not forward a restart.

## Service Lifecycle Boundary

Bridge Service recovery reuses the existing service lifecycle/control boundary. For service unavailable or XPC connection failures, recovery reconnects first. Only if reconnect fails and the safe service state allows it does recovery forward one restart through the existing lifecycle abstraction, then reconnects and verifies service health/protocol compatibility.

Recovery does not use `sudo`, does not install permanently, does not construct launchctl shell strings, does not kill unknown processes, and does not expose service executable paths or PIDs.

## Protocol Incompatibility

Protocol incompatibility is not repaired automatically. Recovery reports the client protocol as `1.8`, keeps compatibility status sanitized, offers `showUpgradeRequired`, and can route to Diagnostics. It does not downgrade protocol semantics and does not download or execute updates.

## Agent Discovery Boundary

Agent recovery uses the service-owned `discoverAgent` XPC contract. `refreshAgentDiscovery` verifies the returned discovery payload. It does not infer Agent state from sessions, expose executable paths, or install Hermes Agent.

## Permission Verification

Permission recovery only opens fixed macOS System Settings panes for Accessibility, Automation, Screen Recording, and Notifications. Opening Settings never marks a permission as granted. Recovery reruns the Permissions Doctor check and reports `recovered` only when the actual permission state is granted; otherwise it reports `stillBlocked`.

No AppleScript or UI automation is used for permission dialogs.

## Onboarding and Diagnostics

Onboarding blocking states can open Recovery with a typed issue. Diagnostics maps unhealthy checks to the same fixed recovery route. The app has one logical Recovery window identifier managed by `HermesWindowCoordinator`; closing the window does not stop Runtime, and app termination only cleans client-side resources.

Successful recovery asks the original readiness flow to rerun.

## Audit Behavior

Recovery records safe events through the audit abstraction when available. Events include action type, sanitized target category, result, and timestamp. Events do not include tokens, credentials, private paths, executable paths, PIDs, raw command lines, or raw stack traces.

## Security Exclusions

The app does not construct or directly access:

- `HermesRuntimeSessionManager`
- concrete `HermesRuntimeEventBus`
- `HermesRuntimeCommandAPI`
- `HermesProcessSupervisor`
- `HermesBackendAdapter`
- `HermesProtocolClient`
- concrete `HermesDiscovery`

Recovery also excludes arbitrary shell execution, arbitrary URL opening, arbitrary file access, `sudo`, `killall`, and `pkill`.

## Intentionally Unsupported Automatic Repairs

- Automatic Bridge Service install or reinstall
- Automatic protocol downgrade
- Automatic update download or execution
- Automatic Hermes Agent download or install
- Session-derived Agent inference
- Permission dialog automation
- Generic process execution or process termination
