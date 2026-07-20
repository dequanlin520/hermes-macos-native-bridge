# Authorized File Roots

## Authorization Model

Hermes file access starts from an explicitly authorized directory bookmark. The
Bridge does not accept arbitrary paths as authorization and does not expose a
generic filesystem API. Production UI is expected to collect user authorization
with `NSOpenPanel`, create bookmark data, and pass only that bookmark data into
the authorized-root registry.

The registry resolves bookmark data through Foundation, standardizes and
resolves the resulting URL, validates the root against policy, then stores a
versioned record. Tests use ordinary bookmarks created for temporary
directories only. They do not contain real user authorization data.

## Ordinary And Security-Scoped Bookmarks

Ordinary bookmarks are durable URL references. Security-scoped bookmarks are a
separate sandbox authorization mechanism and require a signed, sandboxed app,
appropriate file-access entitlements, and a user-selected folder flow.

`HermesBookmarkAuthorizationResolution` preserves that distinction:

- `resolved`: bookmark resolved without stale data.
- `resolvedStale`: bookmark resolved but Foundation marked it stale.
- `securityScopeStarted`: `startAccessingSecurityScopedResource()` succeeded in
  the current runtime.
- `securityScopeUnavailable`: the bookmark resolved, but a security scope was
  not started.
- `rejected`: the bookmark was malformed or failed root policy checks.

Swift Package tests may observe local API behavior, but they must not claim that
security-scoped entitlement access has been proven.

## Registry Schema

`HermesAuthorizedRootRecord` schema version `1` stores only safe metadata:

- schema version;
- generated `HermesAuthorizedRootID`;
- bounded display name;
- resolved standardized root URL;
- bookmark data;
- bookmark creation and update timestamps;
- stale-bookmark flag;
- active or inactive state;
- last observed FSEvent ID;
- revision.

Records do not store file contents, prompts, tokens, file samples, or indexing
state. Public descriptions omit private absolute paths.

## Root Restrictions

The registry rejects:

- filesystem root `/`;
- the current user home directory as a whole;
- non-directory targets;
- symlink authorization roots;
- roots outside the configured policy parents;
- duplicate resolved roots.

The file-backed registry also rejects symlinked registry storage roots,
escaping record paths, corrupt records, unsupported future schema versions,
oversized bookmark data, oversized records, and root-count overflow.

## Registry Operations

`HermesAuthorizedRootRegistry` exposes typed operations only:

- register bookmark;
- resolve root;
- read root;
- list roots;
- deactivate root;
- reactivate root after fresh authorization;
- update event cursor;
- mark stale;
- remove root.

There is no generic key-value store and no operation that accepts an arbitrary
path as authorization.

## File-Backed Storage

`FileBackedHermesAuthorizedRootRegistry` is actor-isolated. Callers supply one
Bridge-owned registry directory and one root policy. Persistence uses one JSON
record per root, restrictive permissions, temporary files, atomic rename, and
directory fsync. Filenames are derived only from generated root IDs.

The storage format is intentionally narrow so future XPC APIs can expose safe
summaries without exposing bookmark data or private paths.
