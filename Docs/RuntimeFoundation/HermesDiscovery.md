# HermesDiscovery Runtime Foundation

## Scope

`HermesDiscovery` is the first narrow runtime foundation component for the
macOS Bridge. It discovers only concrete executable candidates injected by the
caller as an allowlist, records direct symlink metadata, executes the fixed
version probe, and returns typed candidate and version data.

The component does not start Hermes, manage a long-running process, submit
runs, inspect user Hermes state, read Keychain, call Shortcuts, expose XPC, or
implement protocol authentication.

## Security Boundary

The only process invocation is:

```text
<allowlisted-candidate> --version
```

The implementation uses `Process` directly with a fixed argument array. It does
not invoke a shell, accept arbitrary arguments, accept arbitrary environment
injection, or expose a public generic process runner. Output capture is bounded,
timeouts are enforced, and returned diagnostics contain a SHA-256 digest plus
sanitized metadata instead of raw private paths.

Candidate paths must exactly match the injected allowlist before filesystem
checks or execution. Symlink resolution records metadata for the candidate path
without reading `~/.hermes` contents.

## Relationship To SPK-01

SPK-01 established that future adapter work should first discover an
allowlisted Hermes binary, record resolved symlink metadata, run
`hermes --version`, and parse the observed output before any launch. The
observed version shape was:

```text
Hermes Agent v0.18.2 (2026.7.7.2)
Upstream: 56e2ba5e
Install method: git
Python: 3.11.15
OpenAI SDK: 2.24.0
```

`HermesDiscovery` implements only that foundation. It deliberately does not
advance to the SPK-01 process-supervision or protocol-client recommendations.

## Remaining Blocked Components

- `HermesProcessSupervisor`: Bridge-owned process launch, dedicated process
  group ownership, readiness, shutdown, and port cleanup.
- `HermesProtocolClient`: versioned protocol negotiation and capability
  detection.
- Run submission, status, cancellation, approval handling, and authentication.

Those components remain blocked until their own issues and protocol evidence
authorize the work.
