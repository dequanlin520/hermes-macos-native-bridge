# M14-004 Hermes Compatibility Matrix

## Objective

M14-004 adds a deterministic, privacy-safe compatibility assessment between
Hermes macOS Native Bridge and the locally installed real Hermes CLI/Agent.
It does not implement M14-005 behavior and does not add Bridge runtime product
features.

The matrix answers whether a Hermes executable is available, what family and
version were detected, whether service-owned discovery can see it, which
non-mutating commands are supported, which isolated lifecycle checks are safe,
and whether generated files and acceptance-owned processes are cleaned up.

## Ownership Boundary

`HermesBridgeService` remains the runtime owner. The service composition root
constructs `HermesDiscovery` and passes it to `HermesBridgeServiceRequestHandler`.
The UI app does not instantiate `HermesDiscovery`, `HermesRuntimeSessionManager`,
`HermesRuntimeEventBus`, or `HermesRuntimeCommandAPI`.

Compatibility model types live in `HermesRuntimeFoundation`:

- `HermesAgentCompatibilityReport`
- `HermesAgentCompatibilityLevel`
- `HermesAgentCapabilityResult`
- `HermesAgentVersionDescriptor`

The service exposes an internal `agentCompatibilityReport()` helper from the
existing service-owned discovery path. XPC protocol 1.8 is unchanged because
M14-004 does not need a new UI-facing operation.

## Isolation Model

The opt-in acceptance run uses only:

```sh
artifacts/m14-004/runtime
```

The run sets isolated values for:

```sh
HOME
HERMES_HOME
XDG_CONFIG_HOME
XDG_STATE_HOME
XDG_CACHE_HOME
TMPDIR
```

The script must not read secrets from the real Hermes home, copy real profiles,
use Keychain records, use sudo, use broad process matching, stop existing real
Hermes processes, download Hermes, upgrade Hermes, or uninstall Hermes.

Before and after `run`, the script records privacy-safe metadata snapshots of
the real Hermes home. Any difference sets:

```text
REAL_HERMES_HOME_MODIFIED=yes
M14_004_RESULT=FAIL
```

There are no attribution exceptions in M14-004.

## Compatibility Levels

- `compatible`: exercised by acceptance or proven by production API contract.
- `partially-compatible`: discovery/version/help/isolation are usable, but
  lifecycle or protocol handshakes were blocked or unverified.
- `incompatible`: an exercised check proves the installed executable does not
  match the expected contract.
- `blocked`: the check could not safely run, usually because no compatible
  executable or safe isolated lifecycle contract is available.
- `unverified`: the milestone did not exercise the capability and no production
  contract proves it.

## Matrix Rows

The JSON matrix contains stable rows for:

- executable discovery
- version query
- help query
- isolated profile root
- isolated configuration inspection
- bounded Agent startup
- Agent readiness detection
- service-owned Agent discovery
- lifecycle status query
- request submission handshake
- request cancellation handshake
- approval capability discovery
- graceful Agent shutdown
- forced exact-PID cleanup fallback
- real-home isolation
- generated-artifact cleanup

Rows include a stable reason code, exercise flag, evidence category, observed
version when known, blocking flag, and privacy-safe notes.

## Executable Discovery

Discovery reports only privacy-safe structured fields:

- discovery status
- executable family
- executable basename
- semantic version when available
- version command exit status
- supported invocation style
- source category: `PATH`, `known-user-install-location`, or `unavailable`

Result artifacts must not contain the full executable path.

If no executable is available, the result is `BLOCKED`; compatibility is not
manufactured.

## Protocol Negotiation

XPC remains at protocol `1.8`. Existing agent discovery remains available
through the established versioned operation. The M14-004 compatibility report is
kept below the UI layer and does not require a protocol extension.

If a future milestone exposes the full report over XPC, it must deliberately
bump the protocol version, document older-client behavior, retain unsupported
version rejection, and update XPC protocol tests.

## Operator Commands

Read-only local inspection:

```sh
Scripts/m14_004_hermes_compatibility_acceptance.sh inspect
```

Opt-in compatibility run:

```sh
HERMES_M14_004_ACCEPTANCE=YES Scripts/m14_004_hermes_compatibility_acceptance.sh run
```

Cleanup:

```sh
Scripts/m14_004_hermes_compatibility_acceptance.sh cleanup
```

The acceptance script uses bounded exits:

- `0`: PASS
- `1`: FAIL
- `2`: explicit opt-in missing
- `3`: BLOCKED
- `4`: timeout
- `5`: PARTIAL

## Cleanup

Cleanup is idempotent. If an acceptance-owned PID was recorded, the script
validates the exact PID identity with `ps` output before signaling that PID.
It does not use `pkill`, `killall`, negative process IDs, or sudo.

The script removes only the M14-004 runtime root and leaves ignored result
artifacts under `artifacts/m14-004`.

## Result Interpretation

`result.txt` contains deterministic unique keys. Important gates are:

- `SERVICE_OWNED_DISCOVERY_USED=yes`
- `ISOLATED_HOME_USED=yes`
- `REAL_HERMES_HOME_MODIFIED=no`
- `ACCEPTANCE_PROCESS_REMAINING=no`
- `GENERATED_ARTIFACT_TRACKED_BY_GIT=no`

`compatibility-matrix.json` is the row-level evidence source. A partial result
is expected when Hermes can be discovered and queried but the installed CLI does
not expose a safe isolated Agent lifecycle contract.

## Known Limitations

M14-004 does not start a real Agent unless the installed Hermes CLI provides a
safe isolated startup contract. Request, cancel, approval, readiness, and
shutdown rows remain blocked or unverified when no owned isolated Agent was
started. The milestone does not touch the real user Hermes profile and does not
quiesce or modify existing real Hermes processes.
