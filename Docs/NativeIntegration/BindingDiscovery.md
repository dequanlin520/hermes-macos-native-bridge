# Binding Discovery

## Contract

`HermesBridgeXPC` protocol `1.1` adds one backward-compatible operation:

```text
listEnabledBindings
```

The service advertises capability `bindingDiscovery` when the operation is
available. Clients with protocol major version `1` remain compatible. A client
talking to an older service receives a typed `unsupportedOperation` service
error and must treat binding discovery as unavailable.

## Summary Model

`HermesBridgeBindingSummary` contains only:

- binding ID;
- localized display name;
- safe localized description;
- maximum Prompt length in bytes;
- approval policy token;
- enabled state.

It does not expose executable paths, process arguments, endpoints, backend
tokens, JSON-RPC methods, environment values, result locators, prompts, result
bodies, or private filesystem paths.

## Bounds

The service returns enabled bindings only, sorted by binding ID. The list is
bounded to `128` records and the encoded payload is bounded to `64 KiB`.
Display names, descriptions, and approval policy values are filtered and
truncated before encoding.

## Service Adapter

`HermesBridgeServiceRequestHandler` delegates request operations to
`HermesRequestOrchestrator` and delegates binding discovery to the
configuration-backed binding registry. The registry keeps trusted
configuration definitions internally and exposes only safe summaries.

## App Intent Query

`HermesAppIntentProductionBindingProvider` uses typed XPC discovery. If the
Bridge is unavailable or the service is too old, it returns an empty
deterministic fallback. `SubmitHermesRequestIntent` validates the selected
binding ID against current discovery before submitting a Prompt, so callers
cannot supply arbitrary binding IDs.

The App Intents cache stores only safe binding summaries, has a bounded
lifetime, is actor-protected for concurrency, and never caches Prompts,
backend tokens, raw result bodies, or result locators.
