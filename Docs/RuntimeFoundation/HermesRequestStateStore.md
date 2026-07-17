# HermesRequestStateStore Runtime Foundation

## Purpose

`HermesRequestStateStore` is the durable typed state layer for Bridge-owned
long-running Hermes requests. It supports App Intent immediate handoff, status
queries, cancellation, result availability metadata, restart recovery, and
redacted lifecycle audit metadata.

The store is intentionally narrow. It is not a prompt database, generic JSON
payload store, job execution framework, protocol client, process supervisor, or
remote API.

## Record Schema

Records use schema version `1` and are keyed by `HermesRequestID`.

Stored fields are:

- schema version;
- request ID;
- binding ID;
- lifecycle state;
- created, updated, started, and completed timestamps;
- optional backend session ID;
- optional process launch UUID;
- cancellation-requested flag;
- redacted failure metadata;
- result metadata;
- revision number for optimistic update control.

The schema does not contain backend session tokens, prompts, raw result bodies,
stdout, stderr, approval secrets, Keychain values, arbitrary caller paths, or
generic JSON payloads.

Unsupported future schema versions are rejected instead of migrated
implicitly.

## Lifecycle Transition Graph

Supported states are:

- `accepted`
- `queued`
- `starting`
- `running`
- `waitingForApproval`
- `cancelling`
- `cancelled`
- `completed`
- `failed`
- `interrupted`

Valid transitions are:

```text
accepted -> queued
accepted -> failed
accepted -> cancelling
queued -> starting
queued -> cancelling
queued -> failed
starting -> running
starting -> cancelling
starting -> failed
running -> waitingForApproval
running -> cancelling
running -> completed
running -> failed
running -> interrupted
waitingForApproval -> running
waitingForApproval -> cancelling
waitingForApproval -> failed
waitingForApproval -> interrupted
cancelling -> cancelled
cancelling -> failed
cancelling -> interrupted
```

Terminal states are `cancelled`, `completed`, `failed`, and `interrupted`.
Terminal records cannot return to running states. Repeated terminal writes with
identical metadata are idempotent; conflicting terminal writes fail.

## Cancellation Semantics

Cancellation is a typed request-state operation. For nonterminal records it
sets `cancellationRequested` and transitions to `cancelling`. Repeating the
cancellation request is idempotent. `markCancelled` is valid only from the
`cancelling` state or as an identical repeat on an already cancelled record.

The store records intent to cancel. It does not signal processes, call the
Hermes protocol, or decide whether work should be resubmitted.

## Failure And Result Redaction

`HermesRequestFailure` stores only:

- category;
- stable bounded code;
- bounded safe message;
- retryable flag.

It must not contain stack traces, tokens, credentials, raw stderr, private
prompts, or unbounded diagnostics.

`HermesRequestResultMetadata` stores metadata only:

- result availability;
- completion timestamp;
- optional bounded content classification;
- optional redacted summary;
- optional Bridge-owned result locator.

Arbitrary result bodies are out of scope for this component.

## Atomic Persistence

`FileBackedHermesRequestStateStore` uses one caller-supplied Bridge-owned
storage root. The root must be a directory and must not be a symbolic link.
The store creates missing roots with restrictive permissions where supported.

Each record is written as one schema-versioned JSON file. Filenames are derived
deterministically from the validated request ID and a fixed `.json` extension.
The implementation never accepts caller-supplied filenames or paths for
records.

Writes use a temporary file in the storage root followed by POSIX `rename` to
replace the destination atomically. Successful writes leave no temporary state
files. Record size and record count are bounded. Existing symlinks under the
root are rejected to prevent storage-boundary escape.

## Concurrency Model

The production file-backed implementation is an actor. All mutations are
serialized through that actor, and each mutation checks the current revision
before writing when an expected revision is supplied.

`InMemoryHermesRequestStateStore` uses the same typed operations and transition
logic for deterministic unit and composition tests.

## Recovery Classification

Startup recovery lists records with typed decisions:

- `resumeEligible` for accepted or queued records;
- `reconcileWithSupervisor` for starting records and running records without a
  backend session ID;
- `reconcileWithProtocolClient` for running, waiting, or cancelling records
  with a backend session ID;
- `markInterrupted` is reserved for the later orchestrator policy that decides
  to stop tracking an unrecoverable nonterminal record;
- `noActionTerminal` for terminal records.

Recovery classification never infers that Hermes should rerun or resubmit a
prompt merely because a record is nonterminal.

## Retention Policy

Terminal records are retained until an explicit `HermesRequestRetentionPolicy`
prunes records older than the configured terminal age. Pruning is bounded by a
maximum count per call.

Nonterminal records are not pruned by this component.

## Relationship To SPK-06

SPK-06 selected the App Intent handoff model where Siri or Shortcuts returns an
accepted request ID quickly and Bridge-owned runtime infrastructure continues
the long-running work. This store implements the durable request-state layer
needed by that model without implementing App Intents, XPC, orchestration, or
real Siri runtime behavior.

## Relationship To Supervisor And Protocol Client

`HermesProcessSupervisor` owns process launch and shutdown. This store records
only the process launch UUID needed to correlate state with a supervised
launch.

`HermesProtocolClient` owns WebSocket and JSON-RPC calls. This store records
only the backend session ID. It never stores the backend session token and
never performs protocol calls.

## Explicit Non-Goals

This component does not implement:

- prompt persistence;
- arbitrary result body storage;
- generic key-value storage;
- arbitrary JSON payload storage;
- process management;
- WebSocket, REST, or JSON-RPC calls;
- automatic prompt replay;
- Keychain access;
- browser automation;
- GUI computer use;
- arbitrary shell, AppleScript, JXA, or executable-path execution.
