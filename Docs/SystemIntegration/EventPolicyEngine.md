# Event Policy Engine

Hermes event policies evaluate normalized `HermesSystemEvent` values and may
execute only fixed Bridge actions through typed adapters. The engine does not
receive raw macOS notification names, process identifiers, executable paths,
window titles, clipboard data, file contents, environment variables, prompts or
backend tokens.

## Policy Model

Policies use:

- `HermesEventPolicyID`
- `HermesEventPolicySchemaVersion`
- `HermesEventPolicy`
- `HermesEventPolicyCondition`
- `HermesEventPolicyAction`
- `HermesEventPolicyExecutionMode`
- `HermesEventPolicyEvaluation`
- `HermesEventPolicyDecision`
- `HermesEventPolicyStore`
- `FileBackedHermesEventPolicyStore`
- `HermesEventPolicyEngine`
- `HermesEventPolicyExecutionRecord`

Policy IDs are bounded `hepol_` identifiers. Policies are versioned, revisioned,
enabled or disabled, and contain bounded condition and action arrays.

## Conditions

The condition catalog is fixed:

- event kind equals;
- safe application bundle identifier equals;
- network availability equals;
- network interface type equals;
- service-health state equals;
- constrained network flag equals;
- expensive network flag equals;
- bounded local-hour time window;
- minimum interval since previous match.

Conditions use AND semantics. There is no arbitrary code, regex matching over
event content, process argument matching, executable-path matching, window-title
matching, clipboard matching, file-content matching, environment matching or
arbitrary predicate API.

## Actions

The action catalog is fixed:

- `recordAuditEvent`
- `refreshBridgeHealth`
- `restartBridgeService`
- `submitApprovedBinding`
- `createUserNotification`
- `markPolicyAttentionRequired`

Actions execute through injected typed adapters for service management, request
submission, binding discovery, notifications and audit. There is no shell,
AppleScript, URL opening, executable path, generic XPC operation or dynamic
automation action.

## Evaluation

The engine evaluates enabled policies in deterministic policy-ID order. It
validates matches, suppresses duplicate events, enforces per-policy cooldown,
per-policy and global rate limits, applies approval gates, supports dry-run and
records safe decisions.

Decision states are:

- `notMatched`
- `matchedDryRun`
- `blockedDisabled`
- `blockedCooldown`
- `blockedRateLimit`
- `blockedApprovalRequired`
- `blockedBindingUnavailable`
- `blockedGlobalPause`
- `executed`
- `failedRedacted`

Global pause, emergency stop and the circuit breaker block new policy actions.
Manual resume clears pause/circuit-breaker state. Emergency stop is in-memory
and immediate; it does not use process-name matching, `killall`, `pkill`, PIDs
or arbitrary executable controls.
