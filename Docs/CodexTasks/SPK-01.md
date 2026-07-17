You are working on GitHub Issue #3:

SPK-01 — Validate managed Hermes Gateway.

This is a technical spike, not product implementation.

Read before working:

- AGENTS.md
- README.md
- SECURITY.md
- Docs/PRODUCT-SCOPE.md
- Docs/DEVELOPMENT-WORKFLOW.md
- GitHub Issue #3, if available through gh

Goals:

Validate whether the locally installed Hermes Agent can be safely managed by a future macOS Bridge Agent as an isolated child process.

The spike must investigate:

1. Hermes binary discovery.
2. Hermes version and installation metadata.
3. Available CLI commands and flags.
4. Profile selection.
5. API host configuration.
6. API port configuration.
7. API authentication/key configuration.
8. Configuration precedence:
   - command-line arguments;
   - environment variables;
   - profile configuration;
   - defaults.
9. Health endpoint.
10. Detailed readiness endpoint.
11. Capabilities endpoint.
12. Run creation.
13. Run status.
14. Event streaming or SSE.
15. Run stop/cancel.
16. Approval support.
17. Normal gateway shutdown.
18. Abnormal gateway termination.
19. Port cleanup.
20. Whether Bridge-managed configuration can avoid modifying the user's existing Hermes configuration.

Required deliverables:

- Spikes/SPK-01-managed-gateway/README.md
- Spikes/SPK-01-managed-gateway/FINDINGS.md
- Scripts/spikes/spk-01-managed-gateway.zsh
- Docs/ADR/ADR-0003-hermes-http-runs-api.md as a proposed ADR only if evidence supports a decision

Script requirements:

- Default mode must be read-only.
- Active tests require explicit `--active-test`.
- Temporary files must stay under `artifacts/spk-01/`.
- Do not commit artifacts.
- Use trap-based cleanup.
- Track only PIDs started by the spike.
- Never use `killall hermes`.
- Never use `pkill hermes`.
- Never terminate an external Hermes process.
- Never modify ~/.hermes.
- Never modify Hermes profiles.
- Never modify LaunchAgents.
- Never read Keychain.
- Never print API keys or tokens.
- Never create product Swift code.
- Never commit, push, or modify GitHub.

Before active testing:

- inspect `hermes --version`;
- inspect `hermes --help`;
- inspect relevant subcommand help;
- document exactly which command and API surfaces are confirmed;
- do not assume endpoints exist.

Validation:

- zsh -n Scripts/spikes/spk-01-managed-gateway.zsh
- git diff --check
- run read-only mode
- do not run --active-test automatically
- document unsupported or ambiguous capabilities explicitly

Final report:

- confirmed facts;
- failed assumptions;
- unsupported capabilities;
- security implications;
- process-lifecycle implications;
- recommended Hermes Adapter shape;
- recommendation for ADR-003 and ADR-004;
- P0 blockers;
- whether M2 Runtime Foundation may proceed.

Do not implement the production Bridge.
