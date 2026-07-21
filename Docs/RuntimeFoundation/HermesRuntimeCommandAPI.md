# Hermes Runtime Command API

## Scope

`HermesRuntimeCommandAPI` is the stable Runtime Foundation control API for
external Bridge consumers such as CLI commands, MenuBar controls, MCP handlers,
and App Intents.

It is a typed command layer over `HermesRuntimeSessionManager`.

```text
CLI / MenuBar / MCP / AppIntent
        |
        v
HermesRuntimeCommandAPI
        |
        v
HermesRuntimeSessionManager
```

The command API does not own lifecycle state, process supervision, backend
discovery, protocol transport, or Hermes process logic. Those responsibilities
remain delegated to the existing session manager and lower Runtime Foundation
components.

## Commands

The API defines `HermesRuntimeCommand` with these stable cases:

- `createSession`
- `startSession(UUID)`
- `stopSession(UUID, reason:)`
- `getSessionStatus(UUID)`
- `subscribeEvents`

Consumers can call command-specific methods or route through
`execute(_ command:)`.

## Results

Command execution returns `HermesRuntimeCommandResult`:

- `sessionStatus(HermesRuntimeCommandSessionStatus)` for create, start, stop,
  and status queries.
- `eventSubscription(HermesRuntimeCommandEventSubscription)` for event
  subscriptions.

`HermesRuntimeCommandSessionStatus` intentionally exposes a command-safe status
view:

- session ID;
- current runtime status;
- backend semantic version;
- start time;
- runtime capabilities;
- redacted last error message;
- typed shutdown reason.

It does not expose credentials, tokens, filesystem secrets, executable paths,
process identifiers, command arguments, runtime directories, or raw process
details.

## Events

`subscribeEvents()` returns an `AsyncStream<HermesRuntimeCommandEvent>`. The
API subscribes to the manager-owned `HermesRuntimeEventBus` and maps internal
runtime events into command-safe event DTOs.

Command events include:

- event sequence number;
- event kind;
- occurrence time;
- command-safe session summary.

They omit raw process identifiers and executable paths even though lower-level
runtime event summaries may contain those fields for internal diagnostics.

## Errors

The API propagates typed errors through `HermesRuntimeCommandAPIError`:

- `sessionManager(HermesRuntimeSessionManagerError)`
- `session(HermesRuntimeSessionErrorCode)`
- `backendAdapter(HermesBackendAdapterError)`
- `operationFailed(String)`

Known manager, session, and backend adapter errors remain typed. Unknown errors
are converted to a redacted operation failure message using the Runtime
Foundation backend redaction routine.

## Integration

`HermesRuntimeSessionManager` conforms to `HermesRuntimeSessionManaging`, which
is the narrow dependency protocol used by the command API. The API delegates:

- create to `createSession()`;
- start to `startSession(_:)`;
- stop to `stopSession(_:reason:)`;
- status query to `getSession(_:)`;
- event subscription to the manager's `eventBus`.

The command API does not duplicate session storage or backend calls.

## Testing

`HermesRuntimeCommandAPITests` covers:

- create session;
- start session;
- stop session;
- status query;
- invalid session;
- typed backend error propagation;
- event subscription;
- command executor routing;
- omission of raw process details from command status and event descriptions.
