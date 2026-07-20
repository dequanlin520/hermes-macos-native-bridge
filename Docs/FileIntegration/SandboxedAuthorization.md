# Sandboxed Authorization

## Entitlement Policy

`Hermes Bridge.app` has a dedicated sandbox entitlement file:

```text
Packaging/Entitlements/HermesBridgeApp.entitlements
```

The app entitlement policy is:

- `com.apple.security.app-sandbox = true`
- `com.apple.security.files.user-selected.read-write = true`

No broad filesystem, temporary exception, home-relative, downloads, documents,
Full Disk Access, Apple Events, application group, get-task-allow, network or
Mach lookup entitlement is enabled for the app in M5-004.

The Bridge service entitlement policy remains separate. The current
per-user service executable is not App Sandbox-enabled and keeps the existing
empty service entitlement policy.

## Authorization Model

Directory authorization starts only from app UI user selection. The production
selector uses `NSOpenPanel` with directory-only, single-selection settings.
The app creates bookmark data with `.withSecurityScope`, starts access only
long enough to create and validate the bookmark, sends the bookmark bytes over
typed XPC, and then balances any app-side scope with
`stopAccessingSecurityScopedResource()`.

The app does not retain perpetual app-side scope. Refresh requires explicit
reselection and fresh bookmark data. The UI has no arbitrary path entry and no
path-string registration fallback.

## App-To-Service Handoff

M5-004 adds a typed XPC resolution result for the service:

- resolved root ID;
- resolution status;
- stale state;
- whether service-side security scope started;
- whether the resolved URL matches the authorized root stored by the registry.

Automated validation on the research Mac showed that the non-sandboxed
file-backed Bridge fixture can resolve the app-created bookmark after service
restart and that `startAccessingSecurityScopedResource()` succeeds in the
service fixture.

This proves the current local ad-hoc architecture can consume the bookmark in
the test environment. It does not yet prove release Developer ID, notarized, or
manual TCC user-selection behavior.

## M5-004 Automated Evidence

`Scripts/integration/m5-004-sandboxed-bookmark-lifecycle.zsh` builds an
artifact-owned sandboxed app bundle, signs it ad-hoc with explicit app
entitlements, verifies embedded entitlements and App Intents metadata, and runs
an artifact-only fixture under `artifacts/m5-004`.

The automated run observed:

```text
SANDBOXED_APP_BUILD_PASSED=yes
APP_SANDBOX_ENTITLEMENT_PRESENT=yes
USER_SELECTED_RW_ENTITLEMENT_PRESENT=yes
BROAD_FILESYSTEM_ENTITLEMENT_PRESENT=no
APP_INTENTS_METADATA_PRESENT=yes
SECURITY_SCOPED_BOOKMARK_CREATED=yes
BOOKMARK_PERSISTED_OVER_XPC=yes
APP_RESTART_RESOLUTION_PASSED=yes
SERVICE_RESTART_RESOLUTION_PASSED=yes
SERVICE_SECURITY_SCOPE_STARTED=yes
AUTHORIZED_ROOT_EVENT_OBSERVED=yes
OUTSIDE_ROOT_EVENT_OBSERVED=no
BOOKMARK_BYTES_EXPOSED=no
RESIDUAL_APP_PROCESS=no
RESIDUAL_MONITOR_PROCESS=no
M5_004_RESULT=PASS
M5-004 VERDICT: CONDITIONAL GO
```

The result is conditional because automated mode uses an injected
artifact-owned selection and does not claim real manual `NSOpenPanel` or TCC
user-selection proof.

## Manual Mode

Manual validation is explicit:

```sh
Scripts/integration/m5-004-sandboxed-bookmark-lifecycle.zsh \
  --manual-sandbox-bookmark-validation
```

Manual mode launches only the artifact-owned sandboxed app and instructs the
tester to select exactly `artifacts/m5-004/selected-root`. It prepares an
unselected sibling `outside-root` only to verify that outside-root data is not
used or delivered.

## Verdict

M5-004 VERDICT: CONDITIONAL GO

The sandboxed app entitlement policy, sandboxed bundle, bookmark creation,
XPC persistence, app restart resolution, service restart resolution,
service-side scope start, selected-root FSEvents observation and sibling-root
non-leakage are proven in automated artifact-only validation. Real manual
`NSOpenPanel` selection evidence and release signing/notarization remain
separate validation work.
