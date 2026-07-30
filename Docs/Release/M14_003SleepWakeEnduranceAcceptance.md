# M14-003 Sleep/Wake and Service Restart Endurance Acceptance

## Purpose

M14-003 is an operator-controlled real-system release gate for the frozen V0.1
Bridge scope. It validates repeated service restart and XPC reconnection, app
exit and relaunch behavior, manual macOS sleep/wake handling, post-wake service
availability, and cleanup.

The script does not add product runtime behavior or a UI center. It installs
only the real user-scoped acceptance targets used for this gate.

## Non-Opt-In Preflight

Run without opt-in to validate the static contract and write a dry-run result:

```sh
Scripts/m14_003_sleep_wake_endurance_acceptance.sh
```

Without the exact opt-in value, the script writes
`artifacts/m14-003/result.txt`, reports `M14_003_RESULT=OPT_IN_REQUIRED`, exits
`2`, does not install anything, and does not ask the system to sleep.

## Opt-In Command

Use this only from the real macOS login session that will be tested:

```sh
HERMES_SLEEP_WAKE_ACCEPTANCE=YES Scripts/m14_003_sleep_wake_endurance_acceptance.sh
```

The script never initiates sleep. After the pre-sleep checks pass it prints:

```text
WAITING_FOR_MANUAL_SLEEP=yes
```

At that point the operator manually puts the Mac to sleep, then wakes it before
the bounded timeout expires.

## Scoped Paths

The run is limited to:

- App target: `~/Applications/Hermes Bridge.app`
- LaunchAgent target: `~/Library/LaunchAgents/com.hermes.bridge.plist`
- LaunchAgent label: `com.hermes.bridge`
- Mach service: `com.hermes.bridge.xpc`
- Isolated writable state: `artifacts/m14-003/runtime`

The script does not modify `/Applications`, `/Library`, real `~/.hermes`,
unrelated LaunchAgents, unrelated Keychain entries, browser data, or unrelated
processes.

## Restart-Cycle Design

After installation, app launch, and initial XPC protocol `1.8` validation, the
script performs exactly five controlled restart cycles. Each cycle boots out
and bootstraps only the exact acceptance-installed production label in the
current `gui/$UID` domain, waits for a new service PID, verifies XPC protocol
`1.8`, confirms the service-owned runtime boundary, confirms the app does not
own runtime, and performs a reconnect check.

After the five cycles, the script terminates only the recorded acceptance-owned
app PID, verifies the service remains running, relaunches the app, and verifies
pre-sleep reconnection.

## Sleep/Wake Detection Design

The manual sleep checkpoint records service state, app state, safe XPC protocol
state, and a privacy-safe real-home integrity snapshot.

The wait uses a narrowly scoped Swift helper under `artifacts/m14-003/` that
listens for `NSWorkspace.willSleepNotification` and
`NSWorkspace.didWakeNotification`, and records `ProcessInfo.systemUptime`
evidence. A wall-clock delay alone is not accepted as proof. If a real sleep
and wake transition is not observed before the timeout, the result is
`M14_003_RESULT=TIMEOUT` and the exit code is `4`.

## Post-Wake Validation

After wake, the script verifies the LaunchAgent is loaded or restored by
launchd, waits for the service, verifies XPC protocol `1.8`, verifies app
reconnection, rechecks service-owned runtime and app non-ownership, rejects
duplicate exact service executable instances, performs one final controlled
service restart, and verifies the final reconnect.

Hermes Agent may remain unavailable. Agent-dependent checks are reported as
`AGENT_DEPENDENT_CHECK=skip` when Agent status is unavailable, incompatible, or
unknown.

## Cleanup

Cleanup runs for pass, fail, timeout, interrupt, terminate, or hangup. It
targets only acceptance-owned state:

- The recorded acceptance-owned app PID
- The exact `com.hermes.bridge` LaunchAgent installed by this run
- `~/Applications/Hermes Bridge.app` only when this run installed it
- `~/Library/LaunchAgents/com.hermes.bridge.plist` only when this run installed it
- The M14-003 lock owned by this run

The script does not use privileged commands, broad process matching, broad
process kills, or GUI automation.

## Result Semantics

Exit codes map directly to `M14_003_RESULT`:

- `0`: `PASS`
- `1`: `FAIL`
- `2`: `OPT_IN_REQUIRED`
- `3`: `BLOCKED`
- `4`: `TIMEOUT`

The result artifact is:

```text
artifacts/m14-003/result.txt
```

Generated artifacts remain ignored by Git under `artifacts/`.

## Manual Recovery

Use these only after confirming the paths belong to the M14-003 run:

```sh
/bin/launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.hermes.bridge.plist"
rm -rf "$HOME/Applications/Hermes Bridge.app"
rm -f "$HOME/Library/LaunchAgents/com.hermes.bridge.plist"
rm -rf "artifacts/m14-003/runtime"
```

Do not remove real `~/.hermes`, unrelated LaunchAgents, unrelated application
bundles, unrelated logs, or Keychain items.
