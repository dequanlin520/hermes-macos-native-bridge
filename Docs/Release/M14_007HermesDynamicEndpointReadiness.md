# M14-007 Hermes Dynamic Endpoint Ownership and Readiness

## Objective

M14-007 extends the M14-006 exact-process supervision work to discover the endpoint assigned by:

```sh
hermes serve --isolated --port 0
```

The milestone proves that the dynamic listener belongs to the exact supervised root process or a proven descendant, then uses only that acceptance-scoped endpoint for readiness, status, and service-owned discovery checks.

## Relationship to M14-006

M14-006 proved launch identity capture and exact PID shutdown. It intentionally ended with readiness blocked because endpoint ownership was not proven. M14-007 does not replace that supervisor. It adds endpoint discovery and readiness evidence below the UI layer and reuses the same exact PID shutdown sequencing.

## Dynamic Port Behavior

`--port 0` is treated as a dynamic-port request. The deterministic `result.txt` records `DYNAMIC_PORT_REQUESTED=yes` but does not include the assigned numeric port. Runtime evidence JSON may contain the port inside ignored `artifacts/m14-007/evidence/` material.

## Endpoint Ownership Proof

Endpoint discovery is service-owned. UI code must not enumerate sockets, inspect PIDs, build endpoint URLs, or poll readiness.

The accepted listener must be:

- TCP loopback, or a documented acceptance-owned Unix socket.
- Owned by the exact validated root PID or a proven descendant.
- Matched by PID, UID, and process start time.
- Observed after the launch checkpoint.
- Unique for the supervised run.

The real acceptance script uses `/usr/sbin/lsof` only with exact acceptance-owned PID filtering.

## Readiness Contract

Readiness requires both endpoint ownership proof and a Hermes-specific bounded response. The selected Hermes 0.18.2 readiness mechanism is a bounded GET to:

```text
http://127.0.0.1:<dynamic-port>/api/status
```

The response must have the expected Hermes status shape, such as `version`, `auth_required`, `desktop_contract`, `gateway_running`, or `active_agents`. A live process, listening socket, TCP connection, or arbitrary HTTP 200 is not readiness.

## Service-Owned Discovery

Service-owned discovery receives the supervised endpoint candidate and matches against that candidate only. It does not globally scan or adopt unrelated Hermes Agent instances.

## Shutdown Sequencing

After readiness and discovery checks, shutdown reuses M14-006 exact identity rules:

```text
exact root TERM
exact descendant TERM only when needed
exact KILL only as final fallback
verify listener disappearance
verify no acceptance process remains
```

The acceptance flow never invokes `hermes serve --stop`, broad process killing, process-group signaling, `sudo`, or unrelated endpoint queries.

## Security Boundaries

The acceptance run uses an isolated runtime and home. It must not read or write the real `~/.hermes`. Startup output and result artifacts are sanitized; deterministic results avoid dynamic endpoint values.

## Operator Commands

Read-only inspect:

```sh
Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh inspect
```

Opt-in real acceptance:

```sh
HERMES_M14_007_ACCEPTANCE=YES Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh run
```

Idempotent cleanup:

```sh
Scripts/m14_007_dynamic_endpoint_readiness_acceptance.sh cleanup
```

## Result Interpretation

`PASS` means the dynamic endpoint was discovered, listener ownership and Hermes endpoint identity were proven, service discovery matched, exact shutdown succeeded, the listener disappeared, no acceptance process remained, and the environment was restored.

`PARTIAL` is reserved for proven listener ownership and Hermes identity with exact shutdown where one optional status or discovery capability is unavailable.

`UNSUPPORTED` means ownership is proven but Hermes 0.18.2 exposes no safe readiness/status mechanism.

`BLOCKED` means the executable, platform, or exact socket ownership facility is unavailable.

`FAIL` means ownership mismatch, ambiguous candidates, non-loopback exposure, malformed or spoofed identity, real-home access, cleanup failure, broad operation, or remaining process/listener evidence.

## Limitations

The implementation is scoped to Hermes Agent 0.18.x and acceptance-owned isolated runs. It does not expose dynamic endpoints over XPC and does not change protocol 1.8.
