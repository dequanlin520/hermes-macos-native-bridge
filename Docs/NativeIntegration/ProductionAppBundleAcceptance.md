# Production App Bundle Acceptance

M11-003 validates the real built `HermesBridgeApp.app` artifact and its service/XPC
integration without installing the app or permanently installing a service.

Run:

```sh
Scripts/m11_003_production_app_bundle_acceptance.sh
```

The machine-readable result is written to:

```text
artifacts/m11-003/result.txt
```

`artifacts/` is ignored by Git.

## Bundle Topology

The acceptance bundle is assembled under:

```text
artifacts/m11-003/Hermes Bridge.app
```

The harness builds the existing Xcode project:

```text
Packaging/HermesBridgeApp/HermesBridgeApp.xcodeproj
```

The project delegates to the SwiftPM `HermesBridgeApp` product. The harness then
copies the app executable, `Packaging/HermesBridgeApp/Info.plist`, the existing
`HermesBridgeService` product, and the existing LaunchAgent template into the bundle:

```text
Contents/MacOS/HermesBridgeApp
Contents/Info.plist
Contents/Frameworks/
Contents/XPCServices/
Contents/Library/HermesBridge/HermesBridgeService
Contents/Library/LaunchAgents/com.hermes.bridge.plist.template
Contents/Resources/
```

`Contents/XPCServices` is present for topology inspection, but this repository's
current service integration is LaunchAgent/Mach-service based. No duplicate XPC
service target is invented.

## Embedded Ownership

The app bundle embeds only the existing service executable and LaunchAgent template
as resources. Runtime ownership remains in the service process:

```text
HermesBridgeApp
  -> HermesAppCompositionRoot
  -> HermesAppClientGraph
  -> HermesBridgeRuntimeClientAdapter
  -> HermesBridgeXPCClient
  -> com.hermes.bridge.xpc
  -> HermesBridgeService
  -> HermesBridgeCompositionRoot
  -> RuntimeCommandAPI / RuntimeSessionManager / RuntimeEventBus
```

The app target is statically scanned for concrete runtime graph constructors:

```text
HermesRuntimeSessionManager(
HermesRuntimeEventBus(
HermesRuntimeCommandAPI(
HermesProcessSupervisor(
HermesBackendAdapter(
HermesProtocolClient(
```

The expected result is `APP_OWNS_CONCRETE_RUNTIME=no`. The service handshake must
report XPC protocol `1.7` and runtime command/event capabilities.

## XPC Connection Path

The app production graph uses `HermesBridgeXPCClient(machServiceName:
com.hermes.bridge.xpc)`. Because the production graph hardcodes that Mach service
name, the harness refuses to run if `gui/$UID/com.hermes.bridge` is already present.

When clear, the harness bootstraps a temporary LaunchAgent directly from
`artifacts/m11-003/run/com.hermes.bridge.m11-003.plist`. The plist points at the
bundle-embedded `HermesBridgeService` and an artifact-owned configuration file.
It is removed with `launchctl bootout` during cleanup.

## Runtime Lifecycle Independence

The app has a launch-argument-gated M11-003 acceptance hook:

```text
--hermes-m11-003-acceptance start-and-hold <state> <evidence>
--hermes-m11-003-acceptance reconnect-and-stop <state> <evidence>
```

Normal launches do not enable the hook. In acceptance mode the hook reuses the
already composed `HermesAppCompositionRoot.clientGraph`; it does not create a
runtime graph.

The lifecycle validation is:

1. launch the built app executable as an exact harness-owned process;
2. connect to the temporary service over XPC protocol `1.7`;
3. open Dashboard, Logs, Settings, and Diagnostics through typed app routes;
4. create and start a session through the app client graph;
5. receive a runtime event over the XPC event subscription path;
6. terminate only the exact first app PID;
7. relaunch the same built app bundle;
8. reconnect to the existing running runtime;
9. issue one explicit stop through the app client graph;
10. prove the app forwarded one stop command and the service reports the session stopped.

Quitting or terminating the UI process is not treated as Stop Hermes.

## Signing State

The harness performs non-destructive signing inspection with:

```text
codesign --verify --deep --strict
codesign -dv
spctl --assess --type execute
```

It does not create signing identities, import identities, access unrelated Keychain
entries, notarize, or claim production signing. An unsigned local Debug acceptance
bundle is acceptable for this milestone when `SIGNING_STATE=unsigned` is reported.

## Security Scan Scope

The security scan covers the resulting app bundle and exported acceptance evidence:

```text
result.txt
app-first.evidence
app-second.evidence
session-state.txt
```

The scan looks for sentinel token/password/credential patterns, private key blocks,
private developer/repository paths in product resources or exported evidence, and
PID-shaped exported DTO evidence. It intentionally does not fail on normal Mach-O
metadata or system SDK paths.

The artifact-owned service configuration contains temporary paths by design and is
not embedded as a production default.

## Cleanup Guarantees

The harness does not use sudo, AppleScript, GUI automation, `/Applications`,
`~/.hermes`, `killall`, or `pkill`. It does not permanently install the app, service,
or LaunchAgent.

Cleanup terminates only the exact harness-owned app PID, boots out only the
artifact-owned LaunchAgent plist, and checks for residual processes tied to the
artifact run root.

## Limitations

This milestone validates an isolated Debug or unsigned acceptance bundle. It does
not prove notarization, Developer ID signing, installer behavior, auto-update,
permanent LaunchAgent installation, or production `/Applications` deployment.
