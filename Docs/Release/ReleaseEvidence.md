# Release Evidence

M8-001 evidence is persisted under `artifacts/m8-001`:

- `result.txt`
- `release-candidate-manifest.json`
- `sbom.spdx.json`
- `checksums.txt`
- `acceptance-report.md`
- sanitized logs
- `cleanup-report.json`

Evidence must not contain home-directory paths, usernames, credentials, tokens,
prompt bodies, or private file paths. Public manifests should use
`artifacts/m8-001` relative references for artifact-owned files.
