# System Event Bridge

Hermes Bridge observes a narrow allowlist of public macOS system events and
publishes them through typed XPC subscriptions. The bridge does not expose raw
notification names, process identifiers, executable paths, window titles,
clipboard data, keystrokes, document titles, URLs, Prompts or backend tokens.

## Event Model

System events use:

- `HermesSystemEventID`
- `HermesSystemEventKind`
- `HermesSystemEventSource`
- `HermesSystemEvent`
- `HermesSystemEventBatch`
- `HermesSystemEventSubscriptionID`
- `HermesSystemEventMonitorStatus`

The fixed kind catalog covers network availability, network interface,
expensive/constrained network state, system sleep/wake, screen sleep/wake,
session lock/unlock, application launch/termination, active application change
and Bridge service health transitions.

Application payloads are normalized to safe bundle identifier and bounded
localized display name only. Network payloads contain only availability,
interface class, expensive and constrained state. Service-health payloads
contain only healthy, degraded or unavailable classification.

## Subscription Semantics

The Bridge-owned broker generates `ssub_` subscription IDs, validates fixed
event-kind filters, caps active subscriptions and pending batches, bounds poll
timeouts, expires inactive subscribers and supports explicit acknowledgement.
Repeated cancellation is idempotent. A slow consumer receives a typed
`resyncRequired` batch with a bounded reason code instead of unbounded buffering.

Service shutdown stops monitors and clears subscriptions.

## XPC Contract

Protocol version `1.4` adds capability `systemEventObservation` and these typed
operations:

- `createSystemEventSubscription`
- `pollSystemEventSubscription`
- `acknowledgeSystemEventBatch`
- `cancelSystemEventSubscription`
- `systemEventMonitorStatus`

No generic event source, notification-name or arbitrary filter API is exposed.

Protocol version `1.5` adds capability `systemEventPolicyManagement`. The
policy engine receives only normalized `HermesSystemEvent` values and may
execute only the fixed action catalog documented in
`Docs/SystemIntegration/EventPolicyEngine.md`. It does not add generic
automation, shell, AppleScript, URL-opening, executable-path or arbitrary XPC
operations.

Protocol version `1.6` adds capability `eventPolicyApprovalManagement` for
typed approval queue operations over immutable event-policy execution
snapshots.
