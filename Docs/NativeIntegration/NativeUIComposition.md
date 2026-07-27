# Native UI Composition

M11-001 composes the native macOS UI through one application-owned client
composition root. Runtime ownership remains in the Bridge service process.

## Composition Root

`HermesBridgeApp` owns a single `HermesAppCompositionRoot`. The composition root
creates the app-owned client graph, menu bar view model, `HermesNativeUIRouter`,
and `HermesWindowCoordinator`.

The app delegate references the same composition root during application
termination so UI cleanup runs before macOS finishes terminating the app.

## Dependency Ownership

The runtime graph is service-owned:

- `HermesRuntimeEventBus`
- `HermesRuntimeSessionManager`
- `HermesRuntimeCommandAPI`
- `HermesBackendAdapter`
- `HermesProcessSupervisor`
- `HermesProtocolClient`

`HermesBridgeService` exposes runtime control and event observation through the
versioned `HermesBridgeXPC` protocol. Runtime commands enter the service through
the XPC dispatcher and are executed by the service-owned `HermesRuntimeCommandAPI`.
Runtime events are subscribed to through service-owned event subscriptions and
polled over the same versioned XPC envelope.

The app-owned graph is client-only:

- `HermesBridgeXPCClient`
- runtime command client abstraction
- runtime event subscription client abstraction
- `HermesConfigurationStoring`
- UI router and window coordinator
- view models and controllers

Dashboard, Menu Bar, and Diagnostics receive runtime command abstractions. Logs
receives a runtime event subscription abstraction. Settings receives the shared
configuration store.

No app or feature window constructs a runtime session manager, event bus,
command API, backend adapter, process supervisor, or protocol client. The app
process must not contain a duplicate runtime graph.

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

Closing a feature window does not stop Hermes runtime sessions and does not tear
down the service-owned runtime graph.

Application shutdown performs UI/client cleanup:

1. cancel the menu bar runtime subscription;
2. clean up all feature windows;
3. invalidate client-side XPC resources;
4. release window resources and UI tasks.

Shutdown is idempotent.

Application termination is independent from the Bridge service lifecycle. It
does not stop active runtime sessions, stop the backend, call
`HermesProcessSupervisor`, or treat quitting the UI as Stop Hermes.

Runtime is stopped only through an explicit user command, such as Stop Hermes in
the menu bar or Dashboard. That command is routed through the app-owned runtime
client abstraction, over versioned XPC, and into the service-owned
`HermesRuntimeCommandAPI`.

## Security Boundary

Native UI composition only routes between fixed native windows. It does not add shell execution, AppleScript, browser automation, arbitrary URL opening, arbitrary executable paths, or generic process execution.

Routing state is limited to typed window identifiers. Secrets, credentials, file paths, and process IDs are not stored in routing state.
