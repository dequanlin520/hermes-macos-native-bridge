# SPK-02 LaunchAgent and XPC Topology

## Validation Question

Can Hermes macOS Native Bridge use a per-user LaunchAgent and Mach-service/XPC
topology on the local development host, and what evidence is needed before a
runtime implementation issue proceeds?

## Scope

This spike is technical validation only. It does not add Bridge runtime code,
install a permanent LaunchAgent, modify unrelated launchd state, or create any
files in `~/Library/LaunchAgents`.

## Read-only Inspection Script

Run:

```sh
Scripts/spikes/spk-02-launchagent-xpc-topology.zsh
```

The script writes generated probes, build outputs, and captured command output
under `artifacts/spk-02`, which is ignored by Git.

It inspects:

- macOS version and architecture;
- current UID and expected `gui/<uid>` launchd domain;
- `launchctl help` and `launchctl print gui/<uid>`;
- developer tool availability for `codesign`, `xcrun`, `xcode-select`,
  `xcodebuild`, `swift`, `swiftc`, and `clang`;
- whether Swift Foundation and `NSXPCConnection` APIs typecheck;
- whether a minimal Swift executable builds and runs;
- whether `plutil` can validate a LaunchAgent-style plist containing
  `MachServices`;
- local manpage availability for launchd and XPC evidence.

Machine-readable summary keys:

```text
SPK02_READ_ONLY_RESULT=PASS|PARTIAL|FAIL
SWIFT_BUILD_AVAILABLE=yes|no
XPC_COMPILE_AVAILABLE=yes|no
XCODE_AVAILABLE=yes|no
LAUNCHCTL_GUI_DOMAIN_READABLE=yes|no
```

## Active Experiment Script

Run:

```sh
Scripts/spikes/spk-02-launchagent-xpc-topology.zsh --active-test
```

The active mode generates a unique label of the form
`com.hermes.spk02.<timestamp>.<pid>` and writes all generated Swift source,
binaries, plist files, and logs under
`artifacts/spk-02/active/<unique-label>/`, which is ignored by Git.

It validates:

- a minimal Swift XPC server using `NSXPCListener(machServiceName:)`;
- a minimal Swift XPC client using `NSXPCConnection(machServiceName:)`;
- a versioned fixed test contract:
  `ping("SPK02_REQUEST") -> "SPK02_RESPONSE"`;
- a temporary LaunchAgent plist with one unique `MachServices` entry;
- `plutil -lint` acceptance of the generated plist;
- bootstrap into only the current `gui/<uid>` domain;
- launchctl visibility for the generated label and Mach service;
- a fixed XPC request/response round trip;
- bootout of only the generated label;
- absence of the generated launchd registration and recorded server process
  after cleanup.

Machine-readable summary keys:

```text
SPK02_ACTIVE_RESULT=PASS|PARTIAL|FAIL
LAUNCHAGENT_BOOTSTRAP_AVAILABLE=yes|no
MACH_SERVICE_VISIBLE=yes|no
XPC_ROUNDTRIP_AVAILABLE=yes|no
LAUNCHAGENT_BOOTOUT_CLEAN=yes|no
SPK02_UNIQUE_LABEL=<label>
```

## Topology Candidates

### Candidate A: Per-user LaunchAgent with MachServices

Use a user-domain LaunchAgent with a fixed label and a named Mach service. The
Bridge process starts in the `gui/<uid>` launchd domain and exposes only a
versioned XPC contract to approved local clients.

Implications:

- aligns with Siri, Shortcuts, and menu bar interactions that operate in the
  logged-in user session;
- avoids privileged system-domain launchd scope;
- should keep the product inside the V0.1 security boundary if the XPC surface
  is narrow and versioned;
- requires active validation of bootstrap location, service visibility, code
  signing behavior, and client connection rules.

### Candidate B: App-hosted XPC service

Package the Bridge as an app-hosted XPC service and let a containing menu bar
app own lifecycle.

Implications:

- may fit a future app bundle distribution model;
- may simplify client entitlement and signing relationships inside one bundle;
- does not directly validate standalone LaunchAgent behavior needed for
  background lifecycle management;
- requires later packaging and notarization evidence.

### Candidate C: LaunchAgent supervisor plus app-facing helper

Use a user LaunchAgent as the lifecycle owner and keep UI/menu bar concerns in
a separate app or helper that connects over the approved XPC contract.

Implications:

- separates lifecycle from UI while staying in the user domain;
- may provide a clearer emergency-stop and diagnostics boundary;
- adds contract and coordination complexity;
- likely needs the same LaunchAgent/Mach-service validation as Candidate A.

## Active Result and Recommended Direction

The active experiment passed with:

```text
SPK02_ACTIVE_RESULT=PASS
LAUNCHAGENT_BOOTSTRAP_AVAILABLE=yes
MACH_SERVICE_VISIBLE=yes
XPC_ROUNDTRIP_AVAILABLE=yes
LAUNCHAGENT_BOOTOUT_CLEAN=yes
```

The generated client received exactly:

```text
SPK02_XPC_RESPONSE=SPK02_RESPONSE
```

Recommended topology: Candidate A, a per-user LaunchAgent with a narrow
versioned Mach-service/XPC contract.

SPK-02 VERDICT: GO

This verdict means the LaunchAgent/Mach-service topology is technically viable
for the next design step. It does not by itself approve production runtime code,
packaging, notarization, crash policy, or a broad IPC surface.

## Evidence From Active Run

- Unique test label: `com.hermes.spk02.20260717T032034Z.35424`.
- `launchctl bootstrap gui/501 <temporary-plist>` exited `0`.
- `launchctl print gui/501/<unique-label>` showed a LaunchAgent in `gui/501`
  with one managed endpoint matching the unique Mach service.
- The plist used `ProcessType=Background`; launchctl reported
  `spawn type = background (5)`.
- The generated client exited `0` and printed exactly
  `SPK02_XPC_RESPONSE=SPK02_RESPONSE`.
- The server stdout recorded startup, accepted connection, and accepted fixed
  request evidence.
- The server PID observed after the round trip was `35577`.
- `launchctl bootout gui/501/<unique-label>` exited `0`.
- A post-cleanup `launchctl print` for the unique label failed with service not
  found.
- `ps -p 35577` found no remaining experiment-owned process.
- No generated source, binary, plist, or log file is intended to be committed.

## Evidence Needed Before Runtime Work

- Confirmation that the active experiment can bootstrap and boot out a
  temporary user-domain LaunchAgent reliably. Confirmed for the observed run.
- Confirmation that a Mach service advertised by that LaunchAgent is visible
  and connectable from a test client in the same user session. Confirmed for
  the observed run.
- Confirmation of code signing requirements for local development,
  distribution, and future notarized builds.
- Confirmation of plist keys required for production lifecycle behavior,
  logging, crash behavior, and safe disablement.
- Confirmation that the XPC contract can be versioned and kept narrower than a
  generic command execution API.

An ADR is required before runtime implementation to lock the selected topology,
contract versioning rules, lifecycle semantics, logging policy, and cleanup or
emergency-stop behavior.
