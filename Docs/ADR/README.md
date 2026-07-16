# Architecture Decision Records

ADRs capture decisions that affect architecture, security boundaries, IPC
contracts, execution surfaces, dependencies, or product scope.

## When to Write an ADR

Create or update an ADR when a change:

- broadens or changes an execution or permission boundary;
- adds or changes an IPC or external protocol contract;
- adds a production dependency;
- changes the product scope or explicit non-goals;
- creates a long-lived architecture constraint.

## Format

Use short Markdown files in this directory with numeric prefixes:

```text
0001-title-in-kebab-case.md
```

Recommended sections:

```markdown
# ADR-0001: Title

## Status

Proposed | Accepted | Superseded

## Context

## Decision

## Consequences
```

## Rules

- Keep ADRs focused on decisions, not implementation notes.
- Link related issues and pull requests.
- Document security and privacy consequences explicitly.
- Do not use ADRs to bypass `Docs/PRODUCT-SCOPE.md`.
