# Shortcuts Runtime Discovery

M4-003 validates whether macOS registers and exposes the installed Hermes
Bridge App Intents to Shortcuts runtime discovery. The validation script is:

```sh
Scripts/integration/m4-003-shortcuts-runtime-discovery.zsh --install-user-app --uninstall-user-app
```

The script installs only:

```text
$HOME/Applications/Hermes Bridge.app
```

It removes or restores that exact app at the end of the run.

## Expected Intents

The installed bundle must contain metadata for:

- Submit Hermes Request
- Check Hermes Request Status
- Cancel Hermes Request
- Respond to Hermes Approval
- Check Hermes Bridge Health

The script validates these titles in the installed bundle's embedded
`.appintents` metadata. This proves compiled metadata presence, not Shortcuts
runtime indexing by itself.

## Evidence Sources

The script captures:

- `codesign --verify --deep --strict` before and after installation;
- `Info.plist` bundle identifier validation;
- installed `.appintents` metadata inspection;
- app launch evidence from an exact executable path under the installed bundle;
- LaunchServices evidence through `mdls` and `lsregister -dump`;
- `/usr/bin/shortcuts --help`;
- `/usr/bin/shortcuts list`;
- `/usr/bin/shortcuts list --show-identifiers`;
- unified log output constrained to App Intents or
  `com.hermes.bridge.app` references.

The script does not read the user's Shortcuts database directly, does not modify
Shortcuts, does not run a Shortcut, and does not automate the Shortcuts UI.

## Observed Result

The 2026-07-17 run on the dedicated research Mac produced:

```text
APP_BUILD_PASSED=yes
APP_SIGNATURE_VALID=yes
USER_APP_INSTALL_PASSED=yes
APP_LAUNCH_PASSED=yes
LAUNCHSERVICES_REGISTRATION_PROVEN=yes
APP_INTENTS_METADATA_PRESENT=yes
SHORTCUTS_RUNTIME_DISCOVERY_PROVEN=no
EXPECTED_INTENTS_DISCOVERED=0
USER_SHORTCUTS_MODIFIED=no
APP_UNINSTALL_PASSED=yes
RESIDUAL_APP_PROCESS=no
M4-003 VERDICT: CONDITIONAL GO
```

LaunchServices registration and installed App Intents metadata were proven.
Supported local Shortcuts CLI and log evidence did not prove that all five
actions were discoverable in the Shortcuts runtime.

## Shortcuts CLI Limitation

`/usr/bin/shortcuts list` lists user Shortcuts. In this run it did not expose a
documented action catalog for installed App Intents, so absence of Hermes action
titles in that command output is not proof that Shortcuts could never show them
in the UI. It is also not positive runtime discovery evidence.

The script therefore reports `SHORTCUTS_RUNTIME_DISCOVERY_PROVEN=yes` only if
supported evidence contains every expected action title. Otherwise, when build,
install, launch, LaunchServices, and installed metadata all pass, the verdict is
`CONDITIONAL GO`.

## Privacy Boundary

The validation stays within the current user's app installation path and public
system metadata tools. It does not inspect private user databases, Keychain,
browser data, `~/.hermes`, private Shortcuts storage, or existing Shortcut
contents. It never submits a Hermes Prompt.

## Next Product Step

The next issue should identify a documented or explicitly approved way to prove
Shortcuts action discovery for an installed menu bar app, or move to Developer
ID/notarized packaging if macOS indexing behavior depends on release signing
and distribution form.
