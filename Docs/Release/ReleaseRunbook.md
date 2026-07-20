# Release Runbook

## Release Candidate

1. Push a tag matching `vX.Y.Z-rc.N` or run the Release Candidate workflow
   manually.
2. Confirm CI builds the app, service, and CLI.
3. Confirm the workflow runs `Scripts/integration/m8-001-release-candidate-acceptance.zsh`.
4. Download the release-candidate artifact and inspect
   `ReleaseEvidence/release-gate-summary.env`.
5. Treat `M8_002_RESULT=CONDITIONAL` as unsigned/ad-hoc evidence only.

## GitHub-Hosted Rehearsal

1. Run `Scripts/integration/m8-003-github-actions-rehearsal.zsh` from the
   rehearsal branch.
2. Confirm `artifacts/m8-003/result.txt` reports `M8_003_RESULT=CONDITIONAL`
   or `PASS`.
3. Confirm the captured RC run was branch-dispatched and no GitHub Release was
   created.
4. Use `Docs/Release/GitHubHostedRehearsal.md` for the evidence inventory and
   expected unsigned/ad-hoc result.

## Production Release

1. Configure the Developer ID and notarization secrets documented in
   `Docs/Release/GitHubSecrets.md`.
2. Push an exact production tag matching `vX.Y.Z`, or manually dispatch the
   Release workflow with `confirmation=RELEASE`.
3. Confirm `DEVELOPER_ID_SIGNED=yes`, `NOTARIZATION_ACCEPTED=yes`,
   `STAPLE_VERIFIED=yes`, `GATEKEEPER_VERIFIED=yes`, and
   `M8_002_RESULT=PASS`.
4. Publish only the artifact produced by the successful production workflow.

If any production signing, notarization, staple, Gatekeeper, checksum, manifest,
or M8-001 acceptance gate fails, stop before publication.
