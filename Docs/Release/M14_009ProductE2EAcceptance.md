# M14-009 Product End-to-End Acceptance

M14-009 validates the supported RC product path through production ownership
boundaries:

Native App / Menu Bar / App Intents -> XPC 1.8 -> HermesBridgeService ->
service-owned isolated Hermes supervisor -> dynamic endpoint ownership ->
`/api/status` -> typed product capability snapshot -> UI presentation.

The milestone does not add Hermes request transport. Hermes Agent 0.18.2 is
treated as a status-only integration because no public request, cancellation,
or approval route is advertised.

## Capability Snapshot

`HermesProductCapabilitySnapshot` is the production capability model. It is
embedded in the existing XPC 1.8 capabilities response so clients can consume
typed capability evidence without a protocol bump.

Each capability includes:

- identifier
- supported, unsupported, blocked, or unavailable status
- exercised state
- reason code
- observed Hermes version
- ownership source
- timestamp category
- privacy-safe explanation

Unsupported request, cancellation, and approval controls use the deterministic
reason `transport.route-unsupported`.

## Acceptance Script

Use:

```zsh
Scripts/m14_009_product_e2e_acceptance.sh inspect
HERMES_M14_009_ACCEPTANCE=YES Scripts/m14_009_product_e2e_acceptance.sh run
Scripts/m14_009_product_e2e_acceptance.sh cleanup
```

`inspect` is read-only. `run` requires explicit opt-in and writes redacted
evidence under `artifacts/m14-009`.

The script must not print or persist dynamic ports, PIDs, paths, tokens, URLs,
request IDs, or raw process command lines in deterministic result files.

## PASS Boundary

PASS requires app/XPC/service capability snapshot delivery, service-owned
isolated Agent start/readiness/status, visible unsupported request/cancel/
approval controls, exit/relaunch/reconnect behavior, controlled service
restart/reconnect, exact Agent shutdown, cleanup, real-home isolation, and RC
scope freeze.

FAIL applies to private `/api/ws` assumptions, UI-owned runtime operation, XPC
ownership violations, status continuity failure, cleanup residue, real-home
access, broad process control, or malformed capability evidence.
