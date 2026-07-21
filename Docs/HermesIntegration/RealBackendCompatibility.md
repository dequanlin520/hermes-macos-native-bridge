# Real Backend Compatibility

M9-001 validates Hermes Bridge against a real installed Hermes executable
without using the user's normal Hermes profile.

The compatibility layer records only safe fields:

- executable availability;
- detected version;
- compatibility state;
- normalized capability summary;
- SHA-256 checksum prefix;
- code-signing classification;
- last probe timestamp;
- remediation code.

Absolute executable paths are not exposed by default. The discovery boundary
accepts only an explicit configured path, PATH resolution for `hermes`, and
documented package-manager or local development locations. It rejects
directories, non-executable files, and symlinks that resolve outside an allowed
executable root.

Supported harmless probes are version/help output and isolated startup
diagnostics. Protocol, capability, missing-credential, and cancellation probes
must be reported as `not_supported` when the installed Hermes executable does
not expose a supported machine protocol.

Run the local evidence script with:

```sh
Scripts/integration/m9-001-real-hermes-compatibility.zsh
```

Evidence is written under `artifacts/m9-001`.
