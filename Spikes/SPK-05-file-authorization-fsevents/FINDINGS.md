# SPK-05 Findings

Evidence was produced by the spike script on the dedicated research Mac.
Generated logs, Swift sources, binaries, and bookmark data are under
`artifacts/spk-05/active/run-20260717T035728Z-43270` and are intentionally not tracked.

## Result Summary

- Read-only result: PASS.
- Active result: PASS.
- FSEvents monitor availability: yes.
- Approved root: `artifacts/spk-05/active/run-20260717T035728Z-43270/approved-root`.
- File create observed: yes.
- File modify observed: yes.
- File rename observed: yes.
- File delete observed: yes.
- Recursive events observed: yes.
- Root mutation behavior: root-change-event-after-rename-delete.
- Event replay availability: yes.
- Bookmark create available: yes.
- Bookmark resolve available: yes.
- Security-scoped access proven: no.
- Path boundary enforced: yes.
- Residual monitor process: no.
- Verdict: SPK-05 VERDICT: CONDITIONAL GO.

## Event Flags And Operation Mapping

The active helper used `FSEventStreamCreate` with file-level events and
`WatchRoot`. It emitted only event IDs, relative paths, flags, flag names, and
timestamps.

Observed mapping from the passing run:

- File creation produced `scenario-a/file.txt` with flags `69888`
  (`ItemCreated,ItemModified,ItemIsFile`).
- File modification produced `scenario-a/file.txt` with flags `70912`
  (`ItemCreated,ItemInodeMetaMod,ItemModified,ItemIsFile`).
- File rename produced old-path and new-path events carrying `ItemRenamed`;
  the passing run observed flags `72960` on the old path and `67584` on the
  new path.
- File deletion produced `scenario-a/file-renamed.txt` with flags `68096`
  (`ItemRemoved,ItemRenamed,ItemIsFile`).
- Directory creation produced `scenario-b`, `scenario-b/nested`, and
  `scenario-b/nested/child` with flags `131328`
  (`ItemCreated,ItemIsDir`).
- Nested file creation and modification produced descendant file events under
  `scenario-b/nested/child/nested.txt`.
- Directory rename produced old and new directory path events with
  `ItemRenamed` and `ItemIsDir`.
- Recursive deletion produced child file and directory events with
  `ItemRemoved` and `ItemIsFile` or `ItemIsDir`.
- Restart replay emitted `scenario-d/while-stopped.txt` and a
  root-relative `HistoryDone` marker when replay was available.

The exact per-event records are in the active monitor logs under
`artifacts/spk-05/active/run-20260717T035728Z-43270`.

## Latency, Batching, And Duplicates

The monitor latency was configured at 0.20 seconds. Controlled operations were
separated by short sleeps so latency stayed within the bounded monitor window.
FSEvents delivered 22 event records across 14 observed
batches. Batched delivery occurred. Consumers must tolerate coalescing and
duplicate semantic notifications, including history-marker events that can
share an event ID with replayed file events.

## Recursive Event Behavior

Recursive descendant changes were observed as relative paths under the approved
root. The helper did not need to open or read generated file contents.

## Root Rename And Delete Behavior

With `WatchRoot`, root mutation produced root-level and/or descendant events
instead of granting visibility outside the approved artifact boundary. After the
root was renamed or deleted, the script recreated only artifact-owned paths for
subsequent scenarios. Behavior classification: root-change-event-after-rename-delete.

The passing run observed root-relative `.` events carrying flags `32`
(`RootChanged`) and `133120` (`ItemRenamed,ItemIsDir`).

## Restart And Event ID Behavior

The script captured the last observed event ID, stopped the monitor, performed
controlled changes, and restarted with that ID as `sinceWhen`. Result:
yes. This is evidence for local behavior only; production code
must still treat replay as best-effort and reconcile state after restart.

## Bookmark Results

Ordinary bookmark creation result: yes. Ordinary bookmark
resolution result: yes. Stale status was recorded in the active
bookmark probe log.

Security-scoped bookmark APIs were attempted only for the generated test
directory. Security-scoped access proven: no. A successful API
call outside a sandboxed, user-selected folder flow is not proof of production
authorization.

The local API may accept security-scoped options for the generated directory,
but the script does not treat that as production authorization evidence unless a
signed sandboxed app, entitlement, and user-selected folder flow are actually
part of the test.

## Ordinary Bookmarks Versus Security-Scoped Authorization

Ordinary bookmarks can preserve a durable reference to a filesystem URL, but
they are not the same as user-granted sandbox extension authorization.
Production security-scoped authorization requires a user-facing selection flow,
the appropriate app sandbox and file access entitlements, and stale-bookmark
handling.

## LaunchAgent Authorization Implications

A LaunchAgent should not accept arbitrary client-supplied paths or assume it can
reuse user-granted access by itself. The selected architecture remains
app-mediated: a user-facing app obtains authorization, stores a versioned
security-scoped bookmark, and the Bridge resolves only allowlisted bookmarks.

## Privacy And Audit Requirements

Audit events may safely include approved-root identity, event ID, timestamp,
normalized relative path, and normalized event kind. They must not include file
contents, bookmark blobs, unneeded absolute host paths, or unrelated filesystem
metadata.

## Security Boundary

The active helper refused roots outside `artifacts/spk-05/active`, monitored
only the generated approved root, logged only relative paths, and did not read
file contents. Generated artifacts remain under `artifacts/spk-05/`.

## Remaining Blockers

- End-to-end security-scoped authorization still needs a signed, sandboxed,
  user-facing app or helper with an `NSOpenPanel` selection flow.
- Production restart handling should include state reconciliation because
  FSEvents replay and coalescing are best-effort operational signals.
- Authorization storage format and allowlist contract still need versioned IPC
  design.

## SPK-05 Verdict

SPK-05 VERDICT: CONDITIONAL GO
