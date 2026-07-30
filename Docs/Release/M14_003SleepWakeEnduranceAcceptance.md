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
HERMES_QUIESCE_REAL_AGENT=YES \
HERMES_REAL_AGENT_ROOT_PIDS="<space-separated real Hermes Agent root PIDs, or empty>" \
Scripts/m14_003_sleep_wake_endurance_acceptance.sh prepare
```

The prepare phase performs collision checks, builds and installs the Release
app, installs and bootstraps the production `com.hermes.bridge` LaunchAgent,
establishes XPC protocol `1.8`, executes exactly five service restart/reconnect
cycles, proves app exit leaves the service running, relaunches the app, writes a
privacy-safe real-home snapshot, optionally quiesces only explicitly supplied
real Hermes Agent root process groups, starts a dedicated wake recorder, proves
the recorder readiness handshake, and creates a durable checkpoint under
`artifacts/m14-003/runtime/`.

Before prepare prints `WAITING_FOR_MANUAL_SLEEP=yes`, it reads the checkpoint
back and verifies the durable power-log boundary object, recorder identity,
relative evidence paths, real-home baseline path, and exact quiesced process
records. If any required checkpoint field is missing or malformed, prepare fails
before asking the operator to sleep.

When `HERMES_REAL_AGENT_ROOT_PIDS` is non-empty, `HERMES_QUIESCE_REAL_AGENT=YES`
is required. The script validates that every supplied root PID and every exact
current-user PGID member belongs to the current UID, records PID, UID, PGID,
executable basename, process start time, and suspended state in the checkpoint,
then sends `SIGSTOP` only to those recorded PIDs. If no real Hermes Agent is
running, leave `HERMES_REAL_AGENT_ROOT_PIDS` empty.

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
domain and is independent of the initiating terminal. Its primary evidence is
IOKit system power notification delivery: `kIOMessageSystemWillSleep` is
persisted and fsynced before `IOAllowPowerChange`, and
`kIOMessageSystemHasPoweredOn` is persisted after wake. NSWorkspace notifications
may also be recorded, but they are only secondary corroboration and are
insufficient by themselves. The recorder writes a ready file only after
`IORegisterForSystemPower` succeeds, its CFRunLoop is active, the run identifier
matches, the exact recorder PID is alive, and the evidence destination is
writable.

### 3. Resume

```sh
HERMES_SLEEP_WAKE_ACCEPTANCE=YES \
Scripts/m14_003_sleep_wake_endurance_acceptance.sh resume
```

The resume phase loads the durable checkpoint, verifies the run identifier,
requires IOKit will-sleep and powered-on evidence, rejects NSWorkspace-only or
wall-clock-only evidence, validates event order and monotonic uptime consistency,
continues only exact recorded real Hermes Agent PIDs whose PID/UID/PGID/basename
and process start time still match, verifies LaunchAgent/service
availability, verifies XPC protocol `1.8`, relaunches or reconnects the app as
needed, verifies service-owned runtime and app non-ownership, rejects duplicate
service instances, performs one final controlled service restart, verifies final
reconnect, compares the real-home integrity snapshot, removes acceptance-owned
targets, writes the final result, and returns the final exit code.

`resume` returns `0` only for final `M14_003_RESULT=PASS`.

## Read-Only Checkpoint Inspection

Inspect the active checkpoint, or a matching diagnostic checkpoint when the
active checkpoint no longer has a valid power boundary:

```sh
Scripts/m14_003_sleep_wake_endurance_acceptance.sh inspect-checkpoint
```

This mode does not require opt-in, does not write result files, and does not
change system state. It reports only run ID match, required field type status,
power boundary epoch, UTC and timezone type status, recorder identity status,
quiescence completeness, and checkpoint schema version. It does not print
absolute paths.

To inspect a specific run, pass the run identifier used by prepare:

```sh
HERMES_M14_003_RUN_ID="<run-id>" \
Scripts/m14_003_sleep_wake_endurance_acceptance.sh inspect-checkpoint
```

Power-log diagnostics use the same checkpoint selection order: active checkpoint
for the requested run ID when it has a valid power boundary, otherwise the
latest matching privacy-safe diagnostic checkpoint under
`artifacts/m14-003/diagnostics/`.

## Read-Only Diagnostic Finalization

After a completed real run, use replay finalization to recompute only the
real-home attribution verdict and final result without another sleep/wake cycle:

```sh
Scripts/m14_003_sleep_wake_endurance_acceptance.sh finalize-diagnostic-run
```

This mode does not require opt-in. It loads the latest matching preserved
checkpoint/evidence, preserves the already recorded sleep/wake, XPC, lifecycle,
runtime ownership, and cleanup keys, writes a new `result.txt`, and exits `0`
only when the attribution-aware result is `PASS`. It does not install, stop,
signal, launch, sleep, clean, or otherwise modify system state.

## Cleanup For Interrupted Runs

Use cleanup after prepare failure, terminal closure, sleep interruption, resume
failure, or a stale checkpoint:

```sh
Scripts/m14_003_sleep_wake_endurance_acceptance.sh cleanup
```

Cleanup reads `artifacts/m14-003/runtime/checkpoint.json` when present and
targets only acceptance-owned state:

- Exact recorded real Hermes Agent PIDs, resumed with `SIGCONT` only if PID,
  UID, PGID, executable basename, and process start time still match.
- The recorded app PID.
- The recorded wake-recorder PID.
- The exact recorded project-owned recorder label.
- The exact `com.hermes.bridge` LaunchAgent installed by this run.
- `~/Applications/Hermes Bridge.app` only when this run installed it.
- `~/Library/LaunchAgents/com.hermes.bridge.plist` only when this run installed it.
- The M14-003 lock owned by this run.

Cleanup does not remove real `~/.hermes`, unrelated LaunchAgents, unrelated
application bundles, unrelated logs, browser data, or Keychain items.

Failed resume paths preserve a privacy-safe diagnostic checkpoint copy under
`artifacts/m14-003/diagnostics/<run-id>-checkpoint.json` before cleanup rewrites
or removes active runtime state. The diagnostic copy preserves run ID, power-log
boundaries, recorder evidence identifiers, failure reason, and phase ordering,
with private absolute paths redacted.

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

`REAL_HERMES_HOME_MODIFIED` remains a transparent mutation detector. A `yes`
value means real user Hermes state changed during the acceptance interval; it
does not by itself identify the writer. Final acceptance uses additional keys:

- `BRIDGE_TOUCHED_REAL_HERMES_HOME`: whether exact Bridge-owned processes or
  Bridge-owned state paths are attributed to the mutation.
- `EXTERNAL_HERMES_ACTIVITY_DETECTED`: whether changed relative paths are
  limited to known external Hermes operational categories, such as cron
  heartbeat/ticker and account synchronization metadata.
- `REAL_HOME_ATTRIBUTION_CONFIDENCE`: `high`, `medium`, `low`, or `unknown`
  confidence in the writer attribution.

M14-003 fails if Bridge is attributed as the writer, attribution is low/unknown
while real-home changed, isolated Bridge writable roots are not proven, or any
core sleep/wake, XPC, lifecycle, runtime ownership, or cleanup check fails.

M14-003 may pass with `REAL_HERMES_HOME_MODIFIED=yes` only when Bridge did not
touch real `~/.hermes`, external Hermes activity is detected, attribution
confidence is high, LaunchAgent/app/service writable roots are proven isolated
under `artifacts/m14-003/runtime`, the comparison occurred before recorded
external Agent `SIGCONT`, and all core checks passed.

Attribution evidence is privacy-safe. The script records changed relative paths
and metadata categories, exact acceptance-owned targets and PIDs, isolated
environment roots, phase ordering, and exact-PID open-file observations where
available. It does not inspect secret file contents.
