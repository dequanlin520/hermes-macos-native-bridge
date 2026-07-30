# M14-002 Real User-Session Installation Acceptance

## Prerequisites

Run this only from a macOS login session for the current user. The host needs
the Swift toolchain, the production release targets must build locally, and the
current user must have no existing Hermes Bridge user install.

Signing and notarization credentials are not required. Hermes Agent may be
unavailable.

## Opt-In Command

The script is non-destructive unless the exact opt-in value is present:

```sh
HERMES_REAL_USER_INSTALL_ACCEPTANCE=YES Scripts/m14_002_real_user_install_acceptance.sh
```

Without that value, the script performs preflight checks, writes
`artifacts/m14-002/result.txt`, reports `M14_002_RESULT=OPT_IN_REQUIRED`, and
does not install, bootstrap, launch, stop, or remove anything.

Exit codes are derived from the final `M14_002_RESULT` after cleanup and
environment-restoration checks:

- `0`: `M14_002_RESULT=PASS`
- `1`: `M14_002_RESULT=FAIL`
- `2`: `M14_002_RESULT=OPT_IN_REQUIRED`
- `3`: `M14_002_RESULT=BLOCKED`

## Real Agent Quiescence

If a real Hermes Agent process group is writing cron, heartbeat, or account
synchronization state during M14-002, use the quiescence helper with an
explicitly selected root Hermes PID:

```sh
HERMES_QUIESCE_REAL_AGENT=YES Scripts/m14_002_quiesce_real_hermes.zsh <root-hermes-pid>
```

The helper verifies that the root PID belongs to the current user, records the
root process group's exact current-user members, displays PID, PPID, PGID, and
executable basename, sends `SIGSTOP` only to those recorded PIDs, runs M14-002
acceptance once, then sends `SIGCONT` to the same recorded PIDs on success,
failure, interrupt, or hangup. It preserves the acceptance exit code.

## User-Scoped Paths

The acceptance run is limited to project-owned current-user locations:

- App target: `~/Applications/Hermes Bridge.app`
- LaunchAgent target: `~/Library/LaunchAgents/com.hermes.bridge.plist`
- Bridge service support created by the production lifecycle tool:
  `~/Library/Application Support/HermesBridge`
- Isolated service runtime for this run:
  `artifacts/m14-002/runtime/`

The production LaunchAgent label is `com.hermes.bridge`, and the production
Mach service is `com.hermes.bridge.xpc`. The script uses the current
`gui/$UID` launchctl domain.

The isolated runtime configuration is written under
`artifacts/m14-002/runtime/HermesBridge/configuration.json`; the script does
not read or write real `~/.hermes`.

## Collision Behavior

Before any mutation, the script checks for:

- An existing app at `~/Applications/Hermes Bridge.app`
- An existing LaunchAgent plist at
  `~/Library/LaunchAgents/com.hermes.bridge.plist`
- A loaded `gui/$UID/com.hermes.bridge` launchd service
- Existing project-owned service support at
  `~/Library/Application Support/HermesBridge`
- Existing real Hermes home metadata at `~/.hermes`
- Exact project-owned app or service process paths

If any are present, the run stops with:

```text
BLOCKED_BY_PREEXISTING_INSTALL=yes
M14_002_RESULT=BLOCKED
```

The script does not overwrite, unload, back up, move, or delete pre-existing
content.

## Lifecycle Sequence

With opt-in and no collision, the script validates:

1. Build the production Release app and service once.
2. Install the app to `~/Applications/Hermes Bridge.app`.
3. Install the production service with the production lifecycle tool.
4. Install the production LaunchAgent plist at the current user's LaunchAgents
   path, with `HERMES_BRIDGE_SERVICE_CONFIG` pointing to the isolated runtime.
5. Bootstrap `com.hermes.bridge` in the current `gui/$UID` domain.
6. Launch the installed app through `open`.
7. Verify the exact installed app executable is running.
8. Verify the service is running.
9. Verify XPC protocol `1.8`.
10. Verify service runtime ownership and that the app does not own runtime.
11. Restart the service through project lifecycle control.
12. Verify reconnect after restart.
13. Terminate only the exact acceptance-owned app PID and verify the service
    remains running.
14. Relaunch the app and reconnect.
15. Stop and cleanly start the service.
16. Verify the final reconnect.
17. Uninstall, cleanup, and residue-check.

All waits are bounded. The script does not use privileged commands, broad
process termination, or GUI automation.

## Cleanup Guarantees

Cleanup runs on success, failure, timeout, or interrupt. It only attempts to
remove resources that this exact run installed:

- The exact acceptance-owned app PID
- The exact `com.hermes.bridge` service in the current `gui/$UID` domain
- The app target if this run installed it
- The LaunchAgent plist if this run installed it
- Service support installed by this run through the production lifecycle tool
- `artifacts/m14-002/runtime/`

It does not remove unrelated apps, unrelated LaunchAgents, unrelated logs, real
`~/.hermes`, Keychain entries, or browser data.

## Agent Unavailable

Hermes Agent discovery uses the existing service-owned discovery path and
reports one of:

- `available`
- `unavailable`
- `incompatible`
- `unknown`

If the Agent is unavailable, incompatible, or unknown, Agent-dependent checks
are reported as:

```text
AGENT_DEPENDENT_CHECK=skip
```

That alone does not fail installation, XPC, lifecycle, cleanup, or residue
checks.

## Expected Result States

`artifacts/m14-002/result.txt` uses a stable, single-entry key schema.

- `M14_002_RESULT=OPT_IN_REQUIRED`: no exact opt-in was provided.
- `M14_002_RESULT=BLOCKED`: a pre-existing install, configuration, loaded
  label, or project-owned process was detected before mutation.
- `M14_002_RESULT=FAIL`: a required installation, lifecycle, cleanup, or
  residue check failed.
- `M14_002_RESULT=PASS`: real installation, XPC lifecycle, cleanup, and
  environment restoration all passed.

Generated artifacts remain ignored by Git under `artifacts/`.

## Manual Recovery

Use this only for a failed opt-in run after confirming the paths belong to the
M14-002 acceptance run:

```sh
.build/release/HermesBridgeControl stop --timeout 10
/bin/launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.hermes.bridge.plist"
.build/release/HermesBridgeServiceLifecycle uninstall --install-user-service
rm -rf "$HOME/Applications/Hermes Bridge.app"
rm -f "$HOME/Library/LaunchAgents/com.hermes.bridge.plist"
rm -rf "artifacts/m14-002/runtime"
```

Do not remove real `~/.hermes`, unrelated LaunchAgents, unrelated application
bundles, unrelated logs, or Keychain items.
