# M2-003 Findings: Hermes Backend Protocol Contract

## Package Inspected

- Package: `hermes-agent`
- Version: `0.18.2`
- Build text: `Hermes Agent v0.18.2 (2026.7.7.2)`
- Upstream revision: `56e2ba5e`
- Install method: `git`
- Python: `3.11.15`
- OpenAI SDK: `2.24.0`

The executable was discovered from `PATH`, resolved through the installed
Hermes virtual environment, and tied back to the installed source root. Tracked
paths below use `<hermes-install>`.

## Source Evidence

### CLI And Package Metadata

- `<hermes-install>/pyproject.toml`: console script `hermes =
  "hermes_cli.main:main"`.
- `<hermes-install>/hermes_agent.egg-info/PKG-INFO`: package name
  `hermes-agent`, version `0.18.2`, and FastAPI/Uvicorn dependencies.
- `<hermes-install>/hermes_cli/subcommands/dashboard.py`: `serve` is a
  headless backend command sharing the dashboard server and described as the
  JSON-RPC/WebSocket gateway.

### Server Creation

- `<hermes-install>/hermes_cli/web_server.py`: `app = FastAPI(title="Hermes
  Agent", version=__version__, lifespan=_lifespan)`.
- Server framework: FastAPI/Starlette served by Uvicorn.

### Routes

- `<hermes-install>/hermes_cli/web_server.py`: `@app.get("/api/status")`,
  symbol `get_status`.
- `<hermes-install>/hermes_cli/web_server.py`: `@app.websocket("/api/ws")`,
  symbol `gateway_ws`.
- `<hermes-install>/hermes_cli/web_server.py`: `@app.websocket("/api/pub")`,
  symbol `pub_ws`.
- `<hermes-install>/hermes_cli/web_server.py`: `@app.websocket("/api/events")`,
  symbol `events_ws`.
- `<hermes-install>/hermes_cli/dashboard_auth/public_paths.py`:
  `PUBLIC_API_PATHS` includes `/api/status`.

### WebSocket And JSON-RPC

- `<hermes-install>/hermes_cli/web_server.py`: `gateway_ws` verifies auth and
  request origin/host, then delegates to `tui_gateway.ws.handle_ws`.
- `<hermes-install>/tui_gateway/ws.py`: `handle_ws` accepts the WebSocket,
  sends a `gateway.ready` event, parses inbound JSON, and dispatches through
  `tui_gateway.server.dispatch`.
- `<hermes-install>/tui_gateway/server.py`: `_ok`, `_err`,
  `_normalize_request`, `handle_request`, and `dispatch` implement JSON-RPC
  2.0 request/response handling.
- `<hermes-install>/apps/shared/src/json-rpc-gateway.ts` confirms the desktop
  client frame shape: `{ jsonrpc: "2.0", id, method, params }`, responses with
  `result` or `error`, and event notifications where `method === "event"`.

### Authentication

- `<hermes-install>/hermes_cli/web_server.py`: `_SESSION_TOKEN` is read from
  `HERMES_DASHBOARD_SESSION_TOKEN` or generated at process start.
- `<hermes-install>/hermes_cli/web_server.py`: `_SESSION_HEADER_NAME` is
  `X-Hermes-Session-Token` for HTTP API calls.
- `<hermes-install>/hermes_cli/web_server.py`: `_ws_auth_reason` accepts
  `?token=<_SESSION_TOKEN>` for loopback/non-gated mode.
- `<hermes-install>/hermes_cli/dashboard_auth/ws_tickets.py`: gated mode uses
  single-use `?ticket=` values minted by `POST /api/auth/ws-ticket`; internal
  server-spawned WebSocket clients can use `?internal=`.
- `<hermes-install>/apps/desktop/electron/connection-config.ts`: token mode
  WebSocket URLs are built as `/api/ws?token=...`; OAuth mode uses
  `/api/ws?ticket=...`.

### Version And Capability Discovery

- `<hermes-install>/hermes_cli/web_server.py`: `/api/status` returns `version`,
  `release_date`, `auth_required`, gateway state fields, and other bounded
  liveness data.
- `<hermes-install>/tui_gateway/server.py`: `DESKTOP_BACKEND_CONTRACT = 3`.
- `<hermes-install>/tui_gateway/server.py`: `desktop_contract` is returned from
  `session.create` and `session.info`.

### Run, Status, Cancellation, And Approval

- `<hermes-install>/tui_gateway/server.py`: `@method("session.create")`
  returns `session_id`, `stored_session_id`, `message_count`, `messages`, and
  `info`.
- `<hermes-install>/tui_gateway/server.py`: `@method("prompt.submit")` accepts
  `session_id` and `text` and returns `{"status": "streaming"}` after queuing
  the run thread. The spike did not submit a prompt.
- `<hermes-install>/tui_gateway/server.py`: `@method("session.status")`
  returns a textual `output` status summary.
- `<hermes-install>/tui_gateway/server.py`: `@method("session.interrupt")`
  cooperatively interrupts the active turn and returns
  `{"status": "interrupted"}`.
- `<hermes-install>/tui_gateway/server.py`: `_emit_approval_request` emits
  `approval.request`; `@method("approval.respond")` resolves with a `resolved`
  field.

## Active Evidence

The script launches:

```text
hermes --safe-mode serve --host 127.0.0.1 --port 19121 --skip-build --isolated
```

with `HOME`, `HERMES_HOME`, and XDG roots under `artifacts/m2-003/active-root`.

Source-proven probes only:

- `GET /api/status`
- WebSocket upgrade attempt to `/api/ws` without credentials

The active probe captures status code, bounded response shape, content type,
and WebSocket unauthenticated rejection evidence under `artifacts/m2-003/`.
It then stops only the exact recorded child PID and checks for port/process
residue.

## Required Questions

1. Transport protocol: confirmed. FastAPI HTTP plus JSON-RPC 2.0 over
   WebSocket `/api/ws`.
2. Base URL or connection address: confirmed. Loopback base URL
   `http://127.0.0.1:<port>` from the Bridge-owned process launch; WebSocket
   `ws://127.0.0.1:<port>/api/ws?...`.
3. Health/readiness contract: confirmed. Process readiness is
   `HERMES_BACKEND_READY port=<port>`; HTTP liveness is public
   `GET /api/status`.
4. Protocol or backend version discovery: confirmed. `/api/status.version` and
   JSON-RPC `desktop_contract`.
5. Authentication requirement: confirmed. Loopback WebSocket uses `?token=`;
   HTTP API uses `X-Hermes-Session-Token` except public paths; gated mode uses
   ws tickets.
6. Capability discovery: partially confirmed. `desktop_contract` is confirmed,
   but no exhaustive capability endpoint was found.
7. Run submission request schema: confirmed by source. JSON-RPC
   `prompt.submit` with `session_id` and `text`.
8. Run identifier schema: confirmed. `session.create` returns `session_id` and
   `stored_session_id`.
9. Run status schema: partially confirmed. `session.status` returns textual
   `output`; structured run state is not confirmed.
10. Event or streaming mechanism: confirmed. JSON-RPC `event` notifications on
   `/api/ws`; sidecar WebSockets `/api/pub` and `/api/events` are also present.
11. Cancellation method: confirmed. JSON-RPC `session.interrupt`.
12. Approval request/response mechanism: confirmed. `approval.request` event
   and JSON-RPC `approval.respond`.
13. Error envelope: confirmed. JSON-RPC `error` object with `code` and
   `message`.
14. Reconnection and resume behavior: partially confirmed. Client code has
   reconnect handling and server has session resume methods, but no complete
   Bridge contract is established here.
15. Compatibility/versioning strategy: partially confirmed. Monotonic
   `DESKTOP_BACKEND_CONTRACT = 3` is confirmed; broader compatibility policy is
   not found.

## Confirmed Protocol Operations

- Process readiness via stdout/stderr marker.
- Public HTTP status/version/auth-mode discovery via `/api/status`.
- Authenticated JSON-RPC WebSocket connection to `/api/ws`.
- Initial `gateway.ready` event.
- `session.create`.
- `prompt.submit` source schema and streaming-start response.
- `session.status` textual status.
- Event notifications.
- `session.interrupt`.
- `approval.request` and `approval.respond`.

## Blocked Or Limited Areas

- No active prompt submission was performed.
- No generic REST run, status, stream, cancel, or approval endpoint exists in
  the inspected source.
- No SSE run-event contract was found.
- No exhaustive capability endpoint was found.
- Reconnection and resume are not fully specified as a Bridge contract.
- Structured run state beyond textual `session.status.output` is not
  confirmed.

## Security Implications

A Bridge-managed client can avoid credential discovery by generating a
Bridge-owned random session token and launching Hermes with
`HERMES_DASHBOARD_SESSION_TOKEN` set in the child environment. The client then
uses:

- `GET /api/status` without credentials for liveness and auth-mode discovery.
- `ws://127.0.0.1:<port>/api/ws?token=<bridge-owned-token>` for JSON-RPC.

The Bridge must not expose a generic REST client, guessed endpoint probing, or
browser/dashboard automation.

## Decision

M2-003 VERDICT: GO

The installed package source establishes a stable enough narrow contract to
implement `HermesProtocolClient` for status discovery and authenticated
JSON-RPC over `/api/ws`.

Allowed next scope:

- status/version/auth-mode discovery;
- WebSocket JSON-RPC connection with a Bridge-owned launch token;
- event dispatch;
- session creation/status;
- prompt submission model wiring under a separately authorized product issue;
- cooperative interrupt;
- approval request/response handling.

Disallowed next scope:

- guessed REST endpoints;
- generic endpoint scanner;
- arbitrary command or browser automation;
- active user prompt testing in this spike.
