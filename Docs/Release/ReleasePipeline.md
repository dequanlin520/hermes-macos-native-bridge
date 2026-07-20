# Release Pipeline

M8-002 adds three GitHub Actions workflows:

- `.github/workflows/ci.yml`;
- `.github/workflows/release-candidate.yml`;
- `.github/workflows/release.yml`.

Release-candidate builds run manually or from `v*-rc.*` tags. They build the
app bundle, service, and control CLI, run the M8-001 acceptance harness once,
stage a versioned release root, generate SPDX SBOM evidence, write SHA-256
checksums, generate a release manifest, verify the bundle, upload artifacts,
and publish a GitHub prerelease only for trusted tag events.

When Developer ID credentials are unavailable, the RC artifact is ad-hoc signed
and named with `unsigned-rc`. Its gate result may be `CONDITIONAL`. It must not
be described as notarized or production-ready.

Production releases run only from version tags matching `vX.Y.Z` after an
in-job regex gate, or by manual dispatch with the exact `RELEASE` confirmation
input. Production releases require M8-001 acceptance, Developer ID signing,
hardened runtime, notarization acceptance, staple verification, Gatekeeper
assessment, final checksums, and a `PASS` M8-002 gate result before publication.

GitHub artifact attestations are generated where supported. The workflow does
not claim a SLSA level.

