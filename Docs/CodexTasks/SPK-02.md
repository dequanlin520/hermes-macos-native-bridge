# SPK-02 Codex Task

## Issue

GitHub Issue #4: SPK-02 - Validate LaunchAgent and XPC topology.

## Objective

Produce technical evidence for the macOS LaunchAgent and XPC topology that can
support the Hermes macOS Native Bridge without adding product runtime code.

## Required Deliverables

- `Scripts/spikes/spk-02-launchagent-xpc-topology.zsh`
- `Spikes/SPK-02-launchagent-xpc-topology/README.md`
- `Spikes/SPK-02-launchagent-xpc-topology/FINDINGS.md`

## Safety Boundaries

- The default script mode is read-only.
- `--active-test` runs one isolated temporary LaunchAgent/Mach-service
  experiment from ignored artifacts.
- Do not install a permanent LaunchAgent.
- Do not write to `~/Library/LaunchAgents`.
- Do not modify launchd state except for the uniquely generated SPK-02 label
  during `--active-test`.
- Do not run `sudo`.
- Do not inspect Keychain, browser data, or unrelated user files.
- Keep all generated probes and build outputs under `artifacts/spk-02`.
- Do not implement production Bridge runtime.
- Do not merge the pull request.

## Validation Commands

```sh
zsh -n Scripts/spikes/spk-02-launchagent-xpc-topology.zsh
Scripts/spikes/spk-02-launchagent-xpc-topology.zsh
Scripts/spikes/spk-02-launchagent-xpc-topology.zsh --active-test
git diff --check
```

## Completion Notes

The spike is complete when the read-only and active modes run locally, the
active experiment records a defensible bootstrap/XPC/bootout result, generated
artifacts remain untracked, and `FINDINGS.md` captures the evidence-based
topology verdict.
