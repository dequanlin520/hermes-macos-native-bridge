# File Events XPC

## Protocol Version

M5-004 raises the compatible Bridge XPC protocol version to `1.3`.

The added capabilities are:

- `authorizedRootManagement`;
- `fileEventObservation`.

The M5-004 protocol minor also adds typed service-side authorized-root
resolution so the Bridge can report stale state, same-root resolution and
whether `startAccessingSecurityScopedResource()` succeeded in the service.

The major version remains `1`, so existing `1.x` clients continue to negotiate
with the service. Compositions that do not install file integration return the
typed `unsupportedCapability` error for these operations.

## Authorized-Root Boundary

The XPC surface exposes safe `HermesBridgeAuthorizedRootSummary` values only:

- root ID;
- display name;
- active state;
- stale authorization state;
- security-scope availability state;
- last observed FSEvents ID;
- revision;
- safe root kind metadata.

Summaries do not include absolute resolved paths, bookmark data, file contents,
volume-private identifiers, prompts, backend tokens, or diagnostic filesystem
details.

Registration and refresh accept bookmark `Data` created by trusted app code
after explicit user selection. XPC does not accept a path string alternative.
The XPC bookmark payload is bounded below the envelope limit so oversized
bookmark data is rejected as `bookmarkTooLarge`.

Supported root operations are:

- `listAuthorizedRoots`;
- `registerAuthorizedRoot`;
- `refreshAuthorizedRoot`;
- `deactivateAuthorizedRoot`;
- `reactivateAuthorizedRoot`;
- `removeAuthorizedRoot`;
- `authorizedRootStatus`.

## Event Summaries

`HermesBridgeFileEventSummary` includes:

- root ID;
- root-relative path;
- event kind;
- event ID;
- directory hint;
- bounded typed flags;
- replay marker.

It does not include absolute paths, file content, bookmark data, prompts, or
tokens.

`HermesBridgeFileEventBatchPayload` includes the subscription ID, root ID,
bounded events, newest event ID, replay state, history-done state, rescan
state, and a safe dropped-event reason.

The batch contract bounds event count, root-relative path byte length through
`HermesRootRelativePath`, and encoded payload size.

## Subscription Model

The Bridge owns an in-memory subscription broker. Clients can:

- `createFileEventSubscription`;
- `pollFileEventSubscription`;
- `acknowledgeFileEventBatch`;
- `cancelFileEventSubscription`;
- `fileEventMonitorStatus`.

Subscriptions use generated IDs and can include only selected authorized root
IDs. Creation verifies that each root exists and is active. Root count, pending
batches, polling timeout, and subscriber inactivity are bounded. Cancellation
is idempotent. Service shutdown cancels subscriptions and stops the monitor.

Polling is intentionally used instead of callback XPC. There is no unbounded
streaming method and no long-lived reply.

## Cursors And Backpressure

The implementation keeps separate cursor concepts:

- observed cursor from incoming FSEvents batches;
- delivered cursor for batches returned to a client;
- acknowledged cursor advanced only by explicit acknowledgement.

Acknowledgement is idempotent for already acknowledged cursors and rejected if a
client acknowledges beyond the delivered cursor.

Slow consumers do not grow memory without bound. When a subscription exceeds
the pending-batch limit, the broker drops retained batches and emits a
`rescanRequired` batch with a safe dropped-event reason.

## Replay And Rescan

FSEvents replay is best-effort. Replayed batches and history-done events are
marked explicitly. If retained batches are unavailable or event loss is
detected, the client receives `rescanRequired`; the XPC contract never claims
lossless replay when history is not available.

## Error Redaction

The file-integration XPC additions use redacted typed errors:

- `unsupportedCapability`;
- `rootNotFound`;
- `rootInactive`;
- `invalidBookmark`;
- `bookmarkTooLarge`;
- `staleAuthorization`;
- `securityScopeUnavailable`;
- `subscriptionNotFound`;
- `subscriptionExpired`;
- `acknowledgementRejected`;
- `eventBufferOverflow`;
- `rescanRequired`;
- `internalFailure`.

Raw Foundation, filesystem, bookmark, and FSEvents error descriptions are not
returned to callers.

## Next Authorization Step

M5-002 prepares the typed app adapter for future authorization UI. The next
issue should add the user-facing `NSOpenPanel` flow in the trusted app, create
ordinary or security-scoped bookmarks from explicit user selection, and then
call the bookmark registration operation. M5-002 does not implement that UI.
