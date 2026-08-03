# RC1 Release Checklist

## Local Packaging Readiness

1. Confirm the repository is on the intended RC branch.
2. Run `swift build -c release`.
3. Run `swift test`.
4. Run `swift test --filter HermesReleaseVersionTests`.
5. Run `swift test --filter HermesRC1PackagingTests`.
6. Run `zsh -n Scripts/m14_010_rc1_release.sh`.
7. Run `Scripts/m14_010_rc1_release.sh inspect`.
8. Run `HERMES_M14_010_ACCEPTANCE=YES Scripts/m14_010_rc1_release.sh build-unsigned`.
9. Run `Scripts/m14_010_rc1_release.sh verify`.
10. Confirm `artifacts/m14-010/result.txt` reports `M14_010_RESULT=PASS`.
11. Confirm unsigned output is not described as notarized or production-ready.
12. Run `Scripts/m14_010_rc1_release.sh cleanup`.

## Signed And Notarized Release

1. Confirm Developer ID Application and Developer ID Installer identities are
   available without printing identity names into release evidence.
2. Set `HERMES_RELEASE_APPLICATION_IDENTITY` explicitly.
3. Set `HERMES_RELEASE_INSTALLER_IDENTITY` explicitly.
4. Run `HERMES_M14_010_ACCEPTANCE=YES Scripts/m14_010_rc1_release.sh build-signed`.
5. Set `HERMES_M14_010_NOTARIZE=YES`.
6. Provide either `HERMES_RELEASE_NOTARY_KEYCHAIN_PROFILE` or the explicit App
   Store Connect API key environment inputs.
7. Run `Scripts/m14_010_rc1_release.sh notarize`.
8. Confirm notarization, stapling, and `spctl` assessment are accepted.

## Manual GitHub Release Publication

1. Create tag `v0.1.0-rc.1` only after release evidence is reviewed.
2. Attach the package archive and checksum file manually.
3. Include the release manifest and result summary.
4. State that unsigned artifacts are packaging-readiness artifacts only.
5. Do not claim production readiness or external adoption.
6. Do not mention private `/api/ws` support.

## Rollback

1. Stop using the candidate artifact.
2. Run bundled uninstall tooling for any staged local install.
3. Remove `artifacts/m14-010/` if evidence must be regenerated.
4. Rebuild from source after fixes.
