# HermesProcessSupervisor Runtime Foundation

## Scope

`HermesProcessSupervisor` is the narrow runtime foundation component that
launches and stops one Bridge-owned Hermes backend process. It does not expose
a generic process runner, accept arbitrary arguments, invoke a shell, read the
user's real `~/.hermes`, read Keychain, implement a protocol client, submit
runs, manage approvals, or install a LaunchAgent.

The supervisor accepts a `HermesExecutableCandidate` produced by the discovery
boundary and launches only the fixed Hermes serve command shape.

## Fixed Launch Command

The generated command is equivalent to:

```text
hermes --safe-mode serve --host 127.0.0.1 --port <validated-port> --skip-build --isolated
```

The public configuration contains the executable candidate, loopback host,
port, runtime root, startup timeout, graceful shutdown timeout, forced shutdown
timeout, and stdout/stderr byte limit. The host is restricted to
`127.0.0.1`, and ports must be in the TCP user range.

## Lifecycle State Machine

The supervisor exposes typed states:

- `idle`
- `starting`
- `ready(HermesProcessIdentity)`
- `stopping(HermesProcessIdentity)`
- `exited(HermesProcessExit)`
- `failed(HermesProcessFailure)`

Invalid concurrent starts are rejected with `alreadyRunning`. A completed or
failed supervisor may be started again with a new configuration. `stop()` is
idempotent after exit.

## Runtime Root Isolation

Each launch creates a unique Bridge-owned directory under the configured
runtime root. The supervisor creates:

- `HOME`
- `HERMES_HOME`
- `XDG_CONFIG_HOME`
- `XDG_CACHE_HOME`
- `XDG_DATA_HOME`
- `XDG_STATE_HOME`
- `XDG_RUNTIME_DIR`

Directories are created with restrictive `0700` permissions where supported.
The child receives only this fixed environment plus a minimal system `PATH` and
`LANG=C`.

## Readiness Contract

Stdout and stderr are captured asynchronously with bounded storage. Readiness
is accepted only when a complete output line exactly matches:

```text
HERMES_BACKEND_READY port=<configured-port>
```

A readiness line for any other port is rejected as malformed. Exit before
readiness produces `exitedBeforeReady`, and lack of readiness before the
startup deadline produces `startupTimedOut`.

## Process Identity Model

For every launch the supervisor records:

- PID;
- dedicated PGID;
- process start identity from Darwin process metadata;
- resolved executable path;
- launch UUID;
- expected command shape.

The retained PID, PGID, and start identity are rechecked before signaling. If
verification fails, the supervisor refuses to signal and reports
`identityVerificationFailed`.

## Process Group Ownership

The private launcher uses `posix_spawn` with `POSIX_SPAWN_SETPGROUP`, creating
a dedicated process group for the Bridge-owned launch. The supervisor never
uses `killall`, `pkill`, a shell, or process-name termination.

## Shutdown Algorithm

Shutdown proceeds as follows:

1. Verify the retained PID, PGID, and start identity.
2. Send `SIGTERM` to the negative verified PGID.
3. Wait for the parent process to exit and for the owned process group to
   drain within the graceful timeout.
4. Reverify identity before escalation.
5. Send `SIGKILL` only to the same verified process group if members remain.
6. Wait for the group to drain within the forced timeout.
7. Confirm the selected loopback port has closed.
8. Return bounded output and escaped-descendant observation metadata.

If the port remains open after the owned group exits, shutdown fails with
`portDidNotClose`.

## Escaped Descendant Limitation

A descendant can intentionally leave the owned process group, for example with
`setsid()`. The supervisor treats that as residual risk telemetry: it observes
processes whose command line references the launch runtime directory and whose
PGID differs from the owned PGID, but it does not broaden termination by name.
Port-closure enforcement catches the high-risk case where an escaped
descendant keeps the backend port open.

## Security Boundary

The supervisor preserves the product boundary:

- no arbitrary command arguments;
- no arbitrary environment injection;
- no shell invocation;
- no generic process execution abstraction;
- no access to the user's real Hermes home;
- no Keychain access;
- no Hermes protocol methods;
- no LaunchAgent behavior.

## Relationship To SPK-01 And SPK-03

SPK-01 identified the safe launch shape, loopback bind, isolated runtime root,
`HERMES_BACKEND_READY` readiness signal, bounded output capture, and enforcing
port cleanup. `HermesProcessSupervisor` implements those process-lifecycle
pieces without advancing to unproven protocol assumptions.

SPK-03 showed that PID-only shutdown leaves descendants behind and recommended
dedicated process groups, PID plus PGID plus start identity, verified group
`SIGTERM`, bounded wait, `SIGKILL` escalation against the same group, and
escaped-descendant telemetry. The supervisor follows that ownership model.

## Remaining Blocked Components

`HermesProtocolClient` remains blocked. No run submission, run status,
cancellation, approval, event streaming, capability discovery, or production
authentication model is implemented by this issue.
