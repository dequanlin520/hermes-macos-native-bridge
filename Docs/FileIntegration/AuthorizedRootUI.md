# Authorized Root UI

## Workflow

`Hermes Bridge.app` exposes authorized-folder management from the menu bar
through the `Authorized Folders` window. The app lists safe root summaries from
the Bridge service and offers:

- Add Folder;
- Refresh Authorization;
- Activate;
- Deactivate;
- Remove;
- Refresh Status.

Removal requires a confirmation dialog. The app has no path text field and no
manual path registration operation.

## NSOpenPanel

Folder selection is user initiated through `NSOpenPanel`.

The production selector configures the panel as:

- `canChooseDirectories = true`;
- `canChooseFiles = false`;
- `allowsMultipleSelection = false`;
- `canCreateDirectories = false`;
- `resolvesAliases = true`.

Panel title, message and action text are explicit and localized. Cancel returns
a neutral result and is not treated as an error. Automated tests use injected
selectors and never open an interactive panel.

## Pre-Registration Checks

Before calling XPC, the app rejects:

- filesystem root `/`;
- the whole user home directory;
- non-directory selections;
- symbolic-link authorization roots;
- bookmarks larger than the XPC payload limit.

The Bridge registry remains the source of truth for duplicate roots and the
configured root policy. Those failures are returned as typed, redacted XPC
errors and mapped to bounded UI messages.

## XPC Handoff

The app creates bookmark data from the selected directory and sends it through
typed authorized-root operations only:

- `listAuthorizedRoots`;
- `registerAuthorizedRoot`;
- `refreshAuthorizedRoot`;
- `deactivateAuthorizedRoot`;
- `reactivateAuthorizedRoot`;
- `removeAuthorizedRoot`;
- `authorizedRootStatus`;
- `fileEventMonitorStatus`.

There is no public generic XPC envelope API in the app layer and no path-string
registration fallback.

## Rendering Boundary

Normal rendering includes only:

- root ID;
- display name;
- active or inactive state;
- stale authorization state;
- security-scope state;
- monitor state;
- last observed event ID;
- rescan-required state;
- safe action availability.

It does not render absolute paths, bookmark bytes, file-event filenames,
backend tokens, prompts, raw internal errors or file contents.

## Validation

`Scripts/integration/m5-003-authorized-root-ui.zsh` builds and signs an
artifact-owned app bundle, validates AppKit/`NSOpenPanel` linkage, runs an
injected artifact-owned folder selection through bookmark creation and typed
XPC, then deactivates, reactivates and removes the root.

Manual validation is available with:

```text
Scripts/integration/m5-003-authorized-root-ui.zsh --manual-nsopenpanel-validation
```

Manual mode may launch the app and requires the tester to choose only the
artifact-owned validation folder.
