# M14-003 Sleep/Wake and Service Restart Endurance Acceptance

## Purpose

M14-003 is an operator-controlled real-system release gate for the frozen V0.1
Bridge scope. It validates repeated service restart and XPC reconnection, app
exit and relaunch behavior, manual macOS sleep/wake handling, post-wake service
availability, runtime ownership, and cleanup.

The script does not add product runtime behavior or a UI center. It installs
only the real user-scoped acceptance targets used for this gate.

## Non-Opt-In Static Path

Run without opt-in only to validate the static contract and write a dry result:

```sh
Scripts/m14_003_sleep_wake_endurance_acceptance.sh
```

The no-argument form is intentionally explicit: it prints usage, writes
`artifacts/m14-003/result.txt`, reports `M14_003_RESULT=OPT_IN_REQUIRED`, exits
`2`, does not install anything, and does not ask the system to sleep.

## Real Acceptance Workflow

Use these commands only from the real macOS login session that will be tested.
The script never initiates sleep.

### 1. Prepare

```sh
HERMES_SLEEP_WAKE_ACCEPTANCE=YES \
Scripts/m14_003_sleep_wake_endurance_acceptance.sh prepare
```

The prepare phase performs collision checks, builds and installs the Release
app, installs and bootstraps the production `com.hermes.bridge` LaunchAgent,
establishes XPC protocol `1.8`, executes exactly five service restart/reconnect
cycles, proves app exit leaves the service running, relaunches the app, writes a
privacy-safe real-home snapshot, starts a dedicated wake recorder, and creates a
durable checkpoint under `artifacts/m14-003/runtime/`.

On success it writes:

```text
WAITING_FOR_MANUAL_SLEEP=yes
M14_003_RESULT=WAITING
```

and exits `5`. This is the expected transitional state. The prepare command does
not wait indefinitely in the foreground.

### 2. Manually Sleep, Then Wake/Login

After prepare exits `5`, manually put the Mac to sleep using normal system UI or
hardware controls. Wake the Mac and log back in.

The dedicated project-owned recorder is launched through the user LaunchAgent
domain and is independent of the initiating terminal. It records
`NSWorkspace.willSleepNotification`, `NSWorkspace.didWakeNotification`,
`ProcessInfo.systemUptime` before sleep and after wake, monotonic timestamps,
the exact recorder PID, and the exact unique recorder label. Wall-clock delay
alone is rejected as evidence.

### 3. Resume

```sh
HERMES_SLEEP_WAKE_ACCEPTANCE=YES \
Scripts/m14_003_sleep_wake_endurance_acceptance.sh resume
```

The resume phase loads the durable checkpoint, verifies the run identifier,
requires genuine will-sleep and did-wake evidence, rejects wall-clock-only
evidence, validates monotonic uptime consistency, verifies LaunchAgent/service
availability, verifies XPC protocol `1.8`, relaunches or reconnects the app as
needed, verifies service-owned runtime and app non-ownership, rejects duplicate
service instances, performs one final controlled service restart, verifies final
reconnect, compares the real-home integrity snapshot, removes acceptance-owned
targets, writes the final result, and returns the final exit code.

`resume` returns `0` only for final `M14_003_RESULT=PASS`.

## Cleanup For Interrupted Runs

Use cleanup after prepare failure, terminal closure, sleep interruption, resume
failure, or a stale checkpoint:

```sh
Scripts/m14_003_sleep_wake_endurance_acceptance.sh cleanup
```

Cleanup reads `artifacts/m14-003/runtime/checkpoint.json` when present and
targets only acceptance-owned state:

- The recorded app PID.
- The recorded wake-recorder PID.
- The exact recorded project-owned recorder label.
- The exact `com.hermes.bridge` LaunchAgent installed by this run.
- `~/Applications/Hermes Bridge.app` only when this run installed it.
- `~/Library/LaunchAgents/com.hermes.bridge.plist` only when this run installed it.
- The M14-003 lock owned by this run.

Cleanup does not remove real `~/.hermes`, unrelated LaunchAgents, unrelated
application bundles, unrelated logs, browser data, or Keychain items.

## Scoped Paths

The run is limited to:

- App target: `~/Applications/Hermes Bridge.app`
- LaunchAgent target: `~/Library/LaunchAgents/com.hermes.bridge.plist`
- LaunchAgent label: `com.hermes.bridge`
- Mach service: `com.hermes.bridge.xpc`
- Wake-recorder label: `com.hermes.bridge.m14-003.wake-recorder.<run-id>`
- Isolated writable state: `artifacts/m14-003/runtime`

Durable artifacts avoid absolute home paths. The checkpoint stores relative
target identifiers plus exact labels and PIDs so cleanup can reconstruct the
user-scoped paths safely.

## Result Semantics

Exit codes map directly to `M14_003_RESULT`:

- `0`: `PASS`
- `1`: `FAIL`
- `2`: `OPT_IN_REQUIRED`
- `3`: `BLOCKED`
- `4`: `TIMEOUT`
- `5`: `WAITING`

The result artifact is:

```text
artifacts/m14-003/result.txt
```

Generated artifacts remain ignored by Git under `artifacts/`.
