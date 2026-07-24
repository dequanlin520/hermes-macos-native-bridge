# Hermes Runtime Logs Viewer

## Architecture

M10-003 adds `HermesLogsViewer`, a SwiftUI observability component for runtime
events.

```text
Logs Viewer UI
        |
HermesLogsViewerViewModel
        |
HermesLogsViewerController
        |
HermesRuntimeEventBus
```

`HermesLogsViewerController` depends directly on `HermesRuntimeEventBus`. It
does not call `HermesProcessSupervisor`, `HermesBackendAdapter`,
`HermesProtocolClient`, or `HermesRuntimeCommandAPI`.

The viewer keeps in-memory UI state only:

- recent runtime log entries;
- the selected severity filter;
- a redacted last-error display string for failed events.

The clear action removes only the viewer's in-memory entries. It does not delete
runtime records, audit records, event bus history, or any external storage.

## Data Flow

The window owns a `HermesLogsViewerViewModel`. The view model runs on the main
actor and publishes `HermesLogsViewerState` for SwiftUI.

The controller subscribes to `HermesRuntimeEventBus` and converts each
`HermesRuntimeEvent` into a `HermesRuntimeLogEntry` containing:

- timestamp;
- event type;
- severity;
- redacted summary.

Severity is derived from event kind and runtime status:

- `error`: `sessionFailed` events or failed runtime status;
- `warning`: degraded runtime status or health-change events;
- `info`: all other runtime lifecycle events.

Filtering is applied in UI state with `all`, `info`, `warning`, and `error`
filters. Filtering never changes the collected entries.

## Security Boundary

The logs viewer is an observability surface over the event bus, not a runtime
control plane. It intentionally avoids process, backend, protocol, shell, and
filesystem integrations.

Log entries must not expose:

- tokens;
- credentials;
- filesystem paths;
- executable paths;
- process IDs.

Runtime event summaries are converted into short display strings and passed
through the viewer redaction layer before they enter view state. The UI displays
only the redacted summary, event type, timestamp, and severity. Future audit log
integration can be added as a separate data source without changing this
runtime-event boundary.
