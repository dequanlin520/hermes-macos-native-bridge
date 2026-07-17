# Bridge Control CLI

`HermesBridgeControl` is the user-facing operational control utility for the
per-user `HermesBridgeService`.

It exposes fixed commands only. It does not accept arbitrary launchd labels,
Mach services, XPC methods, JSON payloads, shell commands, executable paths, or
process identifiers.

## Commands

```sh
HermesBridgeControl status
HermesBridgeControl doctor
HermesBridgeControl capabilities
HermesBridgeControl start
HermesBridgeControl stop
HermesBridgeControl restart
HermesBridgeControl requests
HermesBridgeControl request-status --request-id hrq_...
HermesBridgeControl cancel --request-id hrq_...
HermesBridgeControl approval-response --request-id hrq_... --decision approve
HermesBridgeControl approval-response --request-id hrq_... --decision reject
HermesBridgeControl emergency-stop
```

Optional global flags:

```sh
--format text
--format json
--timeout 5
--installation-root artifacts/example-root
```

`--installation-root` is test-only and must point at a trusted temporary or
artifact root. Production operation uses the current user's fixed installation
layout.

## Fixed Service Boundary

Control operations target only:

- current user launchd domain: `gui/<uid>`;
- LaunchAgent label: `com.hermes.bridge`;
- Mach service: `com.hermes.bridge.xpc`;
- exact installer-owned plist:
  `~/Library/LaunchAgents/com.hermes.bridge.plist`.

Request operations use typed XPC APIs. The request list reads only the Bridge
request-state store and emits redacted summaries.

## Output

All commands support deterministic JSON with sorted keys:

```sh
HermesBridgeControl status --format json
```

Text output is intended for operators. JSON output is the stable integration
contract for future menu bar and App Intent callers.

Stable Codable output models:

- `HermesBridgeCLIStatusOutput`;
- `HermesBridgeDoctorReport`;
- `HermesBridgeDoctorCheck`;
- `HermesBridgeCLIErrorOutput`;
- `HermesBridgeRequestSummary`.

The CLI never prints backend authentication material, request text, full result
content, captured process streams, credential-store data, private launch
metadata, or arbitrary filesystem paths.

## Exit Codes

| Code | Meaning |
| ---: | --- |
| 0 | success |
| 2 | usage error |
| 10 | not installed |
| 11 | service unavailable |
| 12 | unhealthy |
| 13 | protocol incompatible |
| 14 | request not found |
| 15 | operation rejected |
| 20 | internal redacted failure |

## Emergency Stop

`emergency-stop` is intentionally narrow:

1. It attempts a normal typed service interaction when XPC is available.
2. It boots out only the exact fixed LaunchAgent through the service manager.
3. It may shut down a process group only when Bridge-owned process identity is
   verified by the existing supervisor boundary.
4. It verifies cleanup through the typed health check and emits a redacted
   result.

It never uses `sudo`, process-name termination, arbitrary PID or PGID input, or
generic launchctl arguments.

## Examples

```sh
HermesBridgeControl status --format text
HermesBridgeControl doctor --format json
HermesBridgeControl requests --installation-root artifacts/m3-003/example
HermesBridgeControl cancel --request-id hrq_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
```

## Future UI Relationship

The future menu bar UI should call the same fixed commands or share the same
typed control core. It should not grow a broader control surface than this CLI.
