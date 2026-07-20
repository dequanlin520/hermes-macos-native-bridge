# GitHub-Hosted Release Rehearsal

M8-003 rehearses the real GitHub Actions CI and unsigned release-candidate
workflows on GitHub-hosted runners.

Run:

```sh
Scripts/integration/m8-003-github-actions-rehearsal.zsh
```

The rehearsal uses `gh` to verify authentication and repository identity,
discovers workflow dispatch support, dispatches `.github/workflows/ci.yml`,
waits for that exact run, dispatches `.github/workflows/release-candidate.yml`
from the branch ref, waits for that exact run, downloads artifacts only from
the captured RC run, and validates the unsigned RC evidence.

Manual RC dispatch on a branch ref is the safe rehearsal path. The
release-candidate workflow publishes a GitHub prerelease only for trusted
`v*-rc.*` tag refs, so the branch-dispatched rehearsal must not publish a
GitHub Release.

Evidence is written only under `artifacts/m8-003`:

- `result.txt`;
- CI and RC run metadata and run URLs;
- downloaded RC artifacts;
- artifact inventory;
- validation report;
- sanitized failure logs only when a workflow fails.

`M8_003_RESULT=CONDITIONAL` is expected when CI succeeds, the unsigned RC
workflow succeeds, artifacts validate, Developer ID signing and notarization
remain unavailable, no GitHub Release is published, and no security or cleanup
failure is detected.
