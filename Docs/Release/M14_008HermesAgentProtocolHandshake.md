# M14-008 Hermes Agent Protocol Handshake

## Objective

M14-008 validates the Hermes Agent 0.18.2 request, cancel, approval, terminal
state, and reconnect handshake using one supervised isolated Agent. It classifies
each protocol area as supported and exercised, supported but not safely
exercisable, unsupported, blocked, or protocol incompatible.

## Dependency on M14-007

This milestone depends on the M14-007 ownership model:

- launch exactly one `hermes serve --isolated --port 0` process;
- discover only the listener owned by the exact supervised root PID;
- prove readiness through Hermes-specific `GET /api/status` evidence;
- match service-owned discovery to the isolated endpoint;
- shut down by exact root PID only.

No broad stop, broad process kill, process-group signaling, or real-home access
is allowed.

## Protocol Discovery

Discovery is bounded to:

- `hermes --version` and `hermes serve --help`;
- `GET /api/status`;
- `GET /openapi.json` when present;
- the production local `HermesProtocolClient` JSON-RPC contract.

The committed descriptor is sanitized and records route categories only. Raw
OpenAPI content, dynamic ports, URLs, tokens, profile data, request IDs, and
absolute user paths are not written to deterministic `result.txt`.

## Authentication

Hermes 0.18.2 advertises loopback token authentication through status metadata.
When the acceptance run needs a credential, it generates an acceptance-owned
ephemeral token under `artifacts/m14-008/runtime`, redacts it from reports, and
removes it during cleanup. The script does not read `~/.hermes`, Keychain, or
unrelated environment values.

## Request Identity and State

The production request family is the JSON-RPC/WebSocket session contract:

- request submission category: `session.create`;
- request identity: returned `session_id`;
- status observation category: `session.status`;
- state mapping: queued, running, awaiting-approval, cancelling, cancelled,
  completed, failed, or unknown.

The safe synthetic request is session creation only. It does not submit an
arbitrary prompt or invoke tools.

## Cancellation

Cancellation maps to the documented production client method
`session.interrupt`. The acceptance run targets only the exact captured
acceptance request identity. If the session completes too quickly to prove
deterministic cancellation, the result must remain `supported-unexercised`
instead of forcing a race.

## Approvals

The protocol supports `approval.respond`, but M14-008 does not approve real
Agent actions unless a harmless synthetic approval fixture is available entirely
inside the isolated Agent. Without such a fixture, approval is reported as
supported but not safely exercisable.

Never approve shell execution, filesystem changes, credential access, external
network actions, account changes, destructive operations, GUI automation, or
system settings changes.

## Reconnect

After request creation or stable status observation, the Bridge-owned protocol
client is disposed. A new service-owned client connects to the same
ownership-proven endpoint and queries the exact request identity. The Agent is
not restarted for this check.

## Safety Constraints

M14-008 does not add a UI Center and does not change the XPC protocol version.
The UI must not construct Agent URLs, payloads, or Agent protocol clients. The
service layer owns protocol discovery, the request client, state tracking,
cancellation, and approval capability handling.

## Result Interpretation

- `PASS`: metadata, safe request identity/status, supported optional checks or
  safe unsupported classification, reconnect continuity, exact cleanup, and no
  real-home access all pass.
- `PARTIAL`: request/status works but optional cancel, approval, or reconnect
  cannot be exercised safely.
- `UNSUPPORTED`: Hermes exposes no safe request contract after metadata
  discovery.
- `BLOCKED`: metadata cannot be legally inspected, authentication cannot be
  isolated, or a required platform facility is unavailable.
- `FAIL`: malformed or spoofed response, identity mismatch, wrong cancellation,
  unsafe approval, secret leakage, cleanup failure, real-home access, or broad
  operation use.

## Operator Commands

Read-only local inspection:

```sh
Scripts/m14_008_agent_protocol_handshake_acceptance.sh inspect
```

Opt-in acceptance run:

```sh
HERMES_M14_008_ACCEPTANCE=YES Scripts/m14_008_agent_protocol_handshake_acceptance.sh run
```

Exact-identity cleanup:

```sh
Scripts/m14_008_agent_protocol_handshake_acceptance.sh cleanup
```

Validation:

```sh
swift build
swift test
swift test --filter HermesAgentProtocolDescriptorTests
swift test --filter HermesAgentRequestClientTests
swift test --filter HermesAgentProtocolHandshakeAcceptanceTests
zsh -n Scripts/m14_008_agent_protocol_handshake_acceptance.sh
```

## Limitations

The acceptance script does not crawl endpoints, does not query existing real
Hermes Agent instances, and does not use route names based only on guesses.
Approval remains unexercised unless Hermes exposes a harmless synthetic approval
fixture. The deterministic result file intentionally omits raw request IDs,
ports, URLs, tokens, paths, payloads, and profile data.
