# SPK-01 Findings: Managed Hermes Gateway

## Confirmed Facts

1. `hermes` is discoverable on `PATH` at `<hermes-binary>`.
2. The discovered path resolves to the installed Hermes Agent virtual
   environment binary. The private absolute path is intentionally omitted.
3. `hermes --version` reports `Hermes Agent v0.18.2 (2026.7.7.2)`,
   upstream `56e2ba5e`, install method `git`, Python `3.11.15`, and OpenAI
   SDK `2.24.0`.
4. `hermes --help` confirms global overrides for model, provider, toolsets,
   resume, worktree isolation, user config suppression, rules suppression,
   safe mode, TUI/CLI selection, and development mode.
5. `hermes --help` confirms `--ignore-user-config` and `--safe-mode`.
   `--safe-mode` disables user config, rule injection, plugins, and MCP
   servers according to help text.
6. `hermes serve --help` confirms a headless backend command described as a
   JSON-RPC/WebSocket gateway.
7. `hermes serve --help` confirms `--host`, `--port`, `--skip-build`,
   `--isolated`, `--stop`, and `--status`.
8. The default `serve` host is `127.0.0.1`; the default port is `9119`; port
   `0` requests OS auto-assignment.
9. `hermes serve --help` states `--insecure` is deprecated/no-op and no longer
   disables authentication for public binds.
10. `hermes dashboard --help` exposes the same host, port, skip-build,
    isolated, stop, and status flags and adds `--no-open`.
11. `hermes profile --help` confirms profile commands: `list`, `use`,
    `create`, `delete`, `describe`, `show`, `alias`, `rename`, `export`,
    `import`, `install`, `update`, and `info`.
12. `hermes profile use --help` confirms that `profile use` sets a sticky
    default profile.
13. `hermes gateway --help` is for messaging gateway management, not the
    headless backend server described by `serve`.
14. `hermes gateway run --help` warns that a second foreground dispatcher can
    corrupt shared gateway state unless forced. That command is not a safe
    default candidate for Bridge management.
15. The active-test script now uses an evidence-first sequence. It launches
    only `hermes --safe-mode serve --host 127.0.0.1 --port 19119 --skip-build
    --isolated` with `HOME`, `HERMES_HOME`, `XDG_CONFIG_HOME`,
    `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, and
    `XDG_RUNTIME_DIR` under `<repo>/artifacts/spk-01/`.
16. The active-test script performs only protocol-neutral probes until runtime
    evidence identifies a more specific surface: TCP connect, HTTP `GET /`,
    and a WebSocket upgrade handshake against `/`.
17. The active-test script creates each isolated root with `0700`
    permissions, logs the paths passed to the child, and records filesystem
    evidence only under the spike-owned `active-root`.
18. The active-test script records child PID identity evidence using PID,
    process start time, and command, and verifies that identity before any
    signal is sent.
19. Normal shutdown is enforcing. The script fails active testing if the exact
    recorded child PID remains alive after the `SIGTERM` timeout, does not
    clear `HERMES_PID` while that PID remains alive, and leaves the cleanup
    trap able to retry.
20. Cleanup may escalate to `SIGKILL` only for the exact verified
    spike-owned process. The script still never uses `killall` or `pkill`.
21. After shutdown, the script records any listener still bound to
    `127.0.0.1:19119` and any process command that references the isolated
    active-root path. It reports those survivors without terminating them
    broadly.
22. Normal shutdown active testing passed with exact owned PID `24840`.
    Hermes emitted `HERMES_BACKEND_READY port=19119`, listened only on
    `127.0.0.1:19119`, accepted a TCP connection, returned
    `HTTP/1.1 404 Not Found` for `GET /` from uvicorn, exited after `SIGTERM`
    sent only to the verified owned PID, closed port `19119`, and left no
    `hermes serve` process running.
23. Abnormal shutdown active testing passed with exact owned PID `27319` and
    test exit code `0`. Hermes emitted `HERMES_BACKEND_READY port=19119`,
    listened only on `127.0.0.1:19119`, accepted a TCP connection, returned
    `HTTP/1.1 404 Not Found` for `GET /`, exited after `SIGKILL` sent only to
    the verified owned PID, closed port `19119`, and left no `hermes serve`
    process running.
24. Runtime isolation was observed for the active tests: `HOME`,
    `HERMES_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`,
    `XDG_STATE_HOME`, and `XDG_RUNTIME_DIR` were redirected under
    `<repo>/artifacts/spk-01/active-root`; Hermes wrote runtime state under
    `<isolated-hermes-home>`; no writes to the real user Hermes home were
    intentionally performed; and `artifacts/` is ignored by Git.

## Failed Assumptions

1. The issue title says "Gateway", but the CLI evidence separates messaging
   gateway management (`hermes gateway`) from the headless JSON-RPC/WebSocket
   backend (`hermes serve`).
2. The available help does not support assuming an HTTP REST runs API.
3. The available help does not support assuming health, readiness,
   capabilities, run creation, run status, event streaming, cancellation, or
   approval endpoints.
4. The available help does not prove configuration precedence across command
   line arguments, environment variables, profile configuration, user config,
   and defaults.
5. REST endpoint names remain unconfirmed. Active testing must not probe
   guessed paths such as `/health`, `/ready`, `/readiness`, `/capabilities`,
   `/api/runs`, or `/runs` unless stdout/stderr, an introspection response, or
   upstream documentation first identifies the path.

## Unsupported Or Ambiguous Capabilities

- Health endpoint: unsupported by read-only evidence.
- Detailed readiness endpoint: unsupported by read-only evidence.
- Capabilities endpoint: unsupported by read-only evidence.
- Run creation: unsupported by read-only evidence.
- Run status: unsupported by read-only evidence.
- Event streaming or SSE: unsupported by read-only evidence.
- Run stop/cancel: unsupported by read-only evidence.
- Approval support over the backend protocol: unsupported by read-only
  evidence.
- API key or token configuration for `serve`: ambiguous from help.
- Profile selection for `serve`: ambiguous. `--isolated` references named
  profiles, but the help inspected here does not show a direct `--profile`
  flag for `serve`.
- Configuration precedence: partially evidenced for top-level model/provider
  and safe-mode flags, but not validated for backend host, port,
  authentication, or profiles.

## Security Implications

The safest candidate launch mode is a Bridge-owned child process using:

```text
hermes --safe-mode serve --host 127.0.0.1 --port <bridge-selected-port> --skip-build --isolated
```

This shape keeps the server on loopback, suppresses user configuration,
suppresses rule injection, and avoids plugin/MCP loading according to help
text. Active testing is still required to prove whether this prevents writes to
the user's existing Hermes configuration.

The Bridge must not call `hermes gateway run` by default. Its help text warns
about corrupting shared gateway state when more than one dispatcher is active.

The Bridge must not rely on `--insecure`; help says it is a no-op and public
binds require authentication.

The Bridge should treat API keys, tokens, and auth configuration as
unvalidated. No spike command should print credentials, read Keychain, or read
`~/.hermes` directly. The spike script uses a defensive redactor for common
credential forms, including key/token/secret assignments, JSON credential
fields, Authorization Bearer/Basic, Cookie and Set-Cookie, X-API-Key, sensitive
URL query parameters, and command argument values such as `--api-key` or
`--token`. This is a diagnostic safety layer, not a reason to intentionally
emit secrets.

Active spike evidence must stay inside `artifacts/spk-01/`. Filesystem
evidence is limited to path, type, size, and timestamps for the spike-owned
HOME, `HERMES_HOME`, and XDG roots, including `XDG_STATE_HOME` and
`XDG_RUNTIME_DIR`. The spike must not inspect, hash, stat, list, or read the
user's real `~/.hermes`.

## Process-Lifecycle Implications

A future adapter should:

1. Discover an allowlisted Hermes binary path and record resolved symlink
   metadata.
2. Run `hermes --version` and parse the version/build metadata before launch.
3. Launch only a direct child process.
4. Bind only to `127.0.0.1` unless a later ADR explicitly permits otherwise.
5. Select a Bridge-owned port or use port `0` only if stdout/stderr exposes
   the assigned port reliably.
6. Use a Bridge-owned temporary home/config root if active testing proves
   Hermes honors it.
7. Track only the child PID returned by process creation and capture launch
   identity evidence such as process start time and command.
8. Before signaling, verify that the recorded PID still represents the
   process started by the Bridge. Refuse to signal on identity mismatch.
9. Terminate only that PID and its Bridge-owned process group if one is
   created by the Bridge.
10. Never use process-name termination such as `killall hermes` or
   `pkill hermes`.
11. Probe readiness through a versioned protocol handshake, not by assuming a
    path exists.
12. Treat process descendants as observation data unless they are explicitly
    created and owned by the Bridge. Report unexpected descendants rather than
    terminating by process name.
13. Keep abnormal termination tests scoped to `SIGKILL` against the exact
    spike-owned PID and verify both PID exit and port closure afterward.
14. Treat port cleanup as enforcing. If the owned process exits but the
    expected fixed port remains open, fail and report listener evidence rather
    than reporting success.

## Recommended Hermes Adapter Shape

Use a small adapter boundary with three layers:

1. `HermesDiscovery`: binary discovery, resolved symlink metadata, version
   parsing, and command-surface validation.
2. `HermesProcessSupervisor`: child process launch, stdout/stderr capture,
   readiness timeout, normal shutdown, abnormal-exit observation, and port
   cleanup checks.
3. `HermesProtocolClient`: versioned protocol negotiation and explicit
   capability detection before any run operation is enabled.

The adapter should expose capabilities as optional feature flags. Product code
should not call run creation, cancellation, approval, or event streaming until
the protocol client has confirmed those surfaces at runtime.

The first protocol probe should be conservative: observe startup logs, perform
only protocol-neutral checks, and advance to any named REST, JSON-RPC, or
WebSocket method only after Hermes itself exposes that surface through output,
introspection, or documentation.

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

## ADR Recommendations

ADR-0003 for an HTTP runs API should not be created because that API is
unconfirmed. `GET /` returning `404 Not Found` proves an HTTP/uvicorn server
exists, but it does not prove a REST run API.

A future process-lifecycle ADR is recommended based on the confirmed process
supervision, loopback binding, readiness, shutdown, port cleanup, and isolated
environment-root evidence.

Speculative protocol documentation should not be created.

## P0 Blockers

1. No confirmed run creation API.
2. No confirmed run status API.
3. No confirmed stop/cancel API.
4. No confirmed approval protocol.
5. No confirmed readiness or capability endpoint.
6. No confirmed authentication model for the headless backend.
7. No confirmed profile selection mechanism for a Bridge-managed `serve`
   process.
8. No confirmed production authentication model.

## May M2 Runtime Foundation Proceed?

M2 Runtime Foundation may proceed for a narrow `HermesProcessSupervisor` and
`HermesDiscovery` implementation.

`HermesProtocolClient` and user-facing run execution must remain blocked until
a separate protocol/API spike resolves the backend contract.
