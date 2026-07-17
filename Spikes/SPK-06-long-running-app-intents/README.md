# SPK-06 Long-Running App Intents

## Usage

Read-only mode:

```sh
Scripts/spikes/spk-06-long-running-app-intents.zsh
```

Active prototype mode:

```sh
Scripts/spikes/spk-06-long-running-app-intents.zsh --active-test
```

Both modes write generated sources, binaries, logs, and state under
`artifacts/spk-06/`. Nothing under `artifacts/` is intended to be committed.

## Prototype Architecture

The active prototype models the selected Bridge handoff without installing an
App Intent:

- typed request model with schema version, binding ID, fixed operation, request
  ID, and bounded delay parameter;
- mock AppIntent-like submit entry point that accepts only
  `spk06.approved.binding`;
- artifact-owned local worker that processes only the fixed
  `delayedFixedResult` operation;
- status client that queries by request ID;
- cancellation client that cancels by known request ID and is idempotent.

The prototype never accepts arbitrary prompts, shell commands, executable paths,
Shortcut names, or generic operation names.

## Lifecycle

Submit returns immediately:

```text
ACCEPTED <request-id>
```

Status returns typed state:

```text
STATUS <request-id> queued|running|completed|cancelled <detail> [result]
```

Cancel returns:

```text
CANCELLED <request-id>
```

Repeated cancellation returns the same typed cancellation acknowledgement. An
unknown request ID is rejected.

## Security Boundary

The App Intent layer should be a narrow policy and request creation boundary. It
must validate versioned binding policy, create a request ID, enqueue work through
Bridge-owned IPC, and return accepted immediately.

The Bridge owns long-running Hermes process lifecycle, request state, result
retrieval, cancellation propagation, and audit emission. App Intents must not
execute Hermes work directly and must not expose arbitrary commands, executable
paths, Shortcut names, shell fragments, or unbounded prompts.

## Selected Handoff Model

`app-intent-validates-and-enqueues-to-bridge-xpc`

The intended production path is:

1. App Intent validates an allowlisted binding and bounded structured
   parameters.
2. App Intent sends a versioned request to the Bridge over XPC.
3. Bridge returns accepted/request ID immediately.
4. Bridge-owned worker performs the Hermes run.
5. Separate typed operations provide status, result retrieval, and
   cancellation.

## Later Signed-App Validation

This spike did not prove actual Siri, Shortcuts, or App Intent runtime
execution. A later signed-app validation must install a signed macOS app bundle,
register App Shortcuts/Siri phrases, exercise invocation from Shortcuts and Siri,
measure real runtime duration limits, and test behavior when the app process is
suspended or terminated by the system.

`SPK-06 VERDICT: CONDITIONAL GO`
