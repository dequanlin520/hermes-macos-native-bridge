# Native Update Center

M13-003 adds a native Update Center for the macOS app. The UI exposes only the
safe update and rollback capabilities already owned by the Bridge Service.

## State Machine

The app models update progress with `HermesUpdateState`:

- `idle`
- `checking`
- `upToDate`
- `updateAvailable`
- `validating`
- `awaitingConfirmation`
- `staging`
- `activating`
- `reconnecting`
- `completed`
- `rollbackAvailable`
- `rollingBack`
- `failed`
- `recoveryRequired`

Discovery never activates an update. Validation must pass before the state can
move to `awaitingConfirmation`. Activation and rollback require explicit typed
confirmation.

## Trusted Source Model

The app does not accept arbitrary user-entered URLs, local package paths, shell
commands, or installer command lines. Release metadata is represented by
`HermesUpdateTrustedSource.repositoryConfigured`, which identifies a trusted
repository-configured source. The UI displays only sanitized source identifiers.

## Validation Gates

Before activation, the coordinator validates:

- release manifest shape;
- product identifier;
- version ordering;
- app and service compatibility;
- XPC major protocol compatibility;
- SHA-256 checksum state;
- signing state;
- provenance state where available;
- production payload classification;
- absence of acceptance or test payload content.

Normal update activation rejects downgrade, same-version replacement,
incompatible major XPC protocol, invalid checksum, invalid signature state,
invalid provenance, non-production payloads, and acceptance/test content.
Rollback is a separate typed operation.

## Confirmation Policy

The confirmation model records operation type, current version, target version,
expected reconnect behavior, and rollback availability. The UI cannot activate
or roll back without a `HermesUpdateConfirmation`.

## Service-Owned Boundary

SwiftUI talks to `HermesUpdateViewModel`, which talks to
`HermesUpdateCoordinator`, which talks to `HermesUpdateProviding`. The
production provider calls only fixed `HermesBridgeXPCClient` update operations:

- `updateStatus`
- `checkForUpdate`
- `validateUpdate`
- `activateUpdate`
- `rollbackUpdate`

The app does not construct installer internals, own the Runtime graph, call
launchctl, run shell installers, terminate processes, or write protected product
files.

## Reconnect Behavior

After service-owned activation or rollback, the coordinator enters
`reconnecting`, calls the provider reconnect verification path, and reports
`completed` only after service compatibility is verified.

## Failed Update Recovery

Deterministic activation failure is surfaced as a sanitized
`HermesUpdateFailure`. The current working version remains the reported current
version. Service-owned components are responsible for partial stage cleanup or
quarantine; the UI reports typed failure state and offers Diagnostics or
Recovery routing.

## Rollback Policy

Rollback is shown only when rollback metadata is available. It requires typed
confirmation and is forwarded once. Completion requires rollback service health,
XPC reconnection, and compatibility verification.

## Audit Events

The Update Center records sanitized audit events:

- check started and completed;
- update offered;
- validation passed or failed;
- activation confirmed, succeeded, or failed;
- rollback confirmed, succeeded, or failed.

Audit metadata excludes credentials, tokens, private paths, package absolute
paths, raw command lines, PIDs, notarization credentials, and raw stack traces.

## Security Exclusions

The native Update Center intentionally excludes:

- arbitrary shell execution;
- arbitrary URLs;
- arbitrary package paths;
- `sudo`;
- `killall` or `pkill`;
- automatic permission escalation;
- unsigned validation bypass;
- acceptance/test payload support;
- direct Runtime ownership by the app.

## Production Signing Limitations

Before production signing and notarization are fully enabled, signing and
provenance states are typed and validated through injected or service-provided
metadata. The UI does not implement a bypass for unsigned production updates.
