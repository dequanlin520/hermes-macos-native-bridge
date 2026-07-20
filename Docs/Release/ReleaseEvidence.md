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

M8-002 local release pipeline evidence is generated with:

```sh
Scripts/integration/m8-002-ci-release-pipeline.zsh
```

The entry point reuses `artifacts/m8-001/result.txt`; it does not rerun M8-001.
It stages the local unsigned/ad-hoc RC under
`artifacts/m8-002/release-candidates/HermesBridge-local-rc`, writes
`artifacts/m8-002/local-validation-report.md`, and writes the final
machine-readable result to `artifacts/m8-002/result.txt`.
