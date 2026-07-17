# SPK-03 Process-Group Cleanup

This spike validates whether a future HermesProcessSupervisor should launch
Bridge-owned Hermes processes into a dedicated process group and shut down that
verified group instead of terminating only the immediate parent PID.

## Run Read-Only Mode

```sh
Scripts/spikes/spk-03-process-group-cleanup.zsh
```

Read-only mode records macOS version, architecture, shell PID/PGID/SID,
availability of `ps`, `kill`, `swiftc`, `clang`, and Python, and local man-page
availability for process and signal APIs. It does not create test processes or
send signals.

## Run Active Mode

```sh
Scripts/spikes/spk-03-process-group-cleanup.zsh --active-test
```

Active mode compiles a small C helper under `artifacts/spk-03/`, creates marked
parent/child/grandchild trees, records PID/PPID/PGID/SID/start-time/command
identity with `ps`, and sends signals only after identity verification.

## Safety Boundary

The script refuses to signal a PID unless the live process command contains the
unique experiment marker. It refuses to signal a PGID unless every live member
of that group contains the same marker. The cleanup trap is idempotent and uses
only verified experiment-owned PIDs or verified experiment-owned PGIDs.

The script does not use `sudo`, `killall`, `pkill`, process-name termination,
LaunchAgents, launchd state, Keychain, browser data, `~/.hermes`, or unrelated
files.

## Cleanup Algorithm

1. Record parent, child, and grandchild PID files under the run artifact
   directory.
2. Verify each live PID by command marker before remembering it for cleanup.
3. For owned-group scenarios, verify the parent PGID and confirm no
   non-experiment process shares it.
4. Send `SIGTERM` to the verified target PID or negative PGID.
5. Wait for a bounded timeout.
6. Escalate to `SIGKILL` only for the same verified PID or PGID if required.
7. Fail if any marked process remains.

## Selected Ownership Model

Use a dedicated process group for every Bridge-owned Hermes launch. Retain the
parent PID, owned PGID, launch marker or equivalent identity, and process start
identity. During shutdown, verify that the live PID and PGID still match the
launch identity, send `SIGTERM` to the verified owned group, wait for a bounded
interval, then send `SIGKILL` to the same verified group if needed. Separately
detect descendants that escaped into a different session or process group and
handle them only through recorded verified identities.

## Remaining Risks

A descendant can intentionally escape normal process-group cleanup by creating a
new session or process group. Process-group shutdown is still the correct
default ownership model, but escaped descendants require explicit detection,
audit evidence, and narrow cleanup by recorded verified PID when policy allows.

SPK-03 VERDICT: CONDITIONAL GO

Artifacts are written under `artifacts/spk-03/` and are not committed.
