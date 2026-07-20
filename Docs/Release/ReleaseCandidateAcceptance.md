# Release Candidate Acceptance

M8-001 defines the release-candidate acceptance harness for Hermes macOS Native
Bridge. Run it from the repository root:

```zsh
Scripts/integration/m8-001-release-candidate-acceptance.zsh
```

The harness owns `artifacts/m8-001` and creates a unique LaunchAgent label of
the form `com.hermes.bridge.test.m8-001.<run-id>`. It builds the package
products, launches the real service through launchd, connects through the
versioned XPC client, and drives the request, authorization, event, policy,
audit, emergency-stop, resume, upgrade, rollback, SBOM, checksum, manifest, and
cleanup gates.

The only fake product dependency is the artifact-owned Hermes backend created
inside the run root. It accepts the fixed safe serve argument shape used by
`HermesProcessSupervisor` and binds only to `127.0.0.1`.

M8-002 integrates this harness into release-candidate and production workflows.
The harness is invoked once per release workflow run and its
`artifacts/m8-001/result.txt` file is consumed by
`Scripts/release/generate-release-manifest.zsh`. Release packaging must not
duplicate the functional acceptance logic.
