# AGENTS.md

## Project

This repository contains Hermes macOS Native Bridge, a native macOS control
plane and system bridge for Hermes Agent.

## V0.1 scope

The project is limited to:

1. Hermes lifecycle management.
2. Siri and Shortcuts calling Hermes.
3. Hermes calling explicitly approved macOS Shortcuts.
4. macOS system event ingestion.
5. Permissions and environment diagnostics.
6. Native menu bar controls.
7. Pause, stop, emergency stop, audit and diagnostics.

## Explicit non-goals

Do not implement:

- GUI computer use;
- browser automation;
- general AppleScript or JXA execution;
- arbitrary shell execution;
- arbitrary executable paths;
- Hermes Desktop replacement;
- knowledge-base or manufacturing features;
- remote control APIs.

## Engineering rules

- Work only inside the current repository.
- Do not read `~/.hermes`, Keychain, browser data, or unrelated user files.
- Do not commit, push, merge, or modify GitHub unless the task explicitly
  permits it.
- Do not add production dependencies without documenting the reason.
- Prefer small, reviewable changes.
- Preserve the security boundary.
- Use versioned contracts for IPC and external protocols.
- Never log secrets.
- Never implement a generic process execution API.

## Current phase

The current phase is repository governance and technical validation.

Do not create product runtime code unless the assigned issue explicitly asks
for it.

Governance tasks may add or update repository policy, issue templates,
pull-request templates, ADR documentation, and maintenance scripts. They must
not add Bridge runtime behavior, macOS integration code, or execution paths
unless the assigned issue explicitly changes the current phase and scope.
