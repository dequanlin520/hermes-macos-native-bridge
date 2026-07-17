# Bridge Service Lifecycle

## Installation Layout

The production lifecycle manager installs the per-user Bridge service without
`sudo` under:

```text
~/Library/Application Support/HermesBridge/
├── Versions/<version>/HermesBridgeService
├── Current -> Versions/<version>
├── Runtime/
├── State/
├── Logs/
├── Backups/
└── install-state.json
```

The LaunchAgent plist is installed only by an explicit real-user operation:

```text
~/Library/LaunchAgents/com.hermes.bridge.plist
```

Directories are created with restrictive permissions. The installed service
binary is copied into an immutable version directory with executable owner
permissions. Layout creation rejects symlink components so installation cannot
escape through a symlinked root.

## Lifecycle Operations

`HermesBridgeServiceManager` exposes typed operations only:

- `planInstall`
- `install`
- `validateInstallation`
- `bootstrap`
- `status`
- `stop`
- `restart`
- `upgrade`
- `rollback`
- `uninstall`

The CLI executable, `HermesBridgeServiceLifecycle`, exposes the matching fixed
subcommands:

```text
plan install validate bootstrap status stop restart upgrade rollback uninstall
```

It has no generic exec, shell, passthrough, arbitrary label, arbitrary Mach
service, or arbitrary `launchctl` argument surface.

## Launchctl Boundary

The production adapter is fixed to the current user domain, the production
label, the production Mach service, and the exact installed plist. It permits
only:

```text
launchctl bootstrap gui/<uid> <exact-installed-plist>
launchctl bootout gui/<uid> <exact-installed-plist>
launchctl kickstart -k gui/<uid>/com.hermes.bridge
launchctl print gui/<uid>/com.hermes.bridge
```

There is no `sudo`, `killall`, or `pkill` path.

## Health Checks

Validation checks installed files and permissions, plist consistency, launchd
visibility, and the typed XPC boundary. The XPC health check performs protocol
handshake and capabilities queries only. It does not inspect secrets, submit
prompts, start real Hermes work, or read Keychain or `~/.hermes`.

Status reports:

- `notInstalled`
- `installedStopped`
- `starting`
- `runningHealthy`
- `runningUnhealthy`
- `upgradePending`
- `rollbackAvailable`
- `invalidInstallation`

## Upgrade And Rollback

Upgrade stages a new version, preserves the previous active version, stops the
exact service, atomically switches `Current`, bootstraps or restarts, then runs
a bounded health check. If activation or health validation fails, the manager
automatically switches back to the previous active version and restores prior
install-state metadata.

Rollback uses only the previous version recorded in `install-state.json`; it
never selects an arbitrary filesystem path.

The manager keeps a bounded number of historical versions and preserves the
active and rollback versions during pruning.

## State, Logs, And Uninstall

Uninstall boots out only the exact installed plist and removes installer-owned
plist, versioned binaries, `Current`, and install metadata. It preserves
`State/` and `Logs/` by default. `--purge-state` and `--purge-logs` are
separate explicit CLI flags.

Uninstall is idempotent and does not remove unrelated LaunchAgent files.

## Real-User Installation

Real installation is never performed by tests or integration scripts. To
install into the current user's production layout after building a trusted
service binary:

```sh
swift build --product HermesBridgeService --product HermesBridgeServiceLifecycle
.build/debug/HermesBridgeServiceLifecycle install \
  --install-user-service \
  --service-binary "$PWD/.build/debug/HermesBridgeService" \
  --version "<version>" \
  --bootstrap
```

Omit `--bootstrap` to stage and activate the installed version without loading
the LaunchAgent.

## Signing And Notarization Status

This milestone implements the service lifecycle boundary. Public release still
requires a signed and notarized distribution, hardened runtime review,
entitlement policy, installer UX, and final update channel decisions.

## Limitations Before Public Release

- No public installer package is produced yet.
- Signing and notarization are not claimed by this milestone.
- Log rotation and user-visible controls remain future M3 work.
- Tests use artifact-owned fake homes and injected launchctl/health adapters.
