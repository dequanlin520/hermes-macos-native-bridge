# Hermes Settings Center

## Architecture

M10-004 adds `HermesSettings`, a native SwiftUI settings center for runtime,
interface, and logging preferences.

```text
HermesSettingsWindow
        |
HermesSettingsViewModel
        |
HermesSettingsController
        |
HermesConfigurationStore
        |
UserDefaults
```

`HermesSettingsWindow` is the AppKit-hosted SwiftUI settings surface.
`HermesSettingsViewModel` runs on the main actor and publishes
`HermesSettingsState` plus editable draft settings. `HermesSettingsController`
owns validation and save/load coordination. `HermesConfigurationStore` is the
only persistence boundary.

The settings target does not call the runtime command API, event bus, process
supervisor, backend adapter, protocol client, shell, AppleScript, JXA, or any
generic executable path.

## Data Flow

On load, the view model asks `HermesSettingsController` to load settings from
`HermesConfigurationStore`. The store reads versioned UserDefaults keys and
falls back to `HermesSettings.defaults` when a key is absent.

On save, the view model sends its draft settings to the controller. The
controller validates the values before updating state and before asking the
store to persist them. Invalid values remain out of persisted storage and are
reported through a redacted error message.

Supported settings:

- runtime: `autoStart`, `healthCheckIntervalSeconds`,
  `startupTimeoutSeconds`;
- interface: `showMenuBarIcon`, `enableNotifications`,
  `dashboardRefreshIntervalSeconds`;
- logging: `info`, `warning`, `error`.

Validation rejects negative intervals and startup timeout values outside
`1...3600` seconds.

## Persistence Model

Settings are stored in UserDefaults under versioned keys with the
`com.hermes.settings.v1.` prefix. Each value is stored as a primitive Boolean,
integer, or string. The store does not serialize arbitrary dictionaries or
opaque configuration blobs.

Persisted keys are limited to:

- `runtime.autoStart`;
- `runtime.healthCheckIntervalSeconds`;
- `runtime.startupTimeoutSeconds`;
- `ui.showMenuBarIcon`;
- `ui.enableNotifications`;
- `ui.dashboardRefreshIntervalSeconds`;
- `logging.level`.

## Security Boundary

The settings center stores preferences only. It must not store or display:

- tokens;
- passwords;
- API keys;
- credentials;
- secrets;
- executable paths;
- shell commands;
- launch arguments.

The store rejects sensitive key names at the persistence boundary. Error text
is passed through `HermesSettingsRedactor` before entering view state so
accidental token, password, API key, credential, secret, or user path fragments
are not displayed by the UI.

Changing settings does not start, stop, launch, execute, or remotely control
Hermes. Runtime behavior consumes approved settings through future explicit
integration points.
