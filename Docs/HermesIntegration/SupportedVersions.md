# Supported Hermes Backend Versions

M9-001 uses an explicit compatibility policy.

- Minimum supported: `0.18.0`
- Maximum tested: `0.19.x`

Classification states:

- `supported`: version is in range and required protocol capabilities are
  present.
- `supportedWithWarnings`: version is in range, but only harmless discovery
  probes are available.
- `unsupportedTooOld`: detected version is below the minimum supported version.
- `unsupportedTooNew`: detected version is newer than the maximum tested
  policy.
- `incompatibleProtocol`: required machine protocol capabilities are missing.
- `executableUnavailable`: no safe executable candidate was found.
- `versionUnknown`: version output could not be parsed.

Version parsing failures never imply compatibility.
