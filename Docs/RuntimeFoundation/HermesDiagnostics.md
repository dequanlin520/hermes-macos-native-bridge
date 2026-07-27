# Hermes Diagnostics Center

M10-005 adds `HermesDiagnostics`, a native SwiftUI diagnostics center for
command-safe Hermes runtime health and environment inspection.

## Architecture

```text
HermesDiagnosticsWindow
        |
HermesDiagnosticsViewModel
        |
HermesDiagnosticsController
        |
HermesDiagnosticProvider
```

`HermesDiagnosticsWindow` is the AppKit-hosted SwiftUI surface. The view model
runs on the main actor and publishes `HermesDiagnosticsState`. The controller is
an actor that serializes refresh and Run Diagnostics actions. The provider owns
runtime aggregation and returns a versioned `HermesDiagnosticResult`.

The provider depends on `HermesDiagnosticsRuntimeCommandExecuting`, implemented
by `HermesRuntimeCommandAPI`. It does not expose process supervisor, backend
adapter, or protocol client references to the UI.

## Data Flow

1. The window asks the view model to refresh.
2. The view model calls `HermesDiagnosticsController`.
3. The controller invokes `HermesDiagnosticProvider.runDiagnostics()`.
4. The provider reads sanitized session summaries through
   `HermesRuntimeCommand.listSessions`, gathers permission states through the
   permissions diagnostic reporter, and records macOS/version/architecture
   metadata.
5. The controller stores the aggregated `HermesDiagnosticResult` in view state.

The result includes:

- Runtime health summary: discovery, process, backend, session, and EventBus
  state.
- Environment information: macOS version, architecture, Hermes version, and
  permission states.
- Session diagnostics: active, running, and failed session counts.

## Security Boundary

Diagnostics state is intentionally limited to command-safe and display-safe
fields. The diagnostics module must not surface:

- tokens;
- passwords;
- credentials;
- private keys;
- filesystem paths;
- executable paths;
- process IDs.

`HermesRuntimeCommandSessionStatus` omits raw executable paths and process
identity fields. `HermesDiagnosticRedactor` also sanitizes provider errors,
issues, environment strings, and permission display values before they enter UI
state.

The UI does not access `HermesProcessSupervisor`, `HermesBackendAdapter`, or
`HermesProtocolClient` directly. Any future provider that needs lower-level
runtime evidence must convert it into redacted diagnostic models before crossing
the provider boundary.
