# HermesRequestOrchestrator Runtime Foundation

## Component Responsibility

`HermesRequestOrchestrator` is the narrow coordination layer for Bridge-owned
Hermes requests. It connects the allowlisted request binding model,
`HermesRequestStateStore`, `HermesProcessSupervisor`, and `HermesProtocolClient`
without exposing generic command execution, arbitrary JSON-RPC methods,
caller-selected endpoints, caller-selected tokens, or caller-selected process
arguments.

The orchestrator does not implement UI, App Intents, LaunchAgent installation,
XPC transport, generic persistence, generic process management, browser
automation, GUI computer use, Shortcuts execution, or result-body storage.

## Submission Sequence

Submission is serialized through the orchestrator actor:

1. Validate the binding ID against an injected allowlisted binding registry.
2. Validate the prompt against the binding's maximum prompt byte length.
3. Generate a `HermesRequestID`.
4. Persist an accepted request record.
5. Transition the record to `queued`.
6. Ensure a Bridge-owned backend is ready:
   - reuse an already ready backend when possible;
   - otherwise launch through `HermesProcessSupervisor`;
   - obtain the fixed loopback endpoint and Bridge-owned session token;
   - create a typed `HermesProtocolClient`;
   - wait for confirmed `gateway.ready`.
7. Transition the request to `starting`.
8. Create a backend session with the typed `session.create` operation.
9. Attach the backend session ID and process launch UUID to the request record.
10. Submit the transient bounded prompt with the typed `prompt.submit` operation.
11. Transition the request to `running`.

The prompt is held only in memory for the active submission. It is never stored
in `HermesRequestStateStore`, public descriptions, typed errors, or failure
metadata.

## Lifecycle State Mapping

The orchestrator uses the request store lifecycle states as follows:

- `accepted`: durable request ID exists.
- `queued`: request accepted for orchestration, but backend work has not started.
- `starting`: backend is ready and a backend session is being prepared.
- `running`: prompt was submitted exactly once for the request.
- `waitingForApproval`: confirmed backend approval event matched the request's
  backend session.
- `cancelling`: cancellation was requested and backend interruption may be in
  progress.
- `cancelled`: cancellation completed or was completed before backend work was
  submitted.
- `interrupted`: restart or backend disconnect prevented confirmed continuation.
- `failed`: launch, connection, session creation, prompt submission, state
  store, or internal orchestration failure was recorded with redacted metadata.
- `completed`: reserved for later result handling once completion events and
  result policy are implemented.

## Binding Allowlist

`HermesRequestBinding` is a versioned allowlist entry. It includes the binding
ID, enabled flag, maximum prompt bytes, and typed policy placeholders for
timeout, approval, and result behavior.

Callers may choose only an allowlisted binding ID and prompt text. They cannot
choose an executable path, JSON-RPC method, endpoint, token, environment,
process arguments, Shortcut name, or persistence path.

## Backend Reuse

The orchestrator reuses an existing ready supervisor and ready protocol service
when available. Otherwise it launches the fixed Bridge-owned Hermes backend
through `HermesProcessSupervisor` and builds a typed protocol service from the
returned `HermesBackendLaunchContext`.

Backend reuse does not weaken the process or protocol boundary: endpoint and
token still come from Bridge-owned launch configuration or launch context.

## Approval Handling

The orchestrator consumes only typed `HermesGatewayEvent` values. When an
`approval.request` event includes a backend session ID that maps to a known
running request, the request transitions to `waitingForApproval`.

The approval prompt body and backend approval metadata are not persisted by the
orchestrator. The orchestrator never automatically approves. Callers must use
the explicit typed `respondToApproval(requestID:decision:)` operation, which
supports only confirmed `approve` or `reject` decisions and calls the typed
`approval.respond` protocol method.

## Cancellation Behavior

Cancellation is cooperative and request-scoped:

- `accepted` or `queued`: mark cancellation requested and transition to
  `cancelled` without submitting backend work.
- `starting`: mark cancellation requested; if a backend session has already
  been attached, call typed `session.interrupt`, otherwise cancel locally.
- `running` or `waitingForApproval`: transition to `cancelling`, call typed
  `session.interrupt`, then mark `cancelled` when the backend confirms an
  interrupted or cancelled response.
- terminal states: repeated cancellation is idempotent.

The orchestrator never kills arbitrary processes as a request-cancellation
shortcut. Process shutdown remains owned by `HermesProcessSupervisor`.

## Restart Reconciliation

Restart recovery uses `HermesRequestStateStore` recovery classifications:

- `accepted` and `queued` records are marked `interrupted`. They are not
  replayed because prompt bodies are intentionally not persisted.
- `starting` records are reconciled against `HermesProcessSupervisor` launch
  identity. If the launch identity is absent or mismatched, the request is
  marked `interrupted`; otherwise explicit reconciliation remains required.
- `running`, `waitingForApproval`, and `cancelling` records with backend session
  IDs are reconciled through typed `session.status`. If the session cannot be
  confirmed, the request is marked `interrupted`.
- terminal records require no action.

The no-prompt-persistence rule means a restarted Bridge cannot automatically
resubmit prompts for accepted or queued records. A future XPC/App Intent layer
must present this as an interrupted request requiring user-visible follow-up,
not as transparent replay.

## Dependency Boundaries

The orchestrator depends on narrow protocols:

- `HermesRequestBindingRegistry` for allowlisted bindings.
- `HermesRequestStateStore` for durable typed request records.
- `HermesProcessSupervising` for fixed backend lifecycle operations.
- `HermesProtocolServicing` for confirmed typed protocol methods and events.
- `HermesProtocolServiceFactory` for constructing the typed protocol client
  from a Bridge-owned launch context.

These protocols do not expose generic process runners, generic JSON-RPC send
methods, arbitrary endpoints, arbitrary environment injection, or generic
persistence.

## Security Boundary

The orchestrator preserves the product security boundary:

- no arbitrary shell execution;
- no arbitrary executable path selection;
- no arbitrary AppleScript or JXA execution;
- no browser automation;
- no GUI computer use;
- no unauthenticated remote control API;
- no prompt persistence;
- no token persistence;
- no private backend output in public errors or failure metadata;
- no automatic prompt replay after restart.

## Remaining Work

XPC and App Intents remain outside this component. Future issues must add:

- an XPC transport that exposes only request submission, status, cancellation,
  and explicit approval decisions;
- App Intent/Siri handoff that returns accepted request IDs quickly;
- user-facing interruption and reconciliation presentation;
- completion/result event handling and result availability policy;
- audit integration using only redacted lifecycle metadata.
