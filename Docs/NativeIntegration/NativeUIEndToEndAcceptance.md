# Native UI End-to-End Acceptance

M11-002 adds a deterministic acceptance harness for the composed native UI client and
the service-owned Runtime graph completed in M11-001.

Run:

```sh
Scripts/m11_002_native_ui_e2e_acceptance.sh
```

The harness writes machine-readable evidence to:

```text
artifacts/m11-002/result.txt
```

`artifacts/` remains ignored by Git.

## Topology

The acceptance path is:

```text
HermesBridgeApp
  -> HermesAppClientGraph
  -> HermesBridgeRuntimeClientAdapter
  -> HermesBridgeXPCClient
  -> versioned HermesBridgeXPC protocol 1.7
  -> HermesBridgeServiceRequestHandler
  -> service-owned HermesBridgeCompositionRoot
  -> service-owned RuntimeCommandAPI / RuntimeSessionManager / RuntimeEventBus
```

The app-side composition root is statically checked to ensure it does not construct
`HermesRuntimeSessionManager`, `HermesRuntimeEventBus`, `HermesRuntimeCommandAPI`,
`HermesProcessSupervisor`, `HermesBackendAdapter`, or `HermesProtocolClient`.

The service-side composition root is instantiated directly with artifact-owned roots
and an artifact-owned fake Hermes backend. Runtime commands and runtime events cross
the XPC request dispatcher through encoded request and response envelopes.

## Window Routing

GUI automation is intentionally not used. The app already exposes typed route and
window abstractions, so the harness injects a recording window factory and validates:

- dashboard, logs, settings, and diagnostics routes open;
- repeated open focuses the existing logical window;
- close and reopen reuses the existing logical window controller;
- only fixed `HermesNativeUIWindowIdentifier` cases are accepted.

Arbitrary string identifiers are impossible at the router/coordinator boundary because
the public API accepts `HermesNativeUIRoute` and `HermesNativeUIWindowIdentifier`, not
raw strings.

## Runtime Lifecycle

The fake backend is generated under `artifacts/m11-002/run-*` and implements only the
bounded Hermes backend protocol needed by the Runtime stack. The lifecycle acceptance:

- creates a session through the app-side client abstraction;
- starts it through XPC;
- observes running status through XPC;
- receives ordered runtime events through XPC;
- invalidates the first UI client without calling `stopSession`;
- verifies the service-owned session remains running;
- reconnects with a new UI client and observes the existing running session;
- sends one explicit stop;
- verifies the backend received exactly one stop signal and the session reaches stopped.

## Security And Cleanup

The fake backend emits sentinel token, private path, and PID-like values in its private
process output. Exported DTOs and `result.txt` are scanned to ensure those sentinels do
not escape.

The harness does not use sudo, LaunchAgents, Keychain, AppleScript, browser automation,
`killall`, or `pkill`. Cleanup stops only service-owned sessions and checks that no
harness-owned process remains by matching the artifact-owned run directory path.
