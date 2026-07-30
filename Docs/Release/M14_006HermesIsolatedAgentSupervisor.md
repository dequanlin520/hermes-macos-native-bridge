# M14-006 Hermes Isolated Agent Supervisor

## Objective

M14-006 adds a service-owned supervisor model for evaluating whether
HermesBridgeService can safely manage exactly one `hermes serve --isolated`
instance. The milestone is intentionally diagnostic: it determines whether an
isolated Agent can be launched, proven ready, attributed to Bridge-owned process
identity, and shut down without using any broad Hermes shutdown command.

## Relationship to M14-005

M14-005 established that the observed Hermes Agent 0.18.2 command surface
advertises isolated serving, status/readiness, and a broad `serve --stop`
operation. Because the stop operation may stop all Hermes web server processes,
M14-005 selected:

```text
LAUNCH_CONTRACT_STATUS=unsupported
LAUNCH_CONTRACT_REASON=shutdown.command.not_exact_isolated
```

M14-006 keeps that conclusion for the launch contract and evaluates a separate
question: whether Bridge-owned process identity is enough to supervise one
isolated foreground process safely.

## Broad Stop Rejection

The supervisor never invokes `hermes serve --stop`. It also never uses process
group signaling, `pkill`, `killall`, negative PIDs, command-text-only matching,
or broad global stop behavior. Shutdown is limited to exact PIDs whose identity
is revalidated before each signal.

## Supervisor Ownership

`HermesBridgeService` owns `HermesAgentSupervisor`. UI targets do not construct
supervisor configuration, launch Hermes, capture PIDs, inspect sockets, or
signal processes. The supervisor lives below the UI layer in
`HermesRuntimeFoundation` and is exposed to the service composition root without
changing the XPC protocol.

XPC remains at protocol version 1.8.

## Version Policy

The supervisor supports only the observed Hermes Agent 0.18.x family:

```text
>= 0.18.0, < 0.19.0
```

Unknown, unsupported, or future versions return stable blocked or unsupported
results. Future compatibility is not assumed.

## Isolated Launch

The supported launch shape is exactly:

```text
serve --isolated
```

The isolated environment is rooted under:

```text
artifacts/m14-006/runtime
```

The environment model requires isolated `HOME`, `HERMES_HOME`,
`XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME`, and `TMPDIR`, plus
`stdin=/dev/null`, no TTY, and bounded output.

## Process Topology

The supervisor records privacy-safe identity metadata for the root process and
proven descendants:

- PID, PPID, PGID, UID
- process start time
- executable basename
- executable file identity where available
- process state
- run identifier

Supported topology observations are:

- `foreground-single-process`
- `foreground-with-helpers`
- `launcher-exited-child-remains`
- `daemonized`
- `process-exited`
- `ambiguous-topology`

Descendants are acceptance-owned only when lineage is proven from the recorded
root identity and process start times. Broad command matching is not ownership
proof.

## Endpoint Ownership and Readiness

Readiness requires more than process existence. Endpoint evidence must be tied
to the recorded acceptance-owned process tree or to service-owned status
evidence. Listener ownership cannot be inferred from a port number alone.

Artifacts record only privacy-safe endpoint metadata:

- endpoint category
- loopback or Unix-socket classification
- owning PID relationship
- readiness timestamp
- protocol/status outcome

Full socket paths, unrelated listeners, and raw command lines are not included.

## Exact Shutdown

Shutdown proceeds in bounded phases:

1. Revalidate the root PID identity and send TERM only to that PID.
2. Wait for the root to exit.
3. Re-enumerate proven descendants.
4. Revalidate PID, UID, start time, executable identity, and lineage.
5. Send TERM to each exact remaining acceptance-owned PID.
6. Wait and reap.
7. Use KILL only on exact revalidated acceptance-owned PIDs as final fallback.
8. Verify no acceptance-owned process remains.

Any identity mismatch blocks signaling for that PID.

## Real-Home Isolation

M14-006 does not modify real `~/.hermes`. Real-home protection is based on
attributing real-home access to exact Bridge-owned PIDs, not on treating
unrelated external Hermes activity as Bridge activity. Reports distinguish:

- raw external mutation observed
- supervised process real-home access observed
- final Bridge isolation verdict

`REAL_HERMES_HOME_MODIFIED=no` is required for a passing supervised run.

## Operator Commands

Read-only inspect:

```zsh
Scripts/m14_006_isolated_agent_supervisor_acceptance.sh inspect
```

Opt-in run:

```zsh
HERMES_M14_006_ACCEPTANCE=YES Scripts/m14_006_isolated_agent_supervisor_acceptance.sh run
```

Cleanup:

```zsh
Scripts/m14_006_isolated_agent_supervisor_acceptance.sh cleanup
```

## Result Interpretation

The primary result file is:

```text
artifacts/m14-006/result.txt
```

Additional artifacts:

```text
artifacts/m14-006/process-topology.json
artifacts/m14-006/supervisor-report.json
artifacts/m14-006/evidence/
```

Compatibility levels:

- `SUPPORTED`: launch, readiness, discovery, exact shutdown, no orphan, and
  real-home isolation are proven.
- `PARTIALLY_SUPPORTED`: safe launch/readiness/shutdown succeeds, but an
  optional noncritical status capability is unavailable.
- `UNSUPPORTED`: topology or endpoint ownership cannot be supervised exactly.
- `BLOCKED`: executable, version, or platform facility is unavailable.
- `FAIL`: safety invariant violation, real-home access, orphan, or cleanup
  failure.

Exit codes:

- `0` PASS
- `1` FAIL
- `2` opt-in missing
- `3` BLOCKED
- `4` timeout
- `5` PARTIAL
- `6` UNSUPPORTED

## Limitations

This milestone does not add product runtime lifecycle behavior or UI controls.
It does not replace Hermes Desktop, expose remote control APIs, or introduce
new XPC operations. The default Darwin supervisor controller remains blocked
until the platform-specific endpoint and real-home attribution mechanisms are
validated by acceptance evidence.
