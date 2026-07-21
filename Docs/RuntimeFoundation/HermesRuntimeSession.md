# Hermes Runtime Session Manager

## Scope

`HermesRuntimeSessionManager` is the Runtime Foundation lifecycle registry for
Bridge-owned Hermes runtime sessions. It tracks typed session state and
delegates backend work to `HermesBackendAdapter` through the
`HermesBackendAdapting` protocol.

The session layer does not discover executables, launch processes, parse
readiness signals, perform HTTP or WebSocket transport, submit prompts, or own
protocol methods.

## Architecture

```text
HermesRuntimeSessionManager
        |
        v
HermesRuntimeSession
        |
        v
HermesBackendAdapter
```

The manager creates and stores `HermesRuntimeSession` instances. Each session
retains exactly one backend adapter instance supplied by the manager's
`backendFactory`.

## Typed Session State

Each `HermesRuntimeSessionSnapshot` contains:

- `sessionID`: Bridge runtime session UUID.
- `backendIdentity`: discovered executable path and backend version metadata.
- `processIdentity`: process identity returned by `HermesProcessSupervisor`
  through the adapter start result.
- `startTime`: Bridge-observed start time.
- `currentStatus`: runtime lifecycle status.
- `capabilities`: capability summary derived from `HermesBackendStatus`.
- `lastError`: redacted session error.
- `shutdownReason`: typed shutdown reason when applicable.

Snapshots are value types. Callers receive snapshots instead of mutable session
storage.

## Lifecycle Model

The runtime session states are:

- `created`: session exists in the manager but has not started a backend.
- `starting`: a start request is in progress.
- `running`: backend start succeeded and health reports an operational gateway.
- `degraded`: backend is reachable with degraded status, or a health refresh
  failed after a successful start.
- `stopping`: a stop request is in progress.
- `stopped`: the session has been explicitly stopped.
- `failed`: start or shutdown failed.

Start failure sets `failed`, records a redacted `lastError`, stores
`startupFailed` as the shutdown reason, and rethrows the backend error.

Health refresh failure sets `degraded`, records a redacted `lastError`, and
rethrows the backend error.

Stop is idempotent. Stopping an already stopped session returns the existing
stopped snapshot without calling the backend again.

## Manager Operations

`HermesRuntimeSessionManager` exposes:

- `createSession()`: creates a `created` session using the configured backend
  factory.
- `startSession(_:)`: starts the selected session.
- `getSession(_:)`: returns the latest snapshot for a session.
- `listSessions()`: returns sorted snapshots for all tracked sessions.
- `refreshSessionStatus(_:)`: refreshes health through the backend adapter and
  updates `running` or `degraded` state.
- `stopSession(_:)`: stops the selected session.
- `removeSession(_:)`: removes only a `stopped` session.

Unknown session IDs return `sessionNotFound`. Removing a session before it is
stopped returns `sessionNotStopped`.

## Security Boundary

The session manager preserves the Runtime Foundation security boundary:

- no shell execution;
- no arbitrary executable path surface;
- no process management logic;
- no protocol transport logic;
- no token storage;
- no real profile access;
- no raw credential logging.

Executable allowlisting remains owned by `HermesDiscovery`. Process launch,
fixed arguments, isolated runtime directories, and shutdown remain owned by
`HermesProcessSupervisor`. Loopback protocol details and token use remain owned
by `HermesProtocolClient` and `HermesBackendAdapter`.

Session error descriptions are sanitized with the adapter redaction routine so
known credential markers such as `token=`, `X-Hermes-Session-Token=`, and
`HERMES_DASHBOARD_SESSION_TOKEN=` are not exposed in snapshots or descriptions.

## Testing

`HermesRuntimeSessionManagerTests` uses a fake `HermesBackendAdapting`
implementation. The tests cover:

- session creation;
- successful start;
- start failure;
- status refresh;
- multiple sessions;
- idempotent stop;
- stopped-session removal;
- error propagation and redacted storage;
- redacted snapshot descriptions.
