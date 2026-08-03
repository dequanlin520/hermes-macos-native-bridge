# RC1 Scope

Hermes macOS Native Bridge RC1 is an engineering validation release. It is not
declared production-ready.

## Supported

- native app launch
- menu-bar status
- service connection state
- XPC protocol compatibility
- Hermes executable discovery
- Hermes version discovery
- service-owned isolated Agent start
- Agent readiness and `/api/status` status
- dynamic endpoint ownership
- controlled service restart and reconnect
- app exit without accidental runtime destruction
- exact Bridge-owned Agent shutdown
- diagnostics
- permission status
- audit and security status
- emergency stop
- installation and uninstallation
- Shortcuts/App Intents only for service-owned supported operations

## Unsupported

- request submission for Hermes Agent 0.18.2
- request status for Hermes Agent 0.18.2
- request cancellation for Hermes Agent 0.18.2
- approval response for Hermes Agent 0.18.2
- arbitrary prompts
- arbitrary shell execution
- GUI Computer Use
- browser automation
- arbitrary AppleScript or JXA
- broad process control
- private `/api/ws` assumptions

Unsupported request, cancellation, and approval capabilities must be visible
and deterministic with reason `transport.route-unsupported`.

## Compatibility

- Apple Silicon baseline
- macOS 13+ package baseline, with real-user testing still required per release
  evidence
- Hermes Agent 0.18.2
- XPC protocol version 1.8
- user-scope LaunchAgent installation
- service-owned runtime, endpoint discovery, readiness, and shutdown

## Known Limitations

- Hermes Agent 0.18.2 does not advertise a public request transport.
- Hermes integration is status-only for RC1.
- Signing and notarization status depends on release pipeline credentials.
- External compatibility still requires real user testing.
- The UI must consume typed capability evidence and must not infer support from
  button failures.
