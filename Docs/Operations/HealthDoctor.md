# Health Doctor

`HermesBridgeControl doctor` reports typed, redacted health checks for the
Bridge installation and runtime boundary. It does not repair anything.

Each check returns:

- stable check ID;
- `pass`, `warning`, `fail`, or `notApplicable`;
- safe explanation;
- optional fixed remediation code.

## Checks

| Check ID | Purpose |
| --- | --- |
| `installation.layout` | Expected per-user installation directories exist. |
| `installation.activeVersion` | Install state records an active version. |
| `binary.executable` | Active service binary exists and is executable. |
| `binary.signature` | Active binary has a code signature. |
| `binary.hardenedRuntime` | Active binary reports hardened runtime metadata. |
| `plist.validity` | LaunchAgent plist is parseable. |
| `launchagent.fixedLabel` | Plist label is `com.hermes.bridge`. |
| `launchagent.fixedMachService` | Plist Mach service is `com.hermes.bridge.xpc`. |
| `launchd.visibility` | Fixed service is visible in the current user launchd domain. |
| `xpc.handshake` | Typed XPC handshake succeeds. |
| `xpc.protocolVersion` | Protocol major version is compatible. |
| `xpc.capabilities` | Capability query succeeds. |
| `hermes.executableDiscovery` | Hermes executable discovery status is available. |
| `backend.processStatus` | Backend process status is consistent when running. |
| `requestState.rootReadable` | Request-state root is readable. |
| `runtimeLog.rootPermissions` | Runtime and log roots are writable by the current user. |
| `temporary.staleFiles` | No stale Bridge temporary files are present. |
| `signing.mode` | Signing mode is suitable for the current distribution stage. |
| `notarization.readiness` | Local metadata is ready for notarization preflight. |
| `service.residualState` | No inconsistent service, process, or port state remains. |

## Remediation Codes

| Code | Meaning |
| --- | --- |
| `INSTALL_SERVICE` | Install or restore the Bridge service layout. |
| `REINSTALL_SERVICE` | Reinstall the active service binary. |
| `SIGN_SERVICE_BINARY` | Sign the service binary. |
| `ENABLE_HARDENED_RUNTIME` | Re-sign with hardened runtime enabled. |
| `REINSTALL_LAUNCHAGENT` | Recreate the installer-owned LaunchAgent plist. |
| `START_SERVICE` | Start the fixed per-user service. |
| `UPDATE_BRIDGE` | Update Bridge components to a compatible protocol version. |
| `CHECK_XPC` | Inspect the fixed XPC service boundary. |
| `CHECK_HERMES_INSTALL` | Verify the allowlisted Hermes executable installation. |
| `FIX_STATE_ROOT_PERMISSIONS` | Correct request-state root permissions. |
| `FIX_RUNTIME_LOG_PERMISSIONS` | Correct runtime or log root permissions. |
| `CLEAN_STALE_TEMPORARY_FILES` | Remove stale Bridge-owned temporary files. |
| `USE_DEVELOPER_ID_SIGNING` | Use Developer ID signing for release artifacts. |
| `COMPLETE_NOTARIZATION_PREFLIGHT` | Complete notarization readiness checks. |
| `RUN_EMERGENCY_STOP` | Use the fixed emergency stop command. |

## Privacy

Doctor output is redacted. It must not include backend authentication material,
request text, full result content, captured process streams, credential-store
data, private launch metadata, or arbitrary private paths.

## Example

```sh
HermesBridgeControl doctor --format json
```

The command exits `0` for all-pass and warning reports. It exits `12` when any
check fails.
