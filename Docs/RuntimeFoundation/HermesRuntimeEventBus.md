# Hermes Runtime Event Bus

## Scope

`HermesRuntimeEventBus` is the Runtime Foundation event propagation layer for
Bridge-owned Hermes runtime sessions. It distributes typed lifecycle events
published by `HermesRuntimeSessionManager`.

The event bus does not start processes, call protocol methods, submit prompts,
run callbacks, execute scripts, or perform system integration work.

## Architecture

```text
HermesRuntimeEventBus
        |
        v
HermesRuntimeSessionManager
        |
        v
HermesRuntimeSession
```

The session manager owns publication. Runtime sessions remain responsible for
state transitions and backend interaction. Subscribers receive immutable event
values through `AsyncStream`.

## Event Model

`HermesRuntimeEventKind` defines the fixed event vocabulary:

- `sessionCreated`
- `sessionStarting`
- `sessionRunning`
- `sessionHealthChanged`
- `sessionFailed`
- `sessionStopping`
- `sessionStopped`

Each `HermesRuntimeEvent` contains:

- `sequenceNumber`: monotonic bus-local sequence number assigned during
  publication;
- `kind`: typed event kind;
- `session`: redacted session summary;
- `occurredAt`: Bridge-observed event time.

The session summary contains only bounded lifecycle metadata:

- session UUID;
- current lifecycle status;
- backend semantic version when known;
- process ID when known;
- start time when known;
- capability summary;
- redacted error message;
- typed shutdown reason.

Raw `HermesRuntimeSessionSnapshot` values are not placed on the bus because
snapshots can include executable paths and process command shape details.

## Subscription API

`publish(_:)` assigns the next sequence number and yields the event to every
active subscriber.

`subscribe()` returns a `HermesRuntimeEventSubscription` containing a stable
subscription ID and an `AsyncStream<HermesRuntimeEvent>`.

`unsubscribe(_:)` removes the subscription and finishes its stream. Stream
termination also removes the subscription, so consumers that stop iterating do
not leave retained continuations behind.

The bus does not create worker tasks. Delivery is synchronous with publication
and uses the buffering policy configured by the subscriber.

## Ordering

Ordering is guaranteed per bus instance. Each published event receives a
strictly increasing sequence number before delivery. A subscriber observes the
events yielded to its stream in publication order.

## Manager Integration

`HermesRuntimeSessionManager` owns an injectable event bus. Lifecycle operations
publish events after manager-visible state changes:

- `createSession()` publishes `sessionCreated`.
- `startSession(_:)` publishes `sessionStarting` before the backend start and
  then `sessionRunning`, `sessionHealthChanged`, or `sessionFailed`.
- `refreshSessionStatus(_:)` publishes `sessionHealthChanged` when health
  changes or health refresh fails into degraded state.
- `stopSession(_:)` publishes `sessionStopping` before backend shutdown and
  then `sessionStopped` or `sessionFailed`.

Invalid lifecycle operations do not publish synthetic transition events unless
the underlying session state actually changes.

## Security Boundary

Events are diagnostic lifecycle signals only:

- no credentials;
- no tokens;
- no prompts;
- no raw session snapshots;
- no process command shape;
- no executable path payload;
- no arbitrary callbacks.

Known credential markers are redacted before error text reaches event
descriptions. Absolute private path patterns rooted at `/Users`, `/private`,
`/var`, and `/tmp` are replaced with `<redacted-path>` in event error messages.

## Testing

`HermesRuntimeSessionManagerTests` covers:

- publish and receive;
- multiple subscribers;
- unsubscribe and subscription release;
- ordered lifecycle events;
- health change events;
- startup failure events;
- shutdown failure events;
- stream completion without leaked retained subscriptions.
