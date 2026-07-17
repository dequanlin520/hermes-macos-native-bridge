# SPK-05 File Authorization And FSEvents

SPK-05 validates the file authorization and filesystem event model for the
Hermes macOS Native Bridge. It is a technical validation spike, not product
runtime code.

## Usage

Read-only inspection:

```sh
Scripts/spikes/spk-05-file-authorization-fsevents.zsh
```

Active validation:

```sh
Scripts/spikes/spk-05-file-authorization-fsevents.zsh --active-test
```

Read-only mode does not monitor any directory. It inspects local toolchain and
SDK availability, then compiles narrow Swift probes for FSEvents and bookmark
APIs.

Active mode creates a unique root under `artifacts/spk-05/active/`, generates
temporary Swift helpers, runs an FSEvents monitor only against that generated
root, and writes all logs, sources, binaries, and bookmark data under
`artifacts/spk-05/`.

## Approved-Root Boundary

The active FSEvents helper accepts exactly one positional root path. It
canonicalizes that path and refuses to start unless the root is inside:

```text
artifacts/spk-05/active/
```

The helper records only relative paths beneath the approved root. It does not
read file contents. Absolute host paths are kept out of tracked documentation.

## Generated Operation Scenarios

Active mode exercises:

- Scenario A: create, modify, rename, and delete one generated file.
- Scenario B: create a nested directory, create and modify a nested file,
  rename the directory, and delete the nested tree.
- Scenario C: rename and delete the monitored root itself.
- Scenario D: restart monitoring with the last captured event ID and determine
  whether changes made while stopped are replayed.
- Scenario E: create and resolve test-only bookmark data for the generated
  directory; attempt security-scoped options only when the local API accepts
  them.

## Monitor Cleanup

The script stops monitor processes explicitly, waits for termination, and checks
for residual helper processes. Active mode fails if a residual monitor process
remains after cleanup.

## Selected Authorization Architecture

The recommended architecture is:

- a user-facing app obtains directory authorization through `NSOpenPanel`;
- the app stores a versioned security-scoped bookmark;
- a native Bridge component resolves only allowlisted bookmarks;
- FSEvents monitors only resolved approved roots;
- events expose normalized relative paths and metadata, not file contents;
- a LaunchAgent does not receive arbitrary paths from clients;
- stale bookmarks require explicit reauthorization.

The spike treats ordinary bookmark creation as separate from genuine
security-scoped authorization. Security-scoped production claims require a real
app sandbox, the appropriate entitlements, and a user-selected folder flow.

## Event Normalization Recommendation

Bridge audit events should include:

- approved-root identifier or policy ID;
- normalized relative path;
- event ID;
- event timestamp;
- normalized event kind derived from FSEvent flags;
- directory/file hint where available.

Bridge audit events should not include file contents, unneeded absolute paths,
bookmark blobs, or unrelated filesystem metadata.

FSEvents consumers should deduplicate by event ID, relative path, and normalized
flag set within a short window. Consumers should also tolerate batched delivery,
coalesced updates, and root-level events after root rename or deletion.

## User-Facing App And Entitlement Requirements

FSEvents monitoring of accessible directories can be compiled and run by a
native helper. Durable user-granted access to protected or sandbox-scoped
locations is a separate authorization problem. A LaunchAgent should not accept
arbitrary client-supplied paths as authorization. A user-facing app or helper
with the correct entitlements should mediate folder selection, bookmark
creation, allowlisting, and stale-bookmark reauthorization.
