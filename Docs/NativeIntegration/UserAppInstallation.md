# User App Installation

M4-003 adds an explicit current-user installation workflow for the menu bar app.
The only supported destination is:

```text
$HOME/Applications/Hermes Bridge.app
```

The scripts never use `sudo`, never write to `/Applications`, and reject a
symlinked `$HOME/Applications` destination root. They replace only the exact
`Hermes Bridge.app` path after validating the freshly built bundle.

## Commands

Install and launch the user-local app:

```sh
Scripts/native/install-hermes-bridge-app.zsh --install-user-app
```

Uninstall the user-local app and restore an installer-created backup when one
exists:

```sh
Scripts/native/uninstall-hermes-bridge-app.zsh --uninstall-user-app
```

The explicit flags are required so ordinary script invocation cannot install or
remove the app by accident.

## Installer Behavior

The installer:

- builds the existing `HermesBridgeApp` Xcode SwiftPM scheme and SwiftPM
  product;
- assembles `Hermes Bridge.app` under `artifacts/m4-003/build`;
- validates `Packaging/HermesBridgeApp/Info.plist`;
- requires bundle identifier `com.hermes.bridge.app`;
- copies Xcode-generated `.appintents` metadata into the app resources;
- verifies all five expected App Intent titles in embedded metadata;
- ad-hoc signs the complete app bundle;
- verifies the signature before copying;
- backs up an existing exact installed app to `artifacts/m4-003/backups`;
- keeps only a bounded set of installer-created backups;
- atomically copies through a temporary sibling and renames into place;
- verifies the installed signature and launches the exact installed app with
  `open -n`.

It does not launch Hermes and does not submit a Prompt.

## Uninstaller Behavior

The uninstaller:

- targets only `$HOME/Applications/Hermes Bridge.app`;
- verifies the app bundle identifier before removal;
- asks the bundle-aware application id `com.hermes.bridge.app` to quit;
- falls back to terminating only PIDs whose executable path is inside the exact
  installed bundle;
- never uses `killall` or `pkill`;
- removes only the exact app path;
- restores the last installer-created backup when available;
- is idempotent when the app is already absent.

Unrelated applications and user data are preserved.

## Signing Limitations

The workflow uses ad-hoc signing only. This is enough to validate local bundle
shape and code signature integrity on the research Mac, but it is not a
Developer ID, hardened runtime, notarization, or release distribution claim.

The product release path still needs Developer ID signing, notarization, and
release packaging validation before public distribution.
