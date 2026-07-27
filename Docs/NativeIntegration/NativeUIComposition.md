# Native UI Composition

M11-001 composes the native macOS UI through one application-owned composition root.

## Composition Root

`HermesBridgeApp` owns a single `HermesAppCompositionRoot`. The composition root creates the menu bar view model, `HermesNativeUIRouter`, and `HermesWindowCoordinator`.

The app delegate references the same composition root during application termination so shutdown cleanup runs before macOS finishes terminating the app.

## Dependency Ownership

`HermesAppRuntimeGraph` owns the runtime dependency graph:

- `HermesRuntimeEventBus`
- `HermesRuntimeSessionManager`
- `HermesRuntimeCommandAPI`
- `HermesConfigurationStoring`

The graph is constructed once by the composition root and injected into every UI module. Dashboard, Menu Bar, and Diagnostics receive the shared `HermesRuntimeCommandAPI`. Logs receives the shared `HermesRuntimeEventBus`. Settings receives the shared configuration store.

No feature window constructs its own runtime session manager, event bus, or command API.

## Window Routing

`HermesNativeUIRoute` exposes fixed routes for Dashboard, Logs, Settings, and Diagnostics. Each route maps to a typed `HermesNativeUIWindowIdentifier`.

The identifiers are fixed enum values:

- `com.hermes.bridge.window.dashboard`
- `com.hermes.bridge.window.logs`
- `com.hermes.bridge.window.settings`
- `com.hermes.bridge.window.diagnostics`

The router does not accept arbitrary strings, URLs, file paths, process IDs, tokens, credentials, or user-controlled identifiers.

## Lifecycle

`HermesWindowCoordinator` maintains one logical window per feature. Opening a route creates the window the first time. Opening the same route again focuses the existing open window. If the window was closed, opening the route shows the same logical window again.

Closing a feature window does not stop Hermes runtime sessions and does not tear down the shared runtime graph.

Application shutdown performs controlled cleanup:

1. cancel the menu bar runtime subscription;
2. clean up all feature windows;
3. ask the shared runtime graph to stop active runtime sessions.

Shutdown is idempotent.

## Security Boundary

Native UI composition only routes between fixed native windows. It does not add shell execution, AppleScript, browser automation, arbitrary URL opening, arbitrary executable paths, or generic process execution.

Routing state is limited to typed window identifiers. Secrets, credentials, file paths, and process IDs are not stored in routing state.
