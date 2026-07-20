# Event Policy Security

The event-policy engine preserves the Event Bridge security boundary. Policies
consume only normalized `HermesSystemEvent` fields and can perform only fixed
Bridge actions.

## Binding Invocation

`submitApprovedBinding` is allowed only when typed binding discovery reports an
enabled binding whose configuration explicitly allows event-triggered
invocation. Existing bindings default to `allowsEventTriggeredInvocation =
false`.

Policy prompts are reviewed static templates. Event values may fill only fixed
safe placeholders:

- `eventKind`
- `reasonCode`
- `applicationBundleIdentifier`
- `networkStatus`
- `networkInterface`
- `networkExpensive`
- `networkConstrained`
- `serviceHealth`

Unknown placeholders are rejected. Raw event object injection is not modeled.
Prompt size is bounded by both the policy-template limit and the target binding
maximum Prompt size.

## Prohibited Surfaces

Policies do not support:

- arbitrary shell;
- arbitrary executable paths;
- AppleScript or JXA;
- URL opening;
- generic XPC operations;
- GUI or browser automation;
- process arguments;
- executable paths;
- window titles;
- clipboard data;
- file contents;
- environment variables;
- arbitrary predicates.

## Audit Redaction

Policy audit records contain safe policy IDs, revisions, event kinds, action
kinds, decisions and reason codes. Prompt bodies, generated prompts, paths,
clipboard content, window content and user content are not audit metadata.

Approval audit records contain only approval ID, state, policy ID, event kind,
action kind and reason codes. Approval details and notification content follow
`Docs/SystemIntegration/EventPolicyApprovalSecurity.md`.
