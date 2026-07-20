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

Current automated validation runs with local ad-hoc signing. It proves the
production UI, bookmark creation path and typed XPC registration flow, but it
does not by itself prove App Sandbox entitlement behavior.

`SECURITY_SCOPED_RUNTIME_PROVEN=yes` is reported only when the local runtime
actually observes `startAccessingSecurityScopedResource()` succeeding during
the integration flow. A passing M5-003 result may still report
`SECURITY_SCOPED_RUNTIME_PROVEN=no`; that means sandbox entitlement proof
remains separate.

## Privacy Boundary

Security-scoped bookmark handling does not authorize file-content indexing.
The app does not read selected folder contents, render full absolute paths,
emit bookmark bytes, or expose file-event filenames in the authorized-root UI.

## Next Step

The remaining validation step is a signed, sandboxed app build with explicit
file-access entitlements and a manual `NSOpenPanel` selection, followed by
verification that the Bridge service can resolve the resulting authorization
under the intended release signing model.
