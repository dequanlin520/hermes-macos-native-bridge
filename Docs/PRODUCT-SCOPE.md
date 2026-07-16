# Product Scope

## Product definition

Hermes macOS Native Bridge is the native macOS runtime control layer, system
event ingress, and controlled native action egress for Hermes Agent.

## V0.1 capabilities

1. Hermes lifecycle and health.
2. Siri and App Intents ingress.
3. Approved Shortcuts egress.
4. Network, sleep, application, file and Hermes service events.
5. Permissions Doctor.
6. Native menu bar.
7. Audit, diagnostics and emergency stop.

## Security boundary

Hermes may request only actions represented by an enabled Shortcut Binding.

The Bridge must not expose:

- arbitrary commands;
- arbitrary shell;
- arbitrary AppleScript;
- GUI control;
- browser automation;
- remote unauthenticated control.

## Development sequence

1. Repository governance.
2. Six technical spikes.
3. Runtime foundation.
4. Hermes lifecycle.
5. Shortcuts Bridge.
6. Event Bridge.
7. Doctor and hardening.
8. Preview release.
