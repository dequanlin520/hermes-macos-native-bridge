# SPK-06 - Validate Long-Running App Intents

## Objective

Determine how Siri, Shortcuts, and App Intents should hand off long-running
Hermes work to the native Bridge without turning App Intents into a generic
execution surface.

## Scope

This spike validates compile-time AppIntents availability on the local research
Mac and exercises an artifact-owned handoff prototype. It does not install an
app, register Siri shortcuts, modify existing Shortcuts, or send real Hermes
prompts.

## Deliverables

- `Scripts/spikes/spk-06-long-running-app-intents.zsh`
- `Spikes/SPK-06-long-running-app-intents/README.md`
- `Spikes/SPK-06-long-running-app-intents/FINDINGS.md`
- Generated evidence under `artifacts/spk-06/` only

## Validation Commands

```sh
zsh -n Scripts/spikes/spk-06-long-running-app-intents.zsh
Scripts/spikes/spk-06-long-running-app-intents.zsh
Scripts/spikes/spk-06-long-running-app-intents.zsh --active-test
git diff --check
```

Additional hygiene checks:

```sh
git ls-files | xargs grep -n "<private-home-prefix>" || true
pgrep -fl "SPK06Prototype .* worker" || true
```

## Result

Read-only validation passed: Xcode, Swift, the macOS SDK, the AppIntents
framework, minimal `AppIntent`, and `AppShortcutsProvider` compile availability
were confirmed.

Active validation passed: a typed request was accepted immediately, a request ID
was returned, status/result retrieval worked, cancellation was idempotent,
invalid bindings and unknown request IDs were rejected, and artifact-owned
worker restart recovery completed a persisted request.

## Decision

The selected model is:

1. App Intent validates a versioned, allowlisted binding.
2. App Intent creates a request ID and sends a typed request to the Bridge over
   XPC.
3. Bridge returns accepted/request ID immediately.
4. Bridge-owned worker manages long-running Hermes lifecycle.
5. Status, result retrieval, and cancellation are separate typed operations.
6. Audit records use request ID, binding ID, and lifecycle state while redacting
   private inputs and result content.

`SPK-06 VERDICT: CONDITIONAL GO`

The condition is that real Siri/App Intent runtime behavior still requires a
signed installed app bundle, App Shortcuts/Siri registration, and user-facing
runtime validation.
