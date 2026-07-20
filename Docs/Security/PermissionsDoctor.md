# Permissions Doctor

The Permissions Doctor reports typed permission and configuration state without
repairing anything and without silently triggering macOS permission dialogs.

## Checks

The report contains one check for each `HermesPermissionKind`:

- `appSandbox`
- `userSelectedFiles`
- `accessibility`
- `automation`
- `screenRecording`
- `launchAgent`
- `machService`
- `securityScopedBookmarks`
- `authorizedFileRoots`
- `notifications`
- `appIntentMetadata`
- `signing`
- `hardenedRuntime`
- `notarization`

The report may also carry a bounded audit-integrity summary with state,
verified segment count, verified event count, safe issue codes and verification
timestamp. This summary is diagnostic evidence, not a permission grant.

Each check returns a `HermesPermissionState`:

- `granted`
- `denied`
- `restricted`
- `notDetermined`
- `unavailable`
- `notApplicable`
- `misconfigured`
- `unknown`

## Non-Prompting Behavior

Diagnostics use public APIs only:

- Accessibility uses `AXIsProcessTrusted`.
- Screen Recording uses `CGPreflightScreenCaptureAccess` where available.
- Signing, sandbox and entitlements use code-signing metadata for the signed
  executable or app bundle.
- LaunchAgent and Mach service evidence comes from the existing fixed service
  manager and typed XPC checks.
- Authorized-root and security-scoped bookmark evidence comes from typed Bridge
  state.

The Doctor does not read private TCC databases, does not modify privacy
settings, does not request permission during ordinary diagnostics, and does not
run generic shell, AppleScript or JXA remediation.

Automation is reported from documented state evidence only. When there is no
non-prompting public probe, it is reported as `notDetermined`.

Audit integrity diagnostics are read-only. They do not repair or rewrite audit
history, do not expose raw corrupt records and do not include private paths.

## Remediation

Remediation uses fixed codes:

- `openAccessibilitySettings`
- `openScreenRecordingSettings`
- `openAutomationSettings`
- `openNotificationsSettings`
- `reinstallService`
- `restartService`
- `refreshFolderAuthorization`
- `rebuildSignedApp`
- `configureDeveloperID`
- `notarizeRelease`

System Settings remediation opens only fixed documented URL schemes after an
explicit user click. The Bridge never changes a permission automatically.

## Limitations

Notarization is reported as `unavailable` in local diagnostics unless release
notarization evidence is supplied by future packaging metadata. Notification
status is not queried silently. Automation status cannot be fully enumerated
without user-mediated system state.

## Next Hardening

Future work should add release notarization ticket evidence, Developer ID
release build metadata, richer notification diagnostics, production manifest
signing configuration, and manual validation for user-facing permission flows.
