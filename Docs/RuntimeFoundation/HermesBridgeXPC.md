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
minor: 2
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
- `bindingDiscovery`
- `authorizedRootManagement`
- `fileEventObservation`

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
- `listEnabledBindings`: no payload.
- `listAuthorizedRoots`: no payload.
- `registerAuthorizedRoot`: display name and bounded bookmark data.
- `refreshAuthorizedRoot`: root ID, bounded bookmark data, optional expected revision.
- `deactivateAuthorizedRoot`: root ID and optional expected revision.
- `reactivateAuthorizedRoot`: root ID, bounded bookmark data, optional expected revision.
- `removeAuthorizedRoot`: root ID and optional expected revision.
- `authorizedRootStatus`: root ID.
- `createFileEventSubscription`: selected authorized root IDs.
- `pollFileEventSubscription`: subscription ID and bounded timeout.
- `acknowledgeFileEventBatch`: subscription ID and delivered event cursor.
- `cancelFileEventSubscription`: subscription ID.
- `fileEventMonitorStatus`: no payload.

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
- enabled binding summaries.
- authorized-root summaries.
- file-event subscription status.
- bounded file-event batches.
- file-event acknowledgement summaries.

Status summaries include request ID, binding ID, lifecycle state, cancellation
flag, result availability, and redacted failure code/retryability. They do not
include prompts, backend session tokens, raw stdout/stderr, backend process
PID/PGID, or raw result bodies.

Binding summaries include only binding ID, localized display name, safe
localized description, maximum Prompt length, approval policy, and enabled
state. They do not include executable paths, process arguments, endpoints,
backend tokens, JSON-RPC methods, environments, result locators, prompts, raw
result bodies, or private filesystem paths.

Authorized-root summaries include root ID, display name, active state, stale
authorization state, security-scope status, last observed event ID, revision,
and safe root-kind metadata. They do not include absolute resolved paths,
bookmark data, file contents, volume-private identifiers, prompts, tokens, or
private filesystem paths.

File-event summaries include only root ID, root-relative path, event kind,
event ID, directory hint, bounded flags, and replay state. File-event batch
payloads include subscription ID, root ID, bounded events, newest event ID,
history/replay markers, rescan-required state, and a safe dropped-event reason.

## Size Limits

The shared protocol limits are:

```text
maximum envelope: 128 KiB
maximum transient prompt: 64 KiB
maximum correlation ID: 128 characters
maximum Mach service name: 255 characters
maximum XPC bookmark payload: 80 KiB
maximum XPC file-event batch: 64 KiB
maximum XPC file-event count: 128
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
- `unsupportedCapability`
- `invalidBinding`
- `requestNotFound`
- `invalidState`
- `serviceUnavailable`
- `rootNotFound`
- `rootInactive`
- `invalidBookmark`
- `bookmarkTooLarge`
- `staleAuthorization`
- `securityScopeUnavailable`
- `subscriptionNotFound`
- `subscriptionExpired`
- `acknowledgementRejected`
- `eventBufferOverflow`
- `rescanRequired`
- `internalFailure`

The service maps `HermesRequestOrchestratorError` into this set and emits fixed
safe messages. It does not propagate raw `NSError`, process, WebSocket,
filesystem, backend token, prompt, stdout, stderr, or diagnostic descriptions
through XPC.

File-integration errors are similarly redacted. Raw bookmark, filesystem, and
FSEvents error descriptions are mapped to typed safe codes.

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
- `listEnabledBindings()`
- `listAuthorizedRoots()`
- `registerAuthorizedRoot(displayName:bookmarkData:)`
- `refreshAuthorizedRoot(rootID:bookmarkData:expectedRevision:)`
- `deactivateAuthorizedRoot(rootID:expectedRevision:)`
- `reactivateAuthorizedRoot(rootID:bookmarkData:expectedRevision:)`
- `removeAuthorizedRoot(rootID:expectedRevision:)`
- `authorizedRootStatus(rootID:)`
- `createFileEventSubscription(rootIDs:)`
- `pollFileEventSubscription(subscriptionID:timeoutMilliseconds:)`
- `acknowledgeFileEventBatch(subscriptionID:acknowledgedEventID:)`
- `cancelFileEventSubscription(subscriptionID:)`
- `fileEventMonitorStatus()`
- `close()`

The public client API does not expose raw `Data`, arbitrary operation names, or
generic request methods. Raw transport is confined to internal adapters.
Timeouts are enforced by the client. Interruption and invalidation are surfaced
as typed client errors. Repeated `close()` calls are idempotent.

`HermesBridgeFileIntegrationAppAdapter` prepares future app UI code for
authorized-root list, bookmark registration, and event-status display. The
future `NSOpenPanel` bookmark creation flow remains a separate user
authorization issue.

## File-Event Subscription Semantics

The Bridge composition root installs a narrow file-integration coordinator over
the authorized-root registry and FSEvents monitor. The coordinator owns
generated subscription IDs, verifies selected root IDs, starts/stops monitor
lifecycle, normalizes monitor batches into XPC summaries, and performs shutdown
cleanup. It does not submit file events to Hermes prompts.

The broker keeps separate observed, delivered, and acknowledged cursors. The
acknowledged cursor advances only after `acknowledgeFileEventBatch`. Duplicate
acknowledgements at or behind the acknowledged cursor are idempotent; cursors
beyond the delivered cursor are rejected.

Polling is bounded by timeout and response size. Slow consumers are handled by
bounded pending queues; overflow drops retained batches and emits
`rescanRequired` with a safe dropped-event reason rather than growing memory.
Replay and history-done states are explicit. When retained history is
unavailable, clients must rescan and the service does not imply lossless replay.

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
- file contents;
- bookmark data in responses;
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
