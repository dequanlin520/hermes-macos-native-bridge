# Isolated Backend Testing

M9-001 real backend testing uses only artifact-owned roots under:

```text
artifacts/m9-001/runtime
```

The integration environment sets:

- `HOME=artifacts/m9-001/runtime/home`
- `XDG_CONFIG_HOME=artifacts/m9-001/runtime/xdg-config`
- `XDG_CACHE_HOME=artifacts/m9-001/runtime/xdg-cache`
- `XDG_STATE_HOME=artifacts/m9-001/runtime/xdg-state`
- `TMPDIR=artifacts/m9-001/runtime/tmp`

The test must not read real `~/.hermes` contents, Keychain credentials, browser
sessions, shell startup files, production tokens, Documents, or Desktop.

Before and after the probe, the script fingerprints only real profile directory
metadata. It does not read profile file contents. Process cleanup is limited to
the exact tracked PID/PGID. `killall`, `pkill`, and process-name cleanup are not
used.
