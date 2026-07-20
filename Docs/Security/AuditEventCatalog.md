# Audit Event Catalog

Audit event kinds are fixed by `HermesAuditEventKind`.

| Event kind | Meaning |
| --- | --- |
| `serviceInstalled` | Service layout or active version installed. |
| `serviceStarted` | Fixed LaunchAgent bootstrap requested. |
| `serviceStopped` | Fixed LaunchAgent bootout requested. |
| `serviceRestarted` | Stop, bootstrap and kickstart sequence completed. |
| `serviceUpgraded` | Service upgraded to a new active version. |
| `serviceRolledBack` | Service rolled back to the previous active version. |
| `requestAccepted` | Typed request accepted by XPC. |
| `requestStarted` | Request submitted to the orchestrator. |
| `requestCancelled` | Request cancellation accepted or completed. |
| `requestCompleted` | Request reached completed state. |
| `requestFailed` | Request failed with a bounded reason code. |
| `approvalRequested` | Request entered waiting-for-approval state. |
| `approvalResponded` | Approval response was sent. |
| `authorizedRootAdded` | Authorized root was added through typed XPC. |
| `authorizedRootRefreshed` | Authorized root bookmark was refreshed/reactivated. |
| `authorizedRootDeactivated` | Authorized root was deactivated. |
| `authorizedRootRemoved` | Authorized root was removed. |
| `fileSubscriptionCreated` | File-event subscription was created. |
| `fileSubscriptionCancelled` | File-event subscription was cancelled. |
| `fileRescanRequired` | File monitor/subscription requires a rescan. |
| `doctorExecuted` | Health or permissions Doctor ran. |
| `emergencyStopRequested` | Emergency stop was explicitly requested. |
| `emergencyStopCompleted` | Emergency stop completed with bounded outcome. |
| `auditExported` | Audit export completed and manifest/checksum was written. |

Actors are fixed: `service`, `controlCLI`, `menuBar`, `appIntent`,
`xpcClient`, `testFixture` and `unknown`.

Outcomes are fixed: `accepted`, `started`, `succeeded`, `failed`,
`cancelled`, `denied` and `unavailable`.
