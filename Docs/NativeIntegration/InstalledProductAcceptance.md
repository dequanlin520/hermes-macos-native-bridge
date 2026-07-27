# M11-004 Installed Product Integration Acceptance

M11-004 validates the installed Hermes macOS product topology under an artifact-owned root:

`artifacts/m11-004/install-root/`

This is not a real system-wide installation. The harness must not write to `/Applications`,
`/Library`, `~/Applications`, `~/Library/LaunchAgents`, real `~/.hermes`, Keychain, or unrelated
user state.

## Installed Topology

The acceptance harness stages the production app bundle and service into the isolated root:

- `Applications/Hermes Bridge.app`
- `Hermes Bridge.app/Contents/MacOS/HermesBridgeApp`
- `Hermes Bridge.app/Contents/Library/HermesBridge/HermesBridgeService`
- `Hermes Bridge.app/Contents/Library/LaunchAgents/com.hermes.bridge.plist.template`
- `Hermes Bridge.app/Contents/Frameworks`
- `Hermes Bridge.app/Contents/XPCServices`
- `Hermes Bridge.app/Contents/Resources/product-version.json`
- `fake-home/Library/Application Support/HermesBridge/install-state.json`
- `fake-home/Library/LaunchAgents/com.hermes.bridge.test.m3-001.plist`

The production app executable is copied from the release `HermesBridgeApp` product. Acceptance
support is built only as a harness-side observer and is not installed into the app bundle.

## Ownership Model

The native app owns UI composition and client routing through `HermesAppClientGraph`. It must not
construct concrete runtime graph objects such as `HermesRuntimeSessionManager`,
`HermesRuntimeEventBus`, `HermesRuntimeCommandAPI`, `HermesProcessSupervisor`,
`HermesBackendAdapter`, or `HermesProtocolClient`.

The service owns the concrete runtime graph through `HermesBridgeCompositionRoot`. The live probe
uses XPC protocol 1.7 to validate session creation, session start, runtime event delivery, reconnect,
and explicit stop.

## Launch Configuration

Install, upgrade, rollback, and uninstall transactions use the existing
`HermesBridgeServiceLifecycle` artifact-root mode. That mode creates a fake home under the isolated
root and records launchctl actions through the service manager's fake launchctl adapter.

For the live XPC probe, the harness bootstraps a temporary LaunchAgent plist from
`artifacts/m11-004/run/`. It uses the installed service binary and an artifact-owned service
configuration file. The job is booted out during cleanup. The harness refuses to run if the
production label is already visible in the user's launchd domain.

## Upgrade Transaction

The harness creates two deterministic product versions:

- `m11-004-A`
- `m11-004-B`

The versions differ only by acceptance-safe resource metadata in
`Contents/Resources/product-version.json` and by service manager version metadata. Upgrade uses the
existing service lifecycle `upgrade` command under the isolated root. Configuration and state
directories remain under the fake home.

## Rollback Transaction

Rollback uses the existing service lifecycle `rollback` command. The expected result is that
`m11-004-A` becomes active again in `install-state.json`, rollback metadata remains coherent, and
XPC connectivity remains available from the still-running installed service topology.

## Failed-Upgrade Recovery

The failure case uses a deterministic non-executable staged service binary inside
`artifacts/m11-004/run/`. The expected behavior is that the previously active version remains
active, partial `.staging-*` directories are absent, and the service is not left in an ambiguous
state.

## Uninstall Policy

Uninstall uses the existing service lifecycle `uninstall` command against the isolated root. The
expected cleanup removes installed versions, launch configuration, install state, and the app bundle.
User configuration/state/log directories are retained or removed according to the service manager's
existing `purgeState` and `purgeLogs` options. M11-004 does not request purge options.

## Security Scan Scope

The harness scans the isolated installed product and generated evidence for:

- token, password, credential, and private-key patterns
- production app acceptance symbols or launch arguments
- developer source and build paths

Normal Apple SDK and system framework paths inside Mach-O metadata are not treated as developer path
exposure. Artifact-owned paths are expected in isolated launch configuration because this is not a
real signed installation.

## Remaining Limitations

M11-004 does not prove a real signed installation into `/Applications` or a permanently loaded
LaunchAgent. It also does not exercise notarization, Developer ID signing, privileged helpers,
system-wide installation permissions, or post-login launchd persistence. Those remain prerequisites
for a later real installation acceptance gate.
