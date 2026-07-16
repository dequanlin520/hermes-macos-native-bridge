# Development Workflow

Development is issue-driven and pull-request-driven.

## Standard Flow

1. Open or select a scoped issue.
2. Create one branch for that issue.
3. Keep changes small and reviewable.
4. Add or update tests for behavior changes.
5. Open a pull request using the repository template.
6. Document validation commands and results in the pull request.

## Scope and Security

All work must stay within `Docs/PRODUCT-SCOPE.md`.

Do not add or broaden:

- arbitrary shell execution;
- arbitrary executable paths;
- general AppleScript or JXA execution;
- GUI computer use;
- browser automation;
- unauthenticated remote control interfaces.

Changes that affect execution, permission, IPC, data, dependency, or product
scope boundaries require an ADR or linked ADR issue before implementation.

## Governance and Spike Work

Governance tasks may update repository policy, issue templates, pull-request
templates, ADR documentation, and maintenance scripts.

Technical spikes must be time-boxed and must document:

- the validation question;
- evidence gathered;
- risks found;
- recommended follow-up work;
- whether product implementation should proceed.

Spike issues must not become product runtime implementation work unless a
follow-up issue explicitly authorizes that scope.

## Secrets and Diagnostics

Never commit secrets, access tokens, credentials, private prompts, private file
paths, or unredacted diagnostic packages. Public issues and pull requests must
use redacted examples.
