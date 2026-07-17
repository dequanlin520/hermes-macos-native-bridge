# HermesBridgeXPC Runtime Foundation

## Component Responsibility

`HermesBridgeXPC` defines the versioned local XPC ingress boundary for Bridge
clients running in the same user session. It is the intended IPC surface for
future App Intents, the future menu bar app, and future Shortcuts bindings.

The module exposes only typed request operations over one `NSXPC` method:

```text
handleRequest(Data) -> Data
```

The `Data` values are bounded JSON-encoded envelopes. The XPC method is narrow
so the Objective-C boundary does not expose generic selectors, arbitrary method
dispatch, executable controls, endpoint controls, environment controls, or
JSON-RPC method names.

## Mach-Service Topology

The intended production owner is a per-user LaunchAgent publishing one fixed
Mach service in the current GUI launchd domain. Trusted composition code passes
the fixed service name to `HermesBridgeXPCClient` as a
`HermesBridgeMachServiceName`.

This issue does not install a LaunchAgent, create a bundle, or ship production
packaging. `SPK-02` proved that a temporary per-user LaunchAgent can publish a
Mach service and be removed cleanly on the research Mac. Production signing,
notarization, hardened runtime, entitlement, installer, restart policy, and log
routing remain packaging work.

## Protocol Versioning

The current protocol version is:

```text
major: 1
minor: 0
```

The service rejects unsupported major versions before operation dispatch.
Clients with the same major version and a higher minor version are accepted for
forward-compatible minor additions. A client performs a handshake with the
`protocolVersion` operation, then queries `capabilities`.

## Capabilities

The confirmed capability set is:

- `submitRequest`
- `requestStatus`
- `cancelRequest`
- `respondToApproval`
- `protocolVersion`

The service does not advertise or accept generic execution, generic JSON-RPC,
generic HTTP, filesystem path, process, browser, GUI, AppleScript, JXA, or shell
capabilities.

## Request Envelope

`HermesBridgeRequestEnvelope` contains:

- protocol version;
- bounded correlation ID;
- operation discriminator;
- one typed payload matching the operation.

Supported operations are:

- `protocolVersion`: no payload.
- `capabilities`: no payload.
- `submit`: binding ID and transient prompt.
- `status`: request ID.
- `cancel`: request ID.
- `approvalResponse`: request ID and confirmed approval decision.

The envelope contains no arbitrary dictionaries and no generic JSON blob field.
Payloads are Swift `Codable` types with fixed fields. Unknown operation strings
are rejected as `unsupportedOperation`.

## Response Envelope

`HermesBridgeResponseEnvelope` contains:

- protocol version;
- preserved correlation ID when the request envelope can be identified;
- typed success payload or typed redacted error.

Success payloads are limited to:

- protocol version;
- capabilities;
- submitted request ID;
- redacted request status summary;
- redacted cancellation status summary;
- redacted approval-response status summary.

Status summaries include request ID, binding ID, lifecycle state, cancellation
flag, result availability, and redacted failure code/retryability. They do not
include prompts, backend session tokens, raw stdout/stderr, backend process
PID/PGID, or raw result bodies.

## Size Limits

The shared protocol limits are:

```text
maximum envelope: 128 KiB
maximum transient prompt: 64 KiB
maximum correlation ID: 128 characters
maximum Mach service name: 255 characters
```

The service rejects oversized envelopes before decoding. It rejects oversized
or empty prompts before invoking the request handler. Binding IDs and request
IDs are validated by `HermesRuntimeFoundation` domain types.

## Error Redaction

Caller-facing XPC errors are typed as `HermesBridgeXPCError`:

- `unsupportedProtocolVersion`
- `malformedPayload`
- `oversizedPayload`
- `unsupportedOperation`
- `invalidBinding`
- `requestNotFound`
- `invalidState`
- `serviceUnavailable`
- `internalFailure`

The service maps `HermesRequestOrchestratorError` into this set and emits fixed
safe messages. It does not propagate raw `NSError`, process, WebSocket,
filesystem, backend token, prompt, stdout, stderr, or diagnostic descriptions
through XPC.

## Service Dispatch

`HermesBridgeXPCService` implements the Objective-C `HermesBridgeXPCProtocol`.
It injects a narrow `HermesBridgeRequestHandling` dependency, which is
implemented by `HermesRequestOrchestrator`.

Dispatch is actor-isolated in `HermesBridgeXPCRequestDispatcher` and bounded by
a configurable maximum concurrent request count. Each request is decoded,
validated, dispatched to the typed handler, and encoded as exactly one response.
Cancellation and invalidation are handled by cancelling outstanding service
tasks and by suppressing cancelled replies.

## Client Lifecycle

`HermesBridgeXPCClient` connects to a typed `HermesBridgeMachServiceName`,
performs protocol-version negotiation, queries capabilities, and exposes only:

- `connect()`
- `protocolVersion()`
- `capabilities()`
- `submit(bindingID:prompt:)`
- `status(requestID:)`
- `cancel(requestID:)`
- `respondToApproval(requestID:decision:)`
- `close()`

The public client API does not expose raw `Data`, arbitrary operation names, or
generic request methods. Raw transport is confined to internal adapters.
Timeouts are enforced by the client. Interruption and invalidation are surfaced
as typed client errors. Repeated `close()` calls are idempotent.

## App Intent Handoff Model

`HermesBridgeAppIntentAdapter` is a small future-facing adapter for App Intent
code. It submits a binding ID plus bounded transient prompt and returns a
`HermesRequestID`; status and cancel remain separate calls.

This matches `SPK-06`, where the selected handoff model is that App Intent code
validates and enqueues to Bridge XPC, then returns quickly while Bridge-owned
runtime infrastructure continues long-running work. This issue does not add
actual `AppIntent` types.

## Security Boundary

The XPC boundary never exposes:

- backend session tokens;
- executable path controls;
- arbitrary environment;
- arbitrary JSON-RPC methods;
- generic HTTP endpoints;
- process PID or PGID;
- raw stdout or stderr;
- Keychain content;
- prompt echoes in errors;
- arbitrary filesystem paths;
- generic AppleScript, JXA, shell, GUI, browser, or remote-control APIs.

All backend execution remains behind `HermesRequestOrchestrator`,
`HermesProcessSupervisor`, and `HermesProtocolClient`, which preserve fixed
process and protocol boundaries.

## Test And Integration Status

The implemented test layer uses deterministic in-process transports, an
anonymous test-owned `NSXPCListener`, and a fake `HermesBridgeRequestHandling`
implementation. It covers protocol negotiation, capability response, all typed
operations, correlation preservation, malformed and oversized inputs, invalid
IDs, redaction, concurrent request limits, timeout, interruption, idempotent
close, response decoding failure, no generic client operation exposure, App
Intent handoff shape, NSXPC interface round trip, and residual test-process
checks.

No permanent LaunchAgent is installed, and tests do not call the real installed
Hermes. A real Mach-service integration test still requires signed service
packaging or a temporary LaunchAgent fixture owned by a later packaging issue.

## Remaining Work

Remaining composition and packaging work:

- choose and document the production Mach service name;
- wire the service into the per-user LaunchAgent composition root;
- add signed bundle packaging and installer behavior;
- validate production code signing, hardened runtime, notarization, and
  entitlements;
- add actual App Intent types that call `HermesBridgeAppIntentAdapter`;
- add menu bar and Shortcuts callers;
- add production audit events using only redacted lifecycle metadata.
