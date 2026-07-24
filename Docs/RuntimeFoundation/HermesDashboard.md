# Hermes Dashboard

## Architecture

M10-002 adds `HermesDashboard`, a SwiftUI dashboard window for Hermes Runtime.

```text
Dashboard UI
        |
HermesDashboardViewModel
        |
HermesDashboardController
        |
HermesRuntimeCommandAPI
        |
Hermes Runtime Kernel
```

`HermesDashboardController` depends on the
`HermesDashboardRuntimeCommandExecuting` protocol, implemented by
`HermesRuntimeCommandAPI`. The dashboard does not depend on
`HermesProcessSupervisor`, `HermesBackendAdapter`, or `HermesProtocolClient`.

## Data Flow

The window owns a `HermesDashboardViewModel`. The view model runs on the main
actor and publishes `HermesDashboardState` for SwiftUI.

Dashboard actions are forwarded to the runtime command API:

- Start Hermes -> `createSession` when needed, then `startSession`.
- Stop Hermes -> `stopSession` with the requested shutdown reason.
- Restart Hermes -> `stopSession` for the active session when present, then
  `createSession` and `startSession` for a new runtime session.
- Refresh -> `getSessionStatus` for the active session, or `createSession` when
  no runtime session has been created yet.

Runtime events are received through `subscribeEvents`. The controller maps each
`HermesRuntimeCommandEvent` into dashboard view state and keeps only recent,
command-safe event summaries.

## Security Boundary

Dashboard state is intentionally limited to command-safe runtime information:

- runtime status;
- session status, start time, and shutdown reason;
- backend semantic version;
- gateway health flags, gateway state, active-agent count, and desktop contract;
- recent event kind, status, timestamp, and sanitized error text.

The dashboard does not expose:

- tokens or credentials;
- filesystem paths;
- executable paths;
- process IDs or process group IDs;
- launch arguments, runtime directories, or supervisor internals.

Errors are redacted before entering dashboard state. Event state is adapted from
`HermesRuntimeCommandEvent`, whose session summary omits process identifiers and
executable paths from the command API boundary.
