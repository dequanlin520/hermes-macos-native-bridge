# SPK-02 Findings

## Confirmed Local Facts

### Read-only Inspection

- The read-only script ran successfully on 2026-07-17 UTC and produced:
  `SPK02_READ_ONLY_RESULT=PASS`.
- `sw_vers` reported macOS 27.0 build `26A5378j`.
- `uname -m` reported `arm64`.
- `id -u` reported `501`; the expected current GUI launchd domain is
  `gui/501`.
- `launchctl help` was available and listed relevant subcommands including
  `print`, `bootstrap`, `bootout`, `enable`, `disable`, `kickstart`, `blame`,
  and `procinfo`.
- `launchctl print gui/501` completed successfully. Full captured output is in
  ignored artifacts at
  `artifacts/spk-02/logs/20260717T030834Z-launchctl-print-gui-domain.txt`.
- `codesign` is available at `/usr/bin/codesign`; `codesign -h` printed usage
  and exited with status 2, which is expected for help-style invocation.
- `xcrun` is available at `/usr/bin/xcrun`; `xcrun --version` reported version
  `72`.
- `xcode-select -p` reported
  `/Applications/Xcode-beta.app/Contents/Developer`.
- `xcodebuild -version` reported Xcode 27.0 build `27A5218g`.
- `swift --version` reported Apple Swift 6.4 targeting
  `arm64-apple-macosx27.0.0`.
- `clang --version` reported Apple clang 21.0.0 targeting
  `arm64-apple-darwin27.0.0`.
- A minimal Swift executable compiled under `artifacts/spk-02/build`, ran, and
  printed `SPK02_MINIMAL_SWIFT_OK`.
- A Swift typecheck probe importing Foundation and referencing
  `NSXPCConnection` and `NSXPCInterface` completed successfully.
- `plutil -lint` validated a generated LaunchAgent-style plist with a
  `MachServices` dictionary.
- Local documentation evidence is available for `launchd.plist(5)`,
  `launchctl(1)`, and `xpcservice.plist(5)`.
- No local `xpcd` manpage was found.
- Generated probe sources, module cache, binaries, and logs were written under
  `artifacts/spk-02`, which is ignored by Git.

Machine-readable summary from the successful run:

```text
SPK02_READ_ONLY_RESULT=PASS
SWIFT_BUILD_AVAILABLE=yes
XPC_COMPILE_AVAILABLE=yes
XCODE_AVAILABLE=yes
LAUNCHCTL_GUI_DOMAIN_READABLE=yes
```

### Active LaunchAgent/XPC Experiment

- The active script ran successfully on 2026-07-17 UTC and produced:
  `SPK02_ACTIVE_RESULT=PASS`.
- The active experiment generated the unique label
  `com.hermes.spk02.20260717T032034Z.35424`.
- All generated Swift source, compiled binaries, plist files, module cache, and
  logs were written under ignored artifacts at
  `artifacts/spk-02/active/com.hermes.spk02.20260717T032034Z.35424/`.
- Preflight confirmed `swiftc`, `plutil`, and `launchctl` were available.
- `launchctl print gui/501/<unique-label>` failed before bootstrap, confirming
  there was no pre-existing registration for the generated label.
- The generated plist validated with `plutil -lint`.
- `launchctl bootstrap gui/501 <temporary-plist>` exited `0`.
- `launchctl print gui/501/<unique-label>` succeeded after bootstrap and
  showed a LaunchAgent in `gui/501`.
- The launchctl print evidence showed one managed endpoint named exactly
  `com.hermes.spk02.20260717T032034Z.35424`.
- The generated plist set `ProcessType=Background`; launchctl reported
  `spawn type = background (5)`.
- The generated Swift client connected to the unique Mach service, exited `0`,
  and printed exactly `SPK02_XPC_RESPONSE=SPK02_RESPONSE`.
- The generated Swift server stdout recorded:
  `SPK02_SERVER_STARTED=<unique-label>`,
  `SPK02_SERVER_CONNECTION=accepted`, and
  `SPK02_SERVER_REQUEST=accepted`.
- The observed server PID after the successful client round trip was `35577`.
- `launchctl bootout gui/501/<unique-label>` exited `0`.
- A post-cleanup `launchctl print gui/501/<unique-label>` failed with service
  not found.
- A post-cleanup `ps -p 35577` found no remaining experiment-owned process.
- No sudo was used, no permanent LaunchAgent was installed, and no files were
  written to `~/Library/LaunchAgents`.
- No broad process termination command was used; the cleanup path targets only
  the generated label and, if observed, the recorded experiment-owned PID.

Machine-readable summary from the successful active run:

```text
SPK02_ACTIVE_RESULT=PASS
LAUNCHAGENT_BOOTSTRAP_AVAILABLE=yes
MACH_SERVICE_VISIBLE=yes
XPC_ROUNDTRIP_AVAILABLE=yes
LAUNCHAGENT_BOOTOUT_CLEAN=yes
SPK02_UNIQUE_LABEL=com.hermes.spk02.20260717T032034Z.35424
```

## Unsupported Assumptions

- The active run proves a temporary per-user LaunchAgent can be bootstrapped
  and booted out on this host, but it does not establish production packaging
  or installer behavior.
- The active run proves a generated Swift client can reach a generated Swift
  Mach service in the same user session, but it does not prove cross-version,
  cross-process, or app-bundle entitlement behavior.
- `plutil` syntax validation plus active bootstrap confirms this generated
  plist shape is accepted locally, but does not settle the final production
  plist keys for crash behavior, log rotation, disablement, or emergency stop.
- The current evidence does not establish production code signing,
  notarization, hardened runtime, entitlement, or packaging requirements.
- The current evidence does not establish restart policy, crash backoff,
  production log routing, user-facing disablement, or emergency-stop behavior.

## Blockers

- No blocker remains for selecting a per-user LaunchAgent/Mach-service topology
  as the basis for M2 Runtime Foundation design work.
- Runtime implementation should not begin until an ADR captures the selected
  topology, the versioned XPC contract boundary, lifecycle semantics, cleanup
  behavior, signing assumptions, and explicit non-goals.

## Topology Implications

- Candidate A, a per-user LaunchAgent with a narrow versioned Mach-service/XPC
  contract, is technically validated on this host.
- The runtime foundation should stay in the user launchd domain. The evidence
  does not justify a system LaunchDaemon or privileged helper path.
- Candidate B, an app-hosted XPC service, is not required to satisfy the
  observed lifecycle and IPC topology question.
- Candidate C, a LaunchAgent supervisor plus app-facing helper, remains
  possible later, but it adds coordination complexity that is not necessary for
  the next runtime foundation milestone.
- M2 Runtime Foundation can proceed with Candidate A as the recommended
  topology, provided the production contract remains narrow and versioned.
- The script had to force `CLANG_MODULE_CACHE_PATH` into
  `artifacts/spk-02/build/module-cache`; future spike scripts should keep
  compiler caches artifact-owned to avoid writing outside the repository.
- The XPC surface must remain a versioned, explicit contract. This spike does
  not support any generic process execution, shell, AppleScript, GUI
  automation, browser automation, or remote-control API.

## Verdict

SPK-02 VERDICT: GO

What has been proven:

- A temporary LaunchAgent can be bootstrapped into `gui/501` from a plist under
  ignored repository artifacts.
- A LaunchAgent `MachServices` entry can publish a unique per-user Mach service
  visible through `launchctl print`.
- A generated Swift XPC client can connect to that Mach service and receive the
  fixed response `SPK02_RESPONSE`.
- The temporary LaunchAgent can be booted out cleanly.
- The unique launchd registration and observed experiment-owned server process
  are absent after cleanup.

What remains unresolved:

- Production signing, notarization, hardened runtime, entitlement, packaging,
  and installer behavior.
- Final production LaunchAgent plist keys, restart policy, logging policy,
  disablement behavior, and emergency-stop behavior.
- Final XPC contract versioning and compatibility policy.

Recommended candidate: Candidate A.

ADR requirement: yes. An ADR is required before runtime implementation.
