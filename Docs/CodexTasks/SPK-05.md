# SPK-05 — Validate File Authorization And FSEvents

## Purpose

Validate the macOS file authorization and filesystem event model needed by the
Hermes macOS Native Bridge without adding product runtime behavior.

This spike must produce executable evidence for monitoring explicitly approved
directories, normalizing event paths, enforcing approved-root boundaries, and
distinguishing ordinary bookmark support from genuine security-scoped
authorization.

## Scope

SPK-05 is limited to temporary research assets under:

```text
artifacts/spk-05/
```

The spike script may:

- compile temporary Swift helpers;
- create, modify, rename, and delete generated test files under the active
  artifact tree;
- run an FSEvents monitor only against the generated active test root;
- create test-only bookmark data for the generated active test root;
- write logs and generated source under `artifacts/spk-05/`.

The spike script must not:

- monitor the home directory or unrelated folders;
- inspect unrelated user files;
- request Full Disk Access;
- use `sudo`;
- install permanent LaunchAgents;
- create a generic execution or filesystem access API;
- commit generated artifacts, binaries, logs, or bookmark data.

## Required Commands

```sh
zsh -n Scripts/spikes/spk-05-file-authorization-fsevents.zsh
Scripts/spikes/spk-05-file-authorization-fsevents.zsh
Scripts/spikes/spk-05-file-authorization-fsevents.zsh --active-test
git diff --check
```

After active validation, run a tracked-file private-path scan and confirm no
residual monitor process remains.

## Required Evidence

The read-only mode records:

- macOS version and architecture;
- Swift and Xcode toolchain availability;
- CoreServices/FSEvents compile availability;
- Foundation bookmark API compile availability;
- availability of `codesign`, `plutil`, and `launchctl`;
- local SDK evidence for app sandbox and file-access entitlement concepts.

The active mode records:

- monitor startup and approved root;
- event IDs, timestamps, flags, and sanitized relative paths;
- file create, modify, rename, and delete behavior;
- recursive descendant behavior;
- root rename and deletion behavior;
- batching, duplicate, latency, and coalescing observations;
- restart behavior using a captured event ID where supported;
- ordinary bookmark creation and resolution;
- security-scoped bookmark attempts only where supported by the context.

## Validation Questions

1. Can a native Swift helper monitor only an explicitly supplied directory
   using FSEvents?
2. Which event flags and path semantics are observed for file lifecycle,
   directory lifecycle, and recursive descendant changes?
3. What latency and coalescing behavior are observed?
4. Are duplicate or batched events emitted?
5. Can event monitoring remain limited to an approved root?
6. Can paths outside the approved root be rejected?
7. What happens when the approved directory is moved, renamed, or deleted?
8. What happens after monitor restart?
9. Can a stored bookmark be created and resolved on this host?
10. Which parts require an app sandbox, entitlement, or user-selected folder?
11. Can a LaunchAgent directly reuse user-granted authorization, or must an
    app/helper mediate authorization?
12. What data may be safely included in audit events without exposing private
    file contents or unnecessary absolute paths?

## Architecture Under Evaluation

The spike evaluates this architecture:

- a user-facing app obtains directory authorization through `NSOpenPanel`;
- the app stores a versioned security-scoped bookmark;
- a native Bridge component resolves only allowlisted bookmarks;
- FSEvents monitors only resolved approved roots;
- events expose normalized relative paths and metadata, not file contents;
- a LaunchAgent does not receive arbitrary paths from clients;
- stale bookmarks require explicit reauthorization.

## Completion Criteria

The spike is complete when:

- the required script and documentation are present;
- read-only and active modes have been executed on the dedicated research Mac;
- `FINDINGS.md` contains concrete command output summaries and a single
  `SPK-05 VERDICT`;
- generated artifacts remain untracked under `artifacts/spk-05/`;
- a commit, push, issue update, and pull request are created as requested.
