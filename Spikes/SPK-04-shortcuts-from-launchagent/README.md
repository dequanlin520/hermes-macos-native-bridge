# SPK-04 Shortcuts From LaunchAgent

This spike validates the macOS Shortcuts CLI from a temporary per-user
LaunchAgent in `gui/<uid>`.

## Read-Only Mode

Run:

```sh
Scripts/spikes/spk-04-shortcuts-from-launchagent.zsh
```

Read-only mode records macOS version, architecture, UID, GUI launchd domain
readability, `/usr/bin/shortcuts` presence, bounded `shortcuts --help` output,
selected subcommand help, `launchctl` availability and `plutil` availability.

It does not enumerate personal shortcut names. It checks only whether the exact
fixture name exists and records `FIXTURE_AVAILABLE=yes|no`.

## Active Mode

Run:

```sh
Scripts/spikes/spk-04-shortcuts-from-launchagent.zsh --active-test
```

Active mode creates:

```text
artifacts/spk-04/active/com.hermes.spk04.<timestamp>.<pid>/
```

Inside that directory it writes a generated helper script, a temporary plist,
LaunchAgent stdout and stderr, bounded Shortcuts CLI output, exit codes,
durations, timeout markers, a sanitized environment file and cleanup evidence.

The LaunchAgent is loaded with `launchctl bootstrap gui/<uid> <plist>`, runs
once with `RunAtLoad`, and is removed with `launchctl bootout gui/<uid>
<plist>`. The script then checks that the generated service label is no longer
visible and that the recorded helper PID is not running.

## Fixture Requirement

The only shortcut that active mode may execute is exactly:

```text
Hermes Bridge SPK-04 Fixture
```

The fixture must require no private input and must write exactly this fixed
marker to stdout:

```text
SPK04_SHORTCUT_RESPONSE
```

No unrelated shortcut output is recorded. When the fixture exists, active mode
records only the fixture exit status, duration, timeout state and whether the
expected marker was received. Raw fixture stdout and stderr are removed before
the script exits.

## Manual Fixture Creation

This system did not expose a documented noninteractive way to generate and
import a valid shortcut fixture during the spike. Create the fixture manually in
the Shortcuts app if end-to-end execution needs to be exercised:

1. Create a shortcut named `Hermes Bridge SPK-04 Fixture`.
2. Add one action that emits the text `SPK04_SHORTCUT_RESPONSE`.
3. Ensure it requires no input and does not access private data.
4. Run the active spike again.

## Invocation Model

The selected production model is a versioned Shortcut Binding allowlist:

- each binding has one fixed shortcut name or identifier;
- callers cannot submit arbitrary shortcut names;
- callers may provide only structured parameters allowed by the binding;
- execution uses absolute `/usr/bin/shortcuts`;
- the process environment uses `PATH=/usr/bin:/bin:/usr/sbin:/sbin`;
- timeout, cancellation, exit status and sanitized audit events are mandatory;
- private shortcut input and output are not logged.

## Cleanup

The script uses trap-based cleanup. If interrupted, it attempts to boot out only
the generated plist for the generated label. It does not use `killall`,
`pkill`, `sudo`, permanent LaunchAgent locations, AppleScript, JXA or GUI
automation.
