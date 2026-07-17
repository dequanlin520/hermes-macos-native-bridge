# SPK-01: Managed Hermes Gateway Validation

## Status

Technical spike for GitHub Issue #3. This is not product implementation.

GitHub issue details were not available through `gh issue view 3` in this
environment because the GitHub API connection failed. The local task brief in
`Docs/CodexTasks/SPK-01.md` was used as the issue source.

## Validation Question

Can a future macOS Bridge Agent safely manage the locally installed Hermes
Agent as an isolated child process without modifying the user's existing Hermes
configuration?

## Scope Boundaries

This spike does not add Bridge runtime behavior, Swift code, macOS integration
code, arbitrary execution paths, browser automation, GUI computer use, or a
remote control API.

The spike script is read-only by default. Active process tests require
`--active-test` and write temporary files only under
`<repo>/artifacts/spk-01/`, which is ignored by git.

## Deliverables

- `Spikes/SPK-01-managed-gateway/README.md`
- `Spikes/SPK-01-managed-gateway/FINDINGS.md`
- `Scripts/spikes/spk-01-managed-gateway.zsh`

`Docs/ADR/ADR-0003-hermes-http-runs-api.md` was intentionally not created.
The current evidence confirms a managed `hermes serve` process, loopback
listener, uvicorn HTTP server, and `HERMES_BACKEND_READY` startup signal. It
does not confirm an HTTP runs API contract.

## How to Run

Read-only inspection:

```zsh
Scripts/spikes/spk-01-managed-gateway.zsh
```

Syntax validation:

```zsh
zsh -n Scripts/spikes/spk-01-managed-gateway.zsh
```

Optional active server probe:

```zsh
Scripts/spikes/spk-01-managed-gateway.zsh --active-test
```

Optional abnormal termination probe for only the spike-owned child process:

```zsh
Scripts/spikes/spk-01-managed-gateway.zsh --active-test --abnormal-test
```

The script never uses `killall hermes` or `pkill hermes`. Cleanup tracks only
the PID started by the script and verifies the recorded PID identity before
signaling.

Active mode uses a fixed spike port, binds only to `127.0.0.1`, and launches
only:

```text
hermes --safe-mode serve --host 127.0.0.1 --port 19119 --skip-build --isolated
```

with `HOME`, `HERMES_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`,
`XDG_DATA_HOME`, `XDG_STATE_HOME`, and `XDG_RUNTIME_DIR` all redirected under
`<repo>/artifacts/spk-01/`.

Those spike-owned directories are created with restrictive `0700`
permissions, their paths are logged, and filesystem evidence is limited to the
`<repo>/artifacts/spk-01/active-root` tree. The active child receives every
isolated path explicitly in its environment.

Diagnostic output is passed through a defensive redactor before logging. The
redactor prefers over-redaction for common credential shapes, including
key/token/secret assignments, header forms such as Authorization, Cookie,
Set-Cookie, and X-API-Key, JSON credential fields, sensitive URL query
parameters, and command argument values such as `--api-key` or `--token`.

## Evidence-First Active Sequence

Active testing is intentionally protocol-neutral unless runtime output first
identifies a concrete path or protocol surface. The sequence is:

1. Stage A, process launch: start only `hermes serve`, record the exact command
   and the spike-owned PID, capture PID identity evidence using process start
   time and command, and record the isolated home/config/XDG tree before
   launch.
2. Stage B, runtime observation: capture stdout and stderr, record whether the
   child stays alive, inspect the listening socket with `lsof`, collect child
   process metadata with `ps`, and report descendants without terminating
   unrelated processes.
3. Stage C, protocol-neutral probes: perform only a TCP connect check, HTTP
   `GET /` with headers and a short timeout, and a WebSocket upgrade handshake
   against `/`.
4. Stage D, filesystem evidence: list only files under
   `<repo>/artifacts/spk-01/` with path, type, size, and timestamps. The script
   does not inspect, hash, stat, list, or read the user's real `~/.hermes`, and
   it does not read Keychain.
5. Stage E, shutdown: send `SIGTERM` in normal mode or `SIGKILL` in abnormal
   mode only to the exact spike-owned PID after matching the recorded launch
   identity, verify process exit, verify port closure, and report remaining
   descendants if any.

Normal shutdown is enforcing: if the exact child PID remains alive after the
`SIGTERM` timeout, the active test fails and keeps `HERMES_PID` set so the
`EXIT` trap can retry cleanup. The trap may escalate to `SIGKILL` only after
the same PID identity check succeeds. The script also fails if the fixed port
remains open after shutdown.

Post-shutdown survivor evidence reports any listener still bound to
`127.0.0.1:19119` and any process command that references the isolated
`active-root` path. It does not terminate such processes broadly.

The script does not actively probe speculative REST endpoints such as
`/health`, `/ready`, `/readiness`, `/capabilities`, `/api/runs`, or `/runs`
unless a future runtime observation or introspection response first provides
evidence that such a path exists.

## Confirmed Local Environment

Read-only inspection found:

- Hermes binary: `<hermes-binary>`
- Binary path resolves to the installed Hermes Agent virtual environment
  binary. The private absolute path is intentionally omitted.
- Version: `Hermes Agent v0.18.2 (2026.7.7.2)`
- Upstream: `56e2ba5e`
- Install method: `git`
- Python: `3.11.15`
- OpenAI SDK: `2.24.0`

## Confirmed Active Evidence

Normal shutdown passed:

- exact owned PID: `24840`
- Hermes emitted `HERMES_BACKEND_READY port=19119`
- listener was only on `127.0.0.1:19119`
- TCP connection succeeded
- `GET /` returned `HTTP/1.1 404 Not Found` from uvicorn
- `SIGTERM` was sent only to the verified owned PID
- the PID exited after `SIGTERM`
- port `19119` closed
- no `hermes serve` process remained

Abnormal shutdown passed:

- test exit code: `0`
- exact owned PID: `27319`
- Hermes emitted `HERMES_BACKEND_READY port=19119`
- listener was only on `127.0.0.1:19119`
- TCP connection succeeded
- `GET /` returned `HTTP/1.1 404 Not Found`
- `SIGKILL` was sent only to the verified owned PID
- the PID exited after `SIGKILL`
- port `19119` closed
- no `hermes serve` process remained

Runtime isolation was observed:

- `HOME`, `HERMES_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`,
  `XDG_DATA_HOME`, `XDG_STATE_HOME`, and `XDG_RUNTIME_DIR` were redirected
  under `<repo>/artifacts/spk-01/active-root`
- Hermes wrote runtime state under `<isolated-hermes-home>`
- no writes to the real user Hermes home were intentionally performed
- artifacts are ignored by Git

## Validation Summary

The installed CLI exposes a headless server command:

```text
hermes serve --host HOST --port PORT --skip-build --isolated
```

The help text describes this as the JSON-RPC/WebSocket gateway used by the
desktop app and remote clients. It confirms loopback host and explicit port
configuration. It does not confirm health, readiness, capabilities, HTTP run
creation, run status, SSE, cancellation, or approval endpoints.

REST endpoints remain unconfirmed. The spike must not treat any guessed HTTP
path as supported until Hermes runtime output, an introspection response, or
upstream documentation identifies that path.

The spike therefore recommends a narrow future adapter shape: a child-process
supervisor plus a versioned protocol probe layer. Product implementation should
not assume REST endpoints until active testing or upstream documentation
confirms them.

## Decision

SPK-01 VERDICT: CONDITIONAL GO

GO for:

- Hermes discovery;
- isolated child-process launch;
- loopback binding;
- startup readiness from `HERMES_BACKEND_READY`;
- exact-PID `SIGTERM` shutdown;
- exact-PID `SIGKILL` termination;
- port cleanup;
- narrow M2 process-supervision work.

NO-GO yet for:

- Hermes run submission;
- run status;
- event streaming;
- cancellation;
- approval handling;
- production authentication;
- assuming an HTTP REST runs API.

M2 Runtime Foundation may proceed for a narrow `HermesProcessSupervisor` and
`HermesDiscovery` implementation.

`HermesProtocolClient` and user-facing run execution must remain blocked until
a separate protocol/API spike resolves the backend contract.

## ADR Decision

Do not create ADR-0003 for an HTTP runs API because that API is unconfirmed.
`GET /` returning `404 Not Found` proves an HTTP/uvicorn server exists but does
not prove a REST run API.

A future process-lifecycle ADR is recommended based on the confirmed evidence.
Do not create speculative protocol documentation.
