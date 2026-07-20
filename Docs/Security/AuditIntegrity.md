# Audit Integrity

Hermes Bridge audit integrity uses a deterministic SHA-256 hash chain over the
bounded file-backed audit store. It provides tamper-evidence for retained local
records. Signer authenticity is a separate layer described in
`Docs/Security/AuditSigning.md`.

## Canonical Event Encoding

The hashed event representation is versioned as canonical schema version `1`.
It includes, in fixed field order:

- audit event schema version;
- event ID;
- UTC ISO8601 timestamp normalized to whole seconds;
- event kind;
- actor;
- outcome;
- safe correlation, request, root and subscription identifiers;
- reason code;
- already-redacted metadata sorted by key.

The canonical bytes exclude filesystem location, active file name and other
transient storage details. Event construction still rejects unsupported schema
versions and unsafe metadata before records are persisted.

## Event Chain

Each persisted JSONL record contains the existing safe audit event plus a chain
link:

- chain schema version;
- segment ID;
- global sequence number;
- previous event digest;
- current event digest.

The first record links to the all-zero genesis digest when there is no previous
segment. After rotation, the first record in the next segment links to the
terminal digest of the previous segment.

## Segment Manifests

When a segment closes, Hermes writes an immutable manifest before activating the
next segment. The manifest includes:

- manifest schema version;
- segment ID;
- first and last sequence;
- event count;
- first and terminal event digests;
- previous segment manifest digest;
- segment file SHA-256;
- creation and close timestamps;
- optional signature metadata for finalized manifests only.

A manifest checksum sidecar records the SHA-256 of the manifest file. Previous
segment linkage uses manifest digests, while event linkage uses terminal event
digests.

## Signing And Trust Models

Unsigned hash chaining can show that retained records have not changed relative
to the local chain, but it must not be described as identity authentication.

Signed manifests add Hermes installation audit signer authenticity when a known
public trust anchor is available. This is not Apple Developer ID code signing.
Developer ID signing authenticates distributed binaries; audit manifest signing
authenticates finalized audit segment manifests.

`HermesKeychainAuditManifestSigner` uses a P-256 private key stored through
Security.framework. The private key is not exported. Public trust anchors carry
the public key, signer ID, fingerprint, active or retired state and checksum.

## Retention Anchors

Retention may remove old rotated segments according to the configured bounds.
The retained chain remains verifiable from the first retained record, but a
retention anchor issue may be reported to show that earlier history is outside
the retained window.

## Tail Recovery

An incomplete active-file tail can be reported as
`incompleteRecoverableTail`. This is distinct from confirmed corruption. Closed
segment truncation, invalid JSON in closed segments, digest mismatches,
sequence gaps and broken previous-digest links are reported as corrupted
history and are not silently repaired.

## Verification Report

Verification is read-only and emits only bounded safe summaries:

- integrity state, including signed, unsigned and signer-failure states;
- verified segment count;
- verified event count;
- safe issue codes;
- verification timestamp.

It never exposes raw corrupt records or private filesystem paths.
