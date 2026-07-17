# SPK-04 — Validate Shortcuts Execution From LaunchAgent

## Scope

SPK-04 validates whether a process launched in the current user's launchd GUI
domain can safely invoke the macOS Shortcuts CLI. The spike does not add
Bridge runtime behavior.

## Validation Questions

1. Is `/usr/bin/shortcuts` available?
2. Which commands and flags are exposed by the installed CLI help?
3. Can a temporary user-domain LaunchAgent execute `/usr/bin/shortcuts`?
4. Does the LaunchAgent inherit enough GUI/user session context?
5. Which environment values are visible from the LaunchAgent?
6. Which PATH should production use?
7. How do missing shortcuts, timeout handling, nonzero exits, stdout and stderr
   behave?
8. Can execution stay restricted to an allowlisted binding?
9. Which audit fields can be recorded without logging private input or output?

## Deliverables

- `Scripts/spikes/spk-04-shortcuts-from-launchagent.zsh`
- `Spikes/SPK-04-shortcuts-from-launchagent/README.md`
- `Spikes/SPK-04-shortcuts-from-launchagent/FINDINGS.md`

Generated evidence is written under `artifacts/spk-04/` and is intentionally
not committed.

## Execution

Required validation commands:

```sh
zsh -n Scripts/spikes/spk-04-shortcuts-from-launchagent.zsh
Scripts/spikes/spk-04-shortcuts-from-launchagent.zsh
Scripts/spikes/spk-04-shortcuts-from-launchagent.zsh --active-test
git diff --check
```

Additional checks:

- scan tracked files for private absolute paths before commit;
- verify the generated LaunchAgent label is no longer visible with
  `launchctl print gui/<uid>/<label>`;
- verify the recorded helper PID is no longer running.

## Safety Boundary

The spike may create a temporary uniquely named LaunchAgent from a plist under
`artifacts/spk-04/active/<label>/`. It must bootstrap only into `gui/<uid>` and
must boot out the same generated plist.

The script must not:

- use `sudo`;
- write to `~/Library/LaunchAgents`;
- modify permanent LaunchAgents;
- execute arbitrary existing user shortcuts;
- enumerate or publish unrelated personal shortcut names;
- use AppleScript, JXA or GUI automation;
- use `killall` or `pkill`;
- leave a service or process running;
- commit generated artifacts.

## Completion Criteria

SPK-04 is complete when the script records read-only evidence, active
LaunchAgent evidence, fixture availability, cleanup evidence and a supported
verdict in `FINDINGS.md`.
