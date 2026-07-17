# SPK-06 Findings

## Verdict

`SPK-06 VERDICT: CONDITIONAL GO`

The installed Xcode/macOS SDK can compile AppIntents code, and the active
prototype proves the selected immediate handoff pattern. Real Siri/Shortcuts/App
Intent runtime behavior remains unproven until a signed installed app is tested.

## Read-Only Compile Evidence

Command:

```sh
Scripts/spikes/spk-06-long-running-app-intents.zsh
```

Machine-readable result:

```text
SPK06_READ_ONLY_RESULT=PASS
APPINTENTS_FRAMEWORK_AVAILABLE=yes
APPINTENT_COMPILE_AVAILABLE=yes
APPSHORTCUTS_PROVIDER_COMPILE_AVAILABLE=yes
XCODE_AVAILABLE=yes
```

Environment captured in `artifacts/spk-06/read-only/environment.txt`:

- macOS: `27.0`
- architecture: `arm64`
- Xcode: `27.0`, build `27A5218g`
- Swift: `Apple Swift version 6.4`
- SDK: `MacOSX27.0.sdk`
- deployment target used by probes: `macOS 13.0`

Compile probes:

- `minimal-appintent`: yes, `async perform() throws -> some IntentResult`
  compiled.
- `appshortcuts-provider`: yes, `AppShortcutsProvider` and `AppShortcut`
  compiled.
- `appintent-api-surface`: yes, `IntentResult`, dialog output,
  `openAppWhenRun`, and parameter summary compiled.
- `foreground-continuation`: yes, `continueInForeground` compiled when guarded
  for macOS 26.0+.
- `cancellation-signal`: yes, `CancellableIntent` and
  `withIntentCancellationHandler` compiled when guarded for macOS 26.4+.
- `progress-and-long-running-intent`: yes, `ProgressReportingIntent` compiled
  for macOS 14.0+ and `LongRunningIntent.performBackgroundTask` compiled for
  macOS 27.0+.

SDK interface evidence in `appintents-interface-symbols.txt` found:

- `protocol AppIntent`
- `protocol IntentResult`
- `struct IntentDialog`
- `openAppWhenRun`
- `continueInForeground`
- `requestToContinueInForeground`
- `protocol CancellableIntent`
- `IntentCancellationReason`
- `ParameterSummary`
- `protocol AppShortcutsProvider`
- `ProgressReportingIntent`
- `LongRunningIntent`

Local Xcode documentation search did not find AppIntents documentation cache
hits. `codesign`, `simctl`, and `devicectl` were available.

## Active Runtime Evidence

Command:

```sh
Scripts/spikes/spk-06-long-running-app-intents.zsh --active-test
```

Machine-readable result:

```text
SPK06_ACTIVE_RESULT=PASS
IMMEDIATE_HANDOFF_AVAILABLE=yes
REQUEST_ID_AVAILABLE=yes
STATUS_QUERY_AVAILABLE=yes
COMPLETION_RESULT_AVAILABLE=yes
CANCELLATION_AVAILABLE=yes
INVALID_BINDING_REJECTED=yes
WORKER_RESTART_RECOVERY=yes
REAL_APP_INTENT_RUNTIME_PROVEN=no
SPK06_SELECTED_HANDOFF_MODEL=app-intent-validates-and-enqueues-to-bridge-xpc
RESIDUAL_WORKER_PROCESS=no
```

This is prototype evidence only. It proves the architecture of a typed handoff
to an independent worker, not actual Siri, Shortcuts, or installed App Intent
runtime execution.

## Scenario Results

Scenario A, immediate handoff:

- Submit returned `ACCEPTED <request-id>`.
- Acceptance latency was `5 ms`.
- Initial state was `queued`.
- One second later the worker reported `running`, proving the entry point
  returned before the job completed and the worker continued independently.

Scenario B, completion:

- Status query returned a typed lifecycle state.
- Final state was `completed`.
- Fixed non-secret result was `SPK06_FIXED_RESULT`.

Scenario C, cancellation:

- A longer job accepted a request ID.
- First cancellation returned `CANCELLED <request-id>`.
- Repeated cancellation returned `CANCELLED <request-id>`.
- Final state was `cancelled`.

Scenario D, invalid binding/request:

- Unknown binding was rejected.
- Unknown request ID was rejected.
- Extra submit argument representing an arbitrary operation/command shape was
  rejected.
- The prototype accepts no arbitrary prompt, command, executable path, or
  Shortcut name.

Scenario E, process interruption:

- The artifact-owned worker was terminated while a job was running.
- State persisted under `artifacts/spk-06/active/state`.
- Restarting the artifact-owned worker recovered the inflight request and
  completed it.
- Production still requires Bridge-owned XPC/LaunchAgent ownership because an
  App Intent or app process is not the correct owner for long-running work.

## Validation Questions

1. The installed Xcode and SDK can compile AppIntents code.
2. API availability:
   - async `perform()`: compile-proven.
   - `IntentResult`: compile-proven.
   - dialog output: compile-proven through `ProvidesDialog` and
     `IntentDialog`.
   - progress reporting: compile-proven through `ProgressReportingIntent`
     on macOS 14.0+; `LongRunningIntent` exists on this SDK for macOS 27.0+.
   - opening the app: compile-proven through `openAppWhenRun`.
   - foreground continuation: interface and compile-proven for macOS 26.0+.
   - cancellation: interface and compile-proven for macOS 26.4+.
   - parameter summaries: compile-proven.
   - `AppShortcutsProvider`: compile-proven.
3. A realistic App Intent should not hold the full Hermes run. The prototype
   supports an immediate accepted/run-ID response; real duration limits still
   require a signed installed app runtime test.
4. App Intents should enqueue through Bridge XPC, not execute Hermes work
   directly.
5. Yes. The active prototype safely returned `ACCEPTED <request-id>` immediately
   after validation and durable request creation.
6. Long-running status/result retrieval should be separate typed operations by
   request ID.
7. Cancellation should be a separate typed operation by request ID. The Bridge
   should translate cancellation to the Bridge-owned worker/Hermes lifecycle and
   make repeated cancellation idempotent.
8. Prototype worker termination/restart recovered an inflight request. Actual
   app suspension or termination behavior was not proven; production needs
   LaunchAgent/XPC ownership so work survives App Intent/app lifecycle changes.
9. Real Siri/Shortcuts runtime requires a signed app bundle, installed app,
   App Shortcuts/Siri registration, and user interaction/authorization where
   macOS requires it.
10. The security boundary is versioned policy plus typed IPC: allowlisted
    binding IDs, fixed operations, bounded structured parameters, no arbitrary
    prompt/command/executable/Shortcut input, Bridge-owned lifecycle, and
    redacted audit events.

## Selected Model

`app-intent-validates-and-enqueues-to-bridge-xpc`

The App Intent validates and creates a request. The Bridge accepts a versioned
request over XPC, returns a request ID immediately, owns the long-running Hermes
worker, exposes typed status/result/cancel operations, and emits redacted audit
events.

## Remaining Blockers

- Build a minimal signed macOS app bundle with real App Intents.
- Register App Shortcuts/Siri phrases without affecting existing user
  shortcuts.
- Measure real App Intent/Siri/Shortcuts execution duration and timeout
  behavior.
- Validate actual app suspension/termination behavior with Bridge XPC ownership.
- Decide production deployment target given foreground/cancellation APIs are
  newer than the baseline AppIntents availability.
