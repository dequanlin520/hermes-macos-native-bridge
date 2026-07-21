# HermesBackendAdapter Runtime Foundation

## Scope

`HermesBackendAdapter` is the first production runtime adapter layer for the
Bridge-owned Hermes backend. It owns orchestration only. Discovery, process
lifecycle, shutdown, and protocol transport remain owned by the existing
Runtime Foundation components.

The typed adapter interface is:

- `discover()`;
- `start()`;
- `health()`;
- `stop()`.

## Component Integration

The adapter sequences the existing production components:

- `HermesDiscovery` validates an explicitly configured executable URL against
  an allowlisted candidate set and parses the fixed `--version` output.
- `HermesProcessSupervisor` launches the fixed safe Hermes serve command,
  creates the isolated runtime root, injects the Bridge-owned session token,
  waits for readiness, and owns shutdown.
- `HermesProtocolClient` performs the loopback `/api/status` health check using
  the launch context endpoint and token.

The adapter does not implement process spawning, readiness parsing, process
group cleanup, HTTP transport, WebSocket transport, JSON-RPC, or session
methods.

## Lifecycle

`discover()` returns the `HermesDiscoveryResult` for the configured executable.
Discovery errors are mapped to `HermesBackendAdapterError.discoveryFailed`.

`start()` performs discovery, builds a `HermesProcessConfiguration` from the
typed adapter configuration, asks the supervisor to start Hermes, creates a
protocol client from the returned `HermesBackendLaunchContext`, and validates
protocol availability with `fetchStatus()`.

If the protocol check fails after launch, the adapter closes the protocol
client, asks the supervisor to stop the process, and returns
`protocolUnavailable`.

`health()` fetches the current backend status through the retained protocol
client and returns it with the current process and protocol states. Calling
`health()` before a successful start returns `notStarted`.

`stop()` closes the retained protocol client and delegates shutdown to the
supervisor. Repeated shutdown remains idempotent because the supervisor owns
that state machine.

## Security Boundary

The adapter preserves the existing runtime security model:

- no shell execution;
- no arbitrary command or argument surface;
- no arbitrary executable path beyond the discovery allowlist;
- no arbitrary endpoint, host, REST path, WebSocket path, or JSON-RPC method;
- no prompt submission path;
- no token logging;
- no real user profile access.

The configured runtime root is passed to `HermesProcessSupervisor`, which
creates an isolated Bridge-owned runtime directory and fixed environment. The
adapter does not read `~/.hermes`, Keychain, browser state, or unrelated user
files.

## Error Redaction

Adapter errors carry sanitized messages. Token-bearing markers such as
`token=`, `X-Hermes-Session-Token=`, and
`HERMES_DASHBOARD_SESSION_TOKEN=` are redacted before errors cross the adapter
boundary.

The adapter does not log errors itself. Callers should treat
`HermesBackendAdapterError.description` as the diagnostic-safe string form.

## Testing

Adapter tests use typed test doubles for discovery, supervision, and protocol
health so adapter orchestration is tested without duplicating real lifecycle or
transport coverage.

Covered adapter behavior includes:

- discovery failure mapping;
- successful startup orchestration;
- health failure mapping;
- graceful shutdown;
- repeated shutdown;
- protocol unavailable cleanup during startup;
- redacted token-carrying errors.
