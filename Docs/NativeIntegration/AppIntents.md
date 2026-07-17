# Hermes App Intents

## Intent List

M4-001 adds the `HermesAppIntents` Swift target with real AppIntents framework
types:

- `SubmitHermesRequestIntent`
- `CheckHermesRequestStatusIntent`
- `CancelHermesRequestIntent`
- `RespondToHermesApprovalIntent`
- `CheckHermesBridgeHealthIntent`

The target also includes `HermesAppShortcutsProvider` and a minimal
`HermesAppIntentsHost` SwiftUI executable target that compiles the App Intent
declarations. The host is intentionally not a menu bar UI.

## Immediate XPC Handoff

`SubmitHermesRequestIntent` validates its local inputs, calls the typed
`HermesAppIntentClient.submit(bindingID:prompt:)` operation, returns a Request
ID, and exits. Long-running Hermes execution remains owned by
`HermesBridgeService` behind the existing versioned XPC boundary.

The App Intents layer does not expose raw XPC `Data`, generic operation names,
generic JSON values, executable paths, endpoints, JSON-RPC methods, shell
commands, AppleScript, JXA, GUI control, or browser automation.

## Parameters And Outputs

`HermesAppIntentBindingEntity` represents enabled allowlisted bindings only:

- stable binding identifier;
- localized display name;
- bounded safe description.

It does not include executable, endpoint, token, or JSON-RPC fields.

`HermesAppIntentRequestEntity` represents only:

- Request ID;
- safe lifecycle state;
- cancellation-requested flag;
- result-available flag;
- safe failure code.

It does not include Prompt text, backend session tokens, raw result bodies,
private paths, process identifiers, or backend output.

`CheckHermesBridgeHealthIntent` returns compact safe health data:

- available or unavailable;
- compatible or incompatible;
- protocol version;
- supported capability names.

## App Shortcut Phrases

Static shortcut phrases are:

- `Submit a Hermes request in ${applicationName}`
- `Ask Hermes in ${applicationName}`
- `Check Hermes request status in ${applicationName}`
- `Get Hermes request status in ${applicationName}`
- `Cancel a Hermes request in ${applicationName}`
- `Stop Hermes request in ${applicationName}`
- `Respond to Hermes approval in ${applicationName}`
- `Send Hermes approval decision in ${applicationName}`
- `Check Hermes Bridge health in ${applicationName}`
- `Is Hermes Bridge available in ${applicationName}`

Binding names are not embedded in static phrase declarations.

## Error Mapping

The App Intents client maps typed XPC errors into user-facing redacted errors:

| XPC or client failure | App Intent error |
| --- | --- |
| timeout, interruption, invalidation, `serviceUnavailable` | service unavailable |
| `invalidBinding` | invalid binding |
| `oversizedPayload` or local empty/oversized Prompt | oversized Prompt |
| unsupported protocol, negotiation failure, response decode failure | protocol incompatible |
| `requestNotFound` | request not found |
| malformed payload, unsupported operation, invalid state | operation rejected |
| internal failure or unknown failure | internal redacted failure |

Mapped errors do not include Prompt text, backend tokens, raw XPC payloads,
private filesystem paths, process identifiers, or backend output.

## Privacy And Redaction

The App Intents layer preserves the existing XPC privacy boundary:

- Prompt text is transient input to submit only and is not returned by entities.
- Request entities omit backend session tokens.
- Status and cancel outputs omit raw result bodies.
- Health output omits filesystem and installation details.
- Approval response accepts only `allow` or `deny`.

## Build Target

Swift Package targets:

- `HermesAppIntents`: library target containing AppIntent, AppEntity,
  AppEnum, AppShortcutsProvider, typed client adapter, and dependency provider.
- `HermesAppIntentsHost`: minimal SwiftUI executable target that imports
  `HermesAppIntents`.

No production dependency was added.

## Runtime Validation Level

Validated in this issue:

- `swift build` compiles the AppIntent declarations.
- `swift test` covers the shared operation methods, entity redaction,
  fake-XPC adapter boundary, error mapping, and App Shortcut provider.
- `xcodebuild` can build the Swift package scheme when available.

Not claimed:

- Shortcuts or Siri indexing of an installed application.
- Runtime App Shortcuts discovery by macOS.
- A signed app bundle installed into `/Applications`.

## Current Discovery Blocker

The repository still lacks a signed, installed macOS app bundle with product
bundle identifiers, entitlements, and release packaging for Shortcuts indexing.
The Swift Package host compiles App Intents but is not sufficient evidence that
Shortcuts has indexed a user-visible app.

The production binding provider currently returns no bindings because the
Bridge does not yet expose a list-enabled-bindings XPC operation. This avoids
inventing an unreviewed runtime source for allowlist discovery.

## Recommended Next Step

The next native integration issue should add the app-bundle/menu-bar shell and
Bridge-owned binding discovery contract needed for user-visible Shortcuts
registration, while preserving the same typed XPC boundary.
