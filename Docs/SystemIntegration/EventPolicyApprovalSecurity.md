# Event Policy Approval Security

Event policy approvals preserve the event-policy boundary by approving only one
captured action snapshot.

## Prohibited Data

Approval snapshots, XPC payloads, notifications and menu bar rendering must not
contain raw system events, arbitrary prompt bodies, tokens, absolute paths,
clipboard content, window or document titles, file content, process arguments,
environment values, executable paths, shell commands, AppleScript, JXA, GUI
automation or browser automation.

## Binding Execution

For `submitApprovedBinding`, the approved execution uses the stored reviewed
template plus fixed safe placeholders only. Unknown placeholders are rejected.
The binding must still be enabled and must still allow event-triggered
invocation at approval time.

## Invalidations

Expired approvals never execute. Policy revision changes or disabled policies
invalidate pending approvals unless a future version explicitly introduces a
reviewed immutable-historical execution flag. Global pause blocks execution.
Emergency stop blocks pending execution and records `blockedByEmergencyStop`.

## Notification And UI

Approval notifications use the narrow approval notification adapter. Safe
content is limited to policy display name, event kind, action summary and
expiration time. Notification actions may carry only the approval ID plus a
fixed action name. If a direct notification response cannot be validated
safely, the menu bar Approval Inbox must be opened instead.
