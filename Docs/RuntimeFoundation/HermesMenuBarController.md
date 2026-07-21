# Hermes MenuBar Controller

## Architecture

M10 adds `HermesMenuBar`, a SwiftUI `MenuBarExtra` executable that is the first
runtime-kernel user entry point.

```text
macOS MenuBarExtra
        |
HermesMenuBarViewModel
        |
HermesMenuBarController
        |
HermesRuntimeCommandAPI
        |
Hermes Runtime Kernel
```

The controller depends on the `HermesRuntimeCommandExecuting` protocol, which is
implemented by `HermesRuntimeCommandAPI`. This keeps the MenuBar layer on the
runtime command boundary and avoids direct access to the session manager,
backend adapter, process supervisor, shell, or filesystem execution details.

## Data Flow

The MenuBar app creates a production `HermesRuntimeCommandAPI` and injects it
into `HermesMenuBarViewModel`.

The view model is a `@MainActor` `ObservableObject` that publishes
`HermesMenuBarState` for SwiftUI. It forwards user actions to
`HermesMenuBarController`:

- Start Hermes -> `HermesRuntimeCommand.createSession` when needed, then
  `HermesRuntimeCommand.startSession`.
- Stop Hermes -> `HermesRuntimeCommand.stopSession`.
- Refresh Status -> `HermesRuntimeCommand.getSessionStatus`, or
  `createSession` when no session exists yet.
- Open Events View -> local view state only.

Runtime event updates are event driven. The controller subscribes through
`HermesRuntimeCommand.subscribeEvents` and updates MenuBar state as events
arrive. The MenuBar layer does not run polling loops.

## Security Boundary

The MenuBar state intentionally exposes only sanitized runtime information:

- runtime status;
- coarse health state;
- backend semantic version;
- gateway state and active-agent count;
- shutdown reason;
- recent event kind, status, timestamp, and sanitized error text.

The UI does not expose:

- tokens or credentials;
- executable paths;
- filesystem paths;
- raw process IDs;
- process group IDs;
- supervisor state or launch context internals.

Errors are redacted before they enter MenuBar view state. Runtime event data is
adapted from `HermesRuntimeCommandEvent`, which omits raw process details from
the public command event session summary.

## Extension Points

Future MenuBar work should extend the runtime command surface first, then consume
the new command from `HermesMenuBarController`. Examples:

- a dedicated `refreshSessionStatus` runtime command;
- richer health details with sanitized fields;
- pause, emergency stop, and diagnostics commands;
- a full runtime events window with filtering and export-safe summaries.

The MenuBar layer must continue to avoid direct backend, supervisor, shell,
AppleScript, GUI automation, MCP, or agent-chat integrations.
