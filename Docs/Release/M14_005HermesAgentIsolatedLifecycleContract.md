# M14-005 Hermes Agent Isolated Lifecycle Contract

## Objective

M14-005 defines a production-safe, versioned contract for starting, observing,
and stopping one isolated Hermes Agent instance without using the user's real
Hermes profile.

The milestone is a contract and validation milestone. It does not add UI, does
not replace Hermes Desktop, and does not introduce a generic process execution
API.

## Contract Model

The production contract lives below the UI layer in `HermesRuntimeFoundation`.
The main types are:

- `HermesAgentLaunchContract`
- `HermesAgentLaunchDescriptor`
- `HermesAgentLaunchCapability`
- `HermesAgentLaunchEnvironment`
- `HermesAgentProcessIdentity`
- `HermesAgentReadinessEvidence`
- `HermesAgentShutdownResult`
- `HermesAgentLifecycleError`

Contract outcomes are explicit:

- `supported`
- `partially-supported`
- `unsupported`
- `blocked`
- `incompatible`

`supported` is only valid when noninteractive startup, isolated writable roots,
bounded readiness, stable process identity, documented status, graceful shutdown,
and exact-PID fallback safety are all available.

## Version Policy

The only version range considered by the M14-005 adapter is:

- lower inclusive: `0.18.0`
- upper exclusive: `0.19.0`

Future minor or major versions are not assumed compatible. Unknown or malformed
versions are rejected or blocked rather than inferred.

## Supported And Unsupported Semantics

An honest `UNSUPPORTED` result is acceptable when the installed Hermes Agent
does not advertise a safe isolated lifecycle contract. In that case probes and
cleanup must still succeed, no real profile state may be modified, and no real
Hermes process may be stopped.

`BLOCKED` is reserved for missing executables, failed read-only probes, unsafe
environment construction, or unavailable platform facilities.

`FAIL` is reserved for safety violations, cleanup failure, real Hermes home
mutation, malformed evidence, process identity ambiguity, or supported commands
that fail unexpectedly.

## Isolated Environment

Lifecycle operations use an acceptance-owned root:

```sh
artifacts/m14-005/runtime
```

The environment sets:

- `HOME`
- `HERMES_HOME`
- `XDG_CONFIG_HOME`
- `XDG_STATE_HOME`
- `XDG_CACHE_HOME`
- `TMPDIR`

The production environment utility rejects real home usage, symlink escape,
`..` traversal, unresolved paths, unsafe world-writable parents, and conflicting
environment keys.

## Process Identity

For a started isolated Agent, the coordinator records:

- PID
- PPID
- PGID
- UID
- executable basename
- executable file identity
- process start time
- launch run identifier

Before every signal, the exact process identity is revalidated. The contract
does not signal process groups and does not use broad cleanup commands.

## Readiness

Readiness cannot be process existence alone. A supported contract requires a
documented status command, production discovery evidence, or another structured
readiness mechanism.

Stable readiness reason codes include:

- `readiness-timeout`
- `process-exited-before-ready`
- `malformed-readiness-evidence`
- `discovery-mismatch`
- `unsupported-readiness-contract`

## Shutdown

The shutdown sequence is:

1. Attempt documented graceful shutdown when advertised.
2. Revalidate exact process identity.
3. Send TERM to the exact PID when fallback is allowed.
4. Reap and wait for bounded grace.
5. Revalidate exact process identity again.
6. Send KILL to the exact PID only as the final fallback.

Reported shutdown statuses are:

- `graceful`
- `exact-term`
- `exact-kill`
- `already-exited`
- `identity-mismatch`
- `timeout`
- `unsupported`

## Service Ownership

`HermesBridgeService` owns lifecycle contract selection and coordination through
`HermesBridgeCompositionRoot`. The UI does not instantiate lifecycle
coordinators and does not start or stop Agent processes.

M14-005 does not change XPC protocol 1.8. No production client requires a new
method for this contract milestone.

## Operator Commands

Read-only inspect:

```sh
Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh inspect
```

Opt-in run:

```sh
HERMES_M14_005_ACCEPTANCE=YES Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh run
```

Cleanup:

```sh
Scripts/m14_005_isolated_agent_lifecycle_acceptance.sh cleanup
```

## Result Interpretation

Artifacts are written under:

```sh
artifacts/m14-005/
```

Primary files:

- `result.txt`
- `launch-contract.json`
- `evidence/`

Exit codes:

- `0` PASS
- `1` FAIL
- `2` opt-in missing
- `3` BLOCKED
- `4` timeout
- `5` PARTIAL
- `6` UNSUPPORTED

Artifacts must not contain absolute user paths, command lines, tokens, profile
contents, UUIDs, or secrets.

## Limitations

M14-005 does not manufacture a launch command. If Hermes Agent 0.18.2 does not
advertise safe noninteractive isolated startup, status, and shutdown mechanics,
the correct result is `UNSUPPORTED`.
