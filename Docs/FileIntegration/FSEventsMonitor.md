# FSEvents Monitor

## Scope

`HermesFSEventsMonitor` observes one or more active authorized roots resolved
from `HermesAuthorizedRootRegistry`. It is recursive and uses file-level
FSEvents with root watching. It does not index file contents, read file bodies,
or emit absolute user paths.

The monitor rejects filesystem root `/`, the whole home directory, symlink
roots, and any root that has not passed authorized-root registration.

## Path Normalization

FSEvents callback paths are normalized by
`HermesAuthorizedRootPathNormalizer`:

- standardize the event path;
- reject traversal and null bytes;
- confirm the lexical path remains under the authorized root;
- resolve existing paths to catch symlink escapes;
- preserve missing leaf paths for rename and delete events;
- convert to a root-relative path;
- use `.` as the neutral marker for the root itself;
- bound relative paths by UTF-8 byte length.

If callback data is malformed or cannot be trusted, the monitor emits a
root-scoped `rescanRequired` marker instead of exposing an unsafe path.

## Event Model

`HermesFileEvent` contains:

- root ID;
- normalized kind;
- root-relative path only;
- FSEvent ID;
- timestamp;
- directory hint where known;
- bounded typed flags.

Kinds are:

- `created`;
- `modified`;
- `renamed`;
- `removed`;
- `metadataChanged`;
- `rootChanged`;
- `historyDone`;
- `rescanRequired`.

`HermesFileEventBatch` bounds event count and encoded size, includes newest
event ID, replay state, rescan-required state, and a typed dropped-event reason
when applicable.

## Cursor Semantics

Each root record stores `lastObservedFSEventID`. On start, the monitor uses that
cursor when available; otherwise it starts from `kFSEventStreamEventIdSinceNow`.

The cursor is persisted only after the batch handler returns successfully. If
the handler fails, the monitor does not infer that events were processed and
does not advance the cursor for that failed delivery.

## Replay And Rescan

On restart, FSEvents replay is best-effort. Batches are marked replayed when a
persisted cursor was used or a history marker is observed. A `historyDone` event
is emitted as a typed event. Consumers should reconcile state after restart
instead of assuming old events were fully processed.

The monitor emits `rescanRequired` when these loss or trust flags are observed:

- `MustScanSubDirs`;
- `UserDropped`;
- `KernelDropped`;
- `EventIdsWrapped`.

`RootChanged`, `Mount`, and `Unmount` are normalized as `rootChanged`.

## Lifecycle

The monitor retains each `FSEventStreamRef`, owns a serial callback queue and a
separate state queue, starts and stops idempotently, invalidates and releases
streams exactly once, and suppresses callback delivery after stop. It does not
create a residual helper process.

## Privacy Boundary

Events include root IDs and root-relative paths. They do not include file
contents, bookmark blobs, prompts, tokens, absolute user paths, unrelated
filesystem metadata, or diagnostics from outside authorized roots.

## Future Integration

This foundation is intended for future file-event XPC summaries and future file
indexing work. Those later layers must stay typed and must not expose arbitrary
path access. Any future file-content indexing requires a separate issue,
separate privacy review, and explicit user-facing product scope.

M5-004 automated validation proved selected-root event observation from a
sandboxed, ad-hoc signed app bookmark handoff and no sibling-root event
delivery. Manual `NSOpenPanel`/TCC selection evidence and release-signed app
validation remain separate work.
