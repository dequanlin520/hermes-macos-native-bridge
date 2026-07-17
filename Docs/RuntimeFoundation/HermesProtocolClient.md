# HermesProtocolClient Runtime Foundation

## Scope

`HermesProtocolClient` implements the narrow backend protocol confirmed by
M2-003. It is not a generic REST client and it is not a generic JSON-RPC method
API.

The client supports only:

- `GET /api/status`;
- authenticated WebSocket JSON-RPC 2.0 at `/api/ws`;
- `gateway.ready`;
- `session.create`;
- `prompt.submit`;
- `session.status`;
- `session.interrupt`;
- `approval.respond`;
- typed gateway and approval events.

## Fixed Transport

The endpoint is always loopback:

```text
http://127.0.0.1:<port>/api/status
ws://127.0.0.1:<port>/api/ws?token=<bridge-owned-token>
```

`HermesBackendEndpoint` validates the port and fixes the host and paths. Callers
cannot supply a host, REST path, WebSocket path, or arbitrary endpoint.

## Status Discovery

`fetchStatus()` performs `GET /api/status` and decodes only fields confirmed by
M2-003, including backend version, authentication mode when present,
`auth_required`, gateway liveness fields, and `desktop_contract` when present.
Unknown status fields are ignored.

Malformed status JSON, non-success HTTP status, and oversized payloads are
reported as typed `HermesProtocolClientError` values.

## Session Token Authentication

`HermesBackendSessionToken.generate()` uses `SecRandomCopyBytes` to create a
Bridge-owned random token. Token descriptions and debug descriptions are always
redacted.

The client uses the token as:

- `X-Hermes-Session-Token` for status requests;
- `token` query parameter for `/api/ws`.

The implementation never reads tokens from `~/.hermes`, browser state, or
Keychain.

## Gateway Ready Handshake

After opening the WebSocket, the client waits for the confirmed initial
`gateway.ready` event before allowing typed requests. Waiting is bounded by a
caller-supplied timeout.

## Typed Method Surface

The public API exposes only typed methods:

- `createSession()`;
- `submitPrompt(sessionID:text:)`;
- `sessionStatus(sessionID:)`;
- `interruptSession(sessionID:)`;
- `respondToApproval(sessionID:decision:all:)`.

JSON-RPC method names are fixed internally. The client validates bounded
session identifiers, bounds prompt text, restricts approval decisions to the
typed enum, and does not expose `send(method:params:)`.

## Event Delivery

Events are delivered through `AsyncStream<HermesGatewayEvent>`.

Confirmed event handling includes:

- `gateway.ready`;
- `approval.request`;
- backend events with bounded metadata;
- unknown event frames represented safely without failing the connection.

## Request Correlation

JSON-RPC requests use generated request IDs. Responses are correlated by ID, so
out-of-order responses are supported. The pending request table is bounded, and
each request has a bounded timeout.

JSON-RPC errors are mapped to typed errors preserving code and message.

## Timeout And Disconnect Behavior

Per-request timeout fails the pending request and removes it from the pending
table. Closing or losing the WebSocket fails all pending requests and finishes
the event stream. Repeated close is idempotent.

## Supervisor Integration

`HermesProcessSupervisor` now creates or accepts a
`HermesBackendSessionToken`, injects it into the child process as the fixed
environment entry:

```text
HERMES_DASHBOARD_SESSION_TOKEN=<token>
```

The supervisor does not accept a caller-controlled environment dictionary. It
returns a typed `HermesBackendLaunchContext` containing the process identity,
fixed endpoint, and token. Public descriptions redact the token, and output
snapshots do not include token values.

## Unsupported Protocol Areas

This implementation deliberately excludes:

- generic REST calls;
- arbitrary HTTP paths;
- arbitrary JSON-RPC methods;
- SSE streams;
- browser or dashboard automation;
- OAuth WebSocket ticket minting;
- reconnection or resume guarantees beyond clean close and typed failure;
- structured run state beyond confirmed textual `session.status.output`.

## Relationship To M2-003

M2-003 confirmed the transport, authentication shape, `gateway.ready`, fixed
session/prompt/status/interrupt/approval JSON-RPC methods, event notification
shape, and JSON-RPC error envelope. `HermesProtocolClient` implements only that
confirmed contract as production Runtime Foundation code.
