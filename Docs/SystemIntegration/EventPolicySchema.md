# Event Policy Schema

The file-backed policy store persists one bounded JSON document:

```text
event-policies.v1.json
```

The root is Bridge-owned, rejects symlink roots and is created with restrictive
permissions. Writes are actor-isolated and atomic.

## Store Invariants

- schema version must be `v1`;
- maximum policy count is 64;
- policy IDs are unique;
- policy revisions are positive integers;
- create starts at revision 1;
- update/enable/disable/remove support expected-revision conflict checks;
- disabled policies are retained but ignored by evaluation;
- corrupt or unsupported documents are rejected;
- policies contain no secret fields.

## Policy Fields

Each policy contains:

- schema version;
- `hepol_` policy ID;
- revision;
- enabled state;
- execution mode;
- fixed conditions;
- fixed actions;
- cooldown seconds;
- maximum executions per minute;
- duplicate-suppression flag;
- approval requirement;
- created and updated timestamps.

The schema intentionally has no arbitrary JSON blob, script body, executable
path, environment, dynamic predicate or raw event field.
