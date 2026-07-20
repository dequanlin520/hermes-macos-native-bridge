# Event Policy Approvals

Event-triggered policies that require approval create a bounded, one-shot
approval request. Approval authorizes exactly one immutable execution snapshot;
it does not create a blanket token and it cannot edit the policy action.

## Models

The approval workflow uses:

- `HermesEventPolicyApprovalID`
- `HermesEventPolicyApprovalState`
- `HermesEventPolicyApprovalDecision`
- `HermesEventPolicyApprovalRequest`
- `HermesEventPolicyApprovalSnapshot`
- `HermesEventPolicyApprovalStore`
- `FileBackedHermesEventPolicyApprovalStore`
- `HermesEventPolicyApprovalCoordinator`
- `HermesEventPolicyApprovalExecutionResult`

States are fixed: `pending`, `approved`, `denied`, `expired`, `cancelled`,
`executing`, `executed`, `failedRedacted`, `invalidatedByPolicyChange` and
`blockedByEmergencyStop`.

## Snapshot

Each pending request persists only safe immutable fields: approval ID, policy
ID and revision, event ID and event kind, action kind, optional binding ID,
reviewed template digest, safe rendered summary, timestamps, approval
requirement and correlation ID. Binding actions also retain the reviewed static
template so execution can render with fixed safe placeholders after approval.

Raw system events, arbitrary prompt bodies, window titles, clipboard data,
paths, tokens, file content and process arguments are not persisted or exposed.

## Workflow

When a matching policy requires approval, the engine validates the policy and
binding, captures the snapshot, persists a pending request, audits creation,
optionally sends a safe notification and returns `blockedApprovalRequired` with
the approval ID. No action runs before approval.

Approve, deny, cancel, expire, list, status and queue status are typed
operations. Duplicate identical responses are idempotent after completion;
conflicting responses are rejected. Approval execution checks expiration,
current policy revision, enabled policy state, binding availability,
event-trigger permission, global pause and emergency stop before executing the
captured action.
