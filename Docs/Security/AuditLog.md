# Audit Log

Hermes Bridge records bounded structured audit events for lifecycle, request,
approval, file authorization, file subscription, Doctor, emergency-stop and
export operations.

## Schema

Each event is JSON encoded with:

- schema version;
- event ID;
- timestamp;
- event kind;
- actor;
- safe correlation ID;
- safe request/root/subscription identifiers where relevant;
- outcome;
- stable reason code;
- bounded redacted metadata.

The current file format is append-only JSONL in the Bridge-owned
`Logs/Audit` root.

## Privacy Boundary

Audit events must never persist:

- Prompts;
- result bodies;
- backend tokens;
- bookmark bytes;
- file contents;
- absolute root paths;
- raw stdout or stderr;
- arbitrary environment;
- arbitrary exception text;
- certificate private data.

Metadata keys and values are bounded and validated before writing. Unsafe keys
such as prompt, token, bookmark, stdout, stderr, environment, content and path
are rejected.

## Store

`FileBackedHermesAuditStore` provides:

- Bridge-owned root creation with mode `0700`;
- symlink-root rejection;
- actor-isolated append;
- JSONL schema validation on read;
- corrupt-record skipping;
- safe partial-tail recovery;
- deterministic time, kind and correlation-ID queries;
- maximum file size;
- maximum retained files;
- maximum retained event count;
- atomic-style rotation by renaming the active log.

There is no arbitrary predicate language and no generic file-read API.

## Export

Audit export is explicit and typed:

- bounded query;
- allowed event kinds through `HermesAuditQuery`;
- output directory selected by the UI or supplied by a trusted caller;
- JSON or JSONL output;
- manifest with SHA-256 checksum;
- export event audited;
- no automatic upload.

## Limitations

The audit system is local and append-only at the application level. It is not a
tamper-proof ledger. Future hardening should add signing of rotated segments,
operator-visible retention policy configuration, and release installer
ownership checks.
