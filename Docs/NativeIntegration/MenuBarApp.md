# Menu Bar App

## App

`Hermes Bridge.app` is a minimal SwiftUI menu bar application. The fixed bundle
identifier is:

```text
com.hermes.bridge.app
```

The deployment target is macOS 13.0. `LSUIElement` is enabled, so the app is a
menu bar app and does not show a Dock icon.

## Architecture

The app target imports `HermesAppIntents` so the bundle hosts the App Intent
types and `HermesAppShortcutsProvider`. The operational UI is backed by
`HermesBridgeMenuBarViewModel`, which uses narrow typed adapters:

- service status/start/restart through `HermesBridgeServiceManager`;
- protocol, capabilities, and binding discovery through `HermesBridgeXPC`;
- recent request summaries through the existing redacted request lister;
- doctor through the existing doctor checker.

The menu app does not run shell commands, expose a generic XPC data interface,
install the service automatically, launch real Hermes by itself, or offer
destructive uninstall/release-management controls.

## Features

The first menu surface displays:

- Bridge status;
- installed/running/healthy state;
- protocol compatibility and version;
- capability names;
- enabled binding count;
- recent safe request summaries;
- network online/offline state;
- system-event monitor active state;
- recent safe system-event summaries;
- enabled event-policy count;
- event-policy paused/running state;
- recent safe event-policy decisions;
- service degradation state.

It offers only:

- Refresh;
- Start Service;
- Restart Service;
- Run Doctor;
- View Permissions;
- Run Permissions Doctor;
- Open exact System Settings panes after an explicit click;
- Latest Audit Events;
- Export Audit Log;
- Authorized Folders;
- Pause Policies;
- Resume Policies;
- Dry Run a normalized test event;
- Enable or disable an existing policy;
- Open Shortcuts;
- Quit.

All displayed request values are bounded and redacted. Prompts, backend tokens,
raw result bodies, process identifiers, and private paths are not displayed.

Permission views render only permission kind, state, detail code and fixed
remediation code. Opening System Settings uses the fixed URLs documented in
`Docs/Security/PermissionsDoctor.md` and happens only after a user click.

Audit views render only recent safe structured events: event ID, timestamp,
kind, actor, outcome, reason code and safe correlation ID. The app does not
provide a raw log viewer, arbitrary filesystem browser or generic file-read
operation. Audit export requires explicit user folder selection and writes a
redacted archive with manifest and checksum.

System-event views render only recent safe structured summaries: event ID,
timestamp, fixed kind, source, safe application bundle identifier/name, network
classification, service-health classification and bounded reason code. The app
does not provide a raw system log viewer and does not display executable paths,
PIDs, window titles, document titles, URLs, clipboard, keystrokes, Prompts or
backend tokens.

Policy views render only enabled policy count, paused/running state and recent
safe decisions containing policy ID, event kind, action kind, decision and
reason code. The menu bar can pause/resume policies, dry-run a normalized event
and enable/disable an existing policy through typed XPC operations. It is not a
generic workflow editor and does not expose policy JSON editing, arbitrary
actions, scripts, shell commands, AppleScript, executable paths, prompt bodies,
raw events, clipboard content or window content.

Audit integrity views may show signing availability, an active signer
fingerprint prefix, signed and unsigned segment counts, integrity state, last
verification timestamp and fixed remediation codes. They never display private
Keychain references, complete signatures, private-key bytes, prompts, backend
tokens, bookmark bytes, file contents or private absolute paths.

## Lifecycle

At launch the view model refreshes service status, XPC protocol version,
capabilities, enabled binding summaries, and recent safe request summaries. An
explicit refresh command repeats the same sequence. Refresh tasks are cancelled
when requested by the app model during termination.

If the service is unavailable, the app shows an unavailable state and offers
Start Service through the service manager only. It does not auto-install.

## Authorized Folders

The `Authorized Folders` window is reachable from the menu bar. It lists safe
authorized-root summaries and exposes Add Folder, Refresh Authorization,
Activate, Deactivate, Remove and Refresh Status.

Folder selection uses `NSOpenPanel` with directory-only, single-selection,
alias-resolving configuration. The app creates bookmark data from the selected
directory and sends it through the typed `HermesBridgeXPCClient` authorized-root
operations. There is no path text field, generic filesystem access, arbitrary
XPC data envelope, automatic indexing or file-content reading.

The window renders display name, root ID, active state, stale authorization,
security-scope state, monitor active/inactive state, rescan-required state and
last observed event cursor metadata. It does not render absolute paths,
bookmark bytes, file-event filenames, prompts, backend tokens, file contents or
raw internal errors. Removal requires confirmation.

## Signing And Validation

`Scripts/integration/m4-002-app-bundle-shortcuts.zsh` builds the app target,
assembles an artifact-owned `Hermes Bridge.app`, ad-hoc signs it, verifies the
signature and `Info.plist`, validates App Intents metadata at the strongest
available local level, and performs an in-process binding-discovery round trip.

The current validation level is local ad-hoc signing. Developer ID signing,
hardened runtime release signing, notarization, and installer indexing remain
future release work.

M5-003 adds `Scripts/integration/m5-003-authorized-root-ui.zsh`, which validates
the authorized-root UI build, AppKit/`NSOpenPanel` linkage, injected
artifact-owned bookmark creation, typed XPC registration, root listing,
deactivate/reactivate/remove, privacy scans and residual app-process cleanup.
The script also provides `--manual-nsopenpanel-validation` for explicit manual
panel validation. Successful ordinary bookmark registration does not by itself
prove App Sandbox security-scoped entitlement behavior.

M5-004 adds `Scripts/integration/m5-004-sandboxed-bookmark-lifecycle.zsh`, which
builds an artifact-owned sandboxed `Hermes Bridge.app`, ad-hoc signs it with
`Packaging/Entitlements/HermesBridgeApp.entitlements`, verifies embedded
entitlements and App Intents metadata, then validates security-scoped bookmark
creation, typed XPC persistence, app/service restart resolution and selected
root-only FSEvents observation. The automated run reported `M5_004_RESULT=PASS`
and `M5-004 VERDICT: CONDITIONAL GO` because real manual `NSOpenPanel`/TCC
selection evidence is still separate.

The app entitlement policy is limited to:

```text
com.apple.security.app-sandbox = true
com.apple.security.files.user-selected.read-write = true
```

No broad filesystem, temporary exception, Apple Events, application group,
network, Mach lookup, get-task-allow or library-validation-disabling
entitlement is enabled for the menu bar app in M5-004.

## Shortcuts Discovery

The integration script copies the app only to an artifact-owned location by
default. It performs an explicit local install and queries Shortcuts only when
called with `--install-local-for-shortcuts-check`. Do not claim Shortcuts
runtime indexing unless that flag is used and the script reports:

```text
SHORTCUTS_RUNTIME_DISCOVERY_PROVEN=yes
```

## Security Boundary

The app preserves the Bridge privacy boundary. It does not expose executable
paths, process arguments, endpoints, JSON-RPC methods, environment variables,
backend tokens, Prompts, result bodies, result locators, arbitrary filesystem
paths, arbitrary AppleScript/JXA/shell execution, GUI control, browser
automation, or remote-control APIs.

Audit and permissions UI follows the same boundary: no Prompt, token, bookmark
bytes, file contents, absolute authorized-root paths, raw stdout/stderr,
arbitrary environment or raw exception text are displayed.
