# SPK-03 - Validate Process-Group Cleanup

## Objective

Determine whether HermesProcessSupervisor should own a dedicated process group
for each Bridge-started Hermes process so shutdown can clean child and
descendant processes without signaling unrelated processes.

## Scope

This spike is limited to repository-governance and technical validation. It
does not add Bridge runtime behavior, macOS integration code, or a generic
process execution API.

## Deliverables

- `Scripts/spikes/spk-03-process-group-cleanup.zsh`
- `Spikes/SPK-03-process-group-cleanup/README.md`
- `Spikes/SPK-03-process-group-cleanup/FINDINGS.md`
- `Docs/CodexTasks/SPK-03.md`

## Validation Plan

Run:

```sh
zsh -n Scripts/spikes/spk-03-process-group-cleanup.zsh
Scripts/spikes/spk-03-process-group-cleanup.zsh
Scripts/spikes/spk-03-process-group-cleanup.zsh --active-test
git diff --check
```

Then confirm tracked files do not contain private absolute paths and confirm no
marked experiment processes remain.

## Required Evidence

The active test must prove:

- whether parent-PID-only termination leaves descendants alive;
- whether a dedicated process group can be created and verified;
- whether `SIGTERM` to the verified owned process group cleans normal
  descendants;
- whether bounded `SIGTERM` followed by `SIGKILL` to the same verified owned
  process group cleans SIGTERM-resistant descendants;
- whether a descendant can escape process-group cleanup by creating a new
  session or process group;
- whether cleanup can remain limited to recorded experiment-owned PIDs or PGIDs.

## Completion

SPK-03 is complete when the active test has been executed on the research Mac,
the findings contain actual scenario results, and the selected ownership model
is documented with an explicit verdict.
