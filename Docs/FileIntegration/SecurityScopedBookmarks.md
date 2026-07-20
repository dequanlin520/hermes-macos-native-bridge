# Security-Scoped Bookmarks

## Bookmark Creation

The authorized-folder UI attempts to create the strongest explicit bookmark it
can for a user-selected directory. It first attempts `.withSecurityScope` and
falls back to an ordinary bookmark only when the security-scoped bookmark call
is unavailable in the current runtime.

The app records the observed outcome as one of:

- `ordinaryBookmarkCreated`;
- `securityScopedBookmarkCreated`;
- `securityScopeStarted`;
- `securityScopeUnavailable`;
- `staleBookmark`;
- `rejected`.

Bookmark bytes are never logged or displayed by the app.

## Scope Lifecycle

When `startAccessingSecurityScopedResource()` succeeds, the app balances it
with `stopAccessingSecurityScopedResource()` and holds access only while
creating and validating the bookmark. The app does not retain indefinite
app-side access and does not claim that the Bridge service inherited a security
scope unless that is directly proven.

## Runtime Validation Level

M5-003 automated validation runs with local ad-hoc signing and proves the
production UI, bookmark creation path and typed XPC registration flow, but it
does not by itself prove App Sandbox entitlement behavior.

`SECURITY_SCOPED_RUNTIME_PROVEN=yes` is reported only when the local runtime
actually observes `startAccessingSecurityScopedResource()` succeeding during
the integration flow. A passing M5-003 result may still report
`SECURITY_SCOPED_RUNTIME_PROVEN=no`; that means sandbox entitlement proof
remains separate.

M5-004 adds a dedicated sandboxed app entitlement policy and automated
artifact-only validation. The M5-004 run proved:

- embedded App Sandbox entitlement;
- embedded user-selected read/write entitlement;
- no broad filesystem or temporary exception entitlement;
- `.withSecurityScope` bookmark creation;
- typed XPC bookmark persistence into the Bridge registry;
- app restart bookmark resolution;
- service restart bookmark resolution;
- service-side `startAccessingSecurityScopedResource()` success;
- selected-root FSEvents delivery with no sibling-root event delivery.

Because automated mode uses an injected artifact-owned selection, it does not
claim real manual `NSOpenPanel` or TCC user-selection proof. That proof requires
`Scripts/integration/m5-004-sandboxed-bookmark-lifecycle.zsh
--manual-sandbox-bookmark-validation`.

## Privacy Boundary

Security-scoped bookmark handling does not authorize file-content indexing.
The app does not read selected folder contents, render full absolute paths,
emit bookmark bytes, or expose file-event filenames in the authorized-root UI.

## Current Verdict

M5-004 VERDICT: CONDITIONAL GO

The sandboxed ad-hoc app and service handoff are proven locally. Developer ID
signing, notarization and manual user-selection evidence remain future
validation work.
