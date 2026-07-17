# HermesBridgeService Runtime Foundation

## Scope

`HermesBridgeService` is the first executable Bridge service. It composes the
existing Runtime Foundation and `HermesBridgeXPC` modules behind one fixed
per-user Mach service:

```text
com.hermes.bridge.xpc
```

The launchd label documented for packaging is:

```text
com.hermes.bridge
```

This component does not install a service, claim signing or notarization,
submit prompts during startup, or replace future app packaging.

## Composition Graph

The composition root constructs:

- `HermesDiscovery`;
- `HermesProcessSupervisor`;
- `HermesProtocolClientFactory`;
- `FileBackedHermesRequestStateStore`;
- configuration-backed binding registry;
- `HermesRequestOrchestrator`;
- `HermesBridgeXPCRequestDispatcher`;
- `HermesBridgeXPCService`.

Shutdown ordering is owned by `HermesBridgeCompositionRoot`: XPC work is
invalidated first, then the orchestrator closes protocol state and stops the
supervisor.

## Executable Lifecycle

The executable loads production defaults unless an explicit artifact-owned test
configuration is enabled for integration testing. It starts
`HermesBridgeServiceHost`, prints exactly one readiness marker, then waits for
SIGTERM or SIGINT:

```text
HERMES_BRIDGE_SERVICE_READY service=com.hermes.bridge.xpc
```

Startup failures are reported as redacted error codes only. Private paths,
prompts, backend tokens, stdout/stderr bodies, and arbitrary XPC payloads are
not printed.

## Runtime Roots

Production defaults use an application-support root named `HermesBridge`.
Tests and integration use `artifacts/m2-008`. The service resolves and creates:

- runtime root;
- request-state root;
- logs root;
- temporary root.

Roots are directories with restrictive permissions where supported. Symlink
roots and symlink component escapes are rejected.

## Binding Registry

The production registry is configuration-backed. Binding definitions are
versioned, have fixed binding IDs, an enabled flag, prompt byte limit, timeout
policy, and approval policy. The default production configuration contains no
enabled production bindings.

Definitions cannot name executable paths, endpoints, JSON-RPC methods, or
Shortcut names.

## Security Boundary

The service exposes only `HermesBridgeXPCProtocol` over NSXPC. Callers cannot
select a Mach service name, process arguments, environment dictionary,
endpoint, token, JSON-RPC method, executable path, Shortcut name, or
persistence path. Prompts remain transient and are not stored in configuration
or request-state records.

The service logger records only timestamp, subsystem/category, lifecycle event,
protocol version, safe correlation/request/binding IDs, and redacted error
codes.

## Integration Status

`Scripts/integration/m2-008-launchagent-xpc.zsh` builds the executable and runs
an opt-in XCTest that:

- writes all paths under `artifacts/m2-008`;
- creates a unique test label and Mach service;
- bootstraps into `gui/<uid>`;
- waits for the fixed readiness marker;
- connects with `HermesBridgeXPCClient`;
- performs protocol version and capability queries only;
- boots out the exact generated plist;
- verifies service/process absence and no token or prompt leakage.

The integration test does not submit a prompt and does not launch real Hermes.

## Packaging Limitations

Signing, notarization, hardened runtime, entitlement policy, installer UX,
log rotation, persistent installation, and user-visible service management are
out of scope for this issue.

The next step toward M3 or signed app packaging is an installer or app-bundle
issue that owns signing identity, LaunchAgent placement, upgrade/removal
behavior, and user-facing controls.
