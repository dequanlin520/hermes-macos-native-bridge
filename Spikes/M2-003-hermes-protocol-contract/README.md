# M2-003 Hermes Protocol Contract Spike

## Question

What backend protocol contract does installed Hermes expose to clients, and is
it concrete enough to implement a narrow `HermesProtocolClient`?

## Method

1. Resolve the allowlisted `hermes` executable from `PATH`.
2. Run the fixed `hermes --version` probe.
3. Resolve the executable target and installed package source root.
4. Inspect installed package source, metadata, and bundled docs only.
5. Record source-relative paths, decorators, symbols, and concise schemas.
6. Launch an isolated Hermes server only after source proves safe routes.
7. Probe only fixed source-proven routes:
   - `GET /api/status`
   - unauthenticated WebSocket upgrade attempt to `/api/ws`

## Artifacts

Generated logs and source extracts are written to:

```text
artifacts/m2-003/
```

The directory is intentionally ignored by Git.

## Safety

This spike does not read the real user Hermes state intentionally, does not
read Keychain or browser data, does not use real credentials, does not submit a
prompt, and does not invent endpoint paths.

## Result

M2-003 VERDICT: GO

The backend protocol is confirmed as FastAPI HTTP plus JSON-RPC 2.0 over
WebSocket `/api/ws`. The implementation scope remains narrow and must honor the
confirmed authentication and event contracts.
