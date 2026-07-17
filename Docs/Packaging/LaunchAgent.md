# LaunchAgent Packaging

## Template

The tracked template is:

```text
Packaging/LaunchAgent/com.hermes.bridge.plist.template
```

It documents the production label and Mach service:

```text
Label: com.hermes.bridge
MachServices: com.hermes.bridge.xpc
```

`ProgramArguments`, `StandardOutPath`, and `StandardErrorPath` use replacement
tokens. The tracked plist contains no secrets, backend tokens, prompts, HOME
override, or direct Hermes executable invocation.

## Launchd Fields

`RunAtLoad` is true so the per-user service is available after bootstrap.
`KeepAlive` is false for this milestone; conservative restart/crash behavior is
left to future signed packaging work. `ProcessType` is `Background`, matching
the SPK-02 per-user service topology. `ThrottleInterval` is explicit to avoid
tight restart loops in later installer-owned configurations.

## Generator

`Scripts/packaging/generate-launchagent-plist.zsh` accepts exactly:

```text
generate-launchagent-plist.zsh <output-plist> <service-binary>
```

It requires absolute paths, verifies the service binary exists and is
executable, writes only under `artifacts/m2-008`, substitutes fixed template
tokens, creates an artifact-owned logs directory, and validates the result with
`plutil -lint`.

The script does not install, bootstrap, bootout, or write to
`~/Library/LaunchAgents`.

## Temporary Integration Test

The launchd integration path is intentionally separate:

```text
Scripts/integration/m2-008-launchagent-xpc.zsh
```

It creates a generated test plist under `artifacts/m2-008`, uses a unique test
label and Mach service with trusted test configuration, bootstraps into the
current `gui/<uid>` domain, performs only XPC version/capability queries, and
boots out the exact plist. It verifies the launchd service and process are
absent afterward.

## Signing Status

This issue does not claim production signing, notarization, hardened runtime,
or final installer behavior. Permanent installation remains out of scope.

## Next Step

The next packaging issue should define signed app or installer ownership for
LaunchAgent placement, upgrade, removal, log rotation, restart policy, and
user-visible service controls.
