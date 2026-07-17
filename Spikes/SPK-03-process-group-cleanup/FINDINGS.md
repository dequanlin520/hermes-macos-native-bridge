# SPK-03 Findings

## Active Result

The active test executed on the research Mac and produced executable evidence
under `artifacts/spk-03/20260717T033309Z-38879/`.

```text
SPK03_ACTIVE_RESULT=PASS
PARENT_ONLY_LEAVES_DESCENDANTS=yes
PROCESS_GROUP_TERM_CLEAN=yes
PROCESS_GROUP_KILL_ESCALATION_CLEAN=yes
ESCAPED_DESCENDANT_OBSERVED=yes
IDENTITY_VERIFICATION_AVAILABLE=yes
SPK03_SELECTED_OWNERSHIP_MODEL=dedicated-process-group-with-pid-pgid-launch-identity-term-then-kill-and-escaped-descendant-detection
```

## Scenario A - Parent PID Only

Terminating only the parent PID left descendants alive. The child and grandchild
remained marked experiment processes after the parent exited and had to be
cleaned by their individually recorded and verified PIDs.

Observed process tree before signaling:

```text
role        PID    PPID   PGID   SID
parent      39033  38879  38879  0
child       39035  39033  38879  0
grandchild  39036  39035  38879  0
```

After parent-only `SIGTERM`:

```text
child_alive_after_parent_term=yes
grandchild_alive_after_parent_term=yes
```

Result: parent-PID-only shutdown is insufficient for a process tree.

## Scenario B - Owned Process Group

The helper created a distinct process group for the owned subprocess tree. The
parent, child, and grandchild shared the owned PGID. Before signaling, the
script verified that the group contained only marked experiment processes.

Sending `SIGTERM` to the negative verified PGID cleaned the parent, child, and
grandchild, and no marked process remained for the scenario.

Observed process tree before signaling:

```text
role        PID    PPID   PGID   SID
parent      39109  38879  39109  0
child       39111  39109  39109  0
grandchild  39112  39111  39109  0
```

Owned PGID: `39109`.

Result: verified owned-process-group shutdown cleans normal descendants.

## Scenario C - SIGTERM-Resistant Child

The child and grandchild installed a `SIGTERM` ignore handler. `SIGTERM` to the
verified owned process group did not complete cleanup within the bounded wait.
Escalating with `SIGKILL` to the same verified owned PGID cleaned all remaining
marked descendants.

Observed process tree before signaling:

```text
role        PID    PPID   PGID   SID
parent      39188  38879  39188  0
child       39190  39188  39188  0
grandchild  39191  39190  39188  0
```

After group `SIGTERM`, the parent exited, while the child and grandchild
remained in PGID `39188`. Group `SIGKILL` cleaned both survivors.

Result: bounded `SIGTERM` followed by `SIGKILL` against the same verified group
is required for resistant descendants.

## Scenario D - Escaped Descendant

The child called `setsid()`, creating a new session and process group before
forking the grandchild. Signaling the original owned process group cleaned the
original parent but did not reach the escaped child or grandchild. The script
then cleaned those survivors only through their recorded and verified PIDs.

Observed process tree before signaling:

```text
role        PID    PPID   PGID   SID
parent      39273  38879  39273  0
child       39275  39273  39275  0
grandchild  39276  39275  39275  0
```

The parent owned PGID was `39273`; the escaped child and grandchild were in
PGID `39275`. After signaling only PGID `39273`:

```text
child_alive_after_original_group_term=yes
grandchild_alive_after_original_group_term=yes
```

Result: an escaped descendant is an explicit residual risk. Group ownership
does not clean a descendant that deliberately leaves the owned group.

## Identity Verification

Before signaling, the script recorded and verified:

- PID;
- PPID;
- PGID;
- SID;
- process start time from `ps -o lstart`;
- command line containing a unique experiment marker;
- membership in the artifact-owned process tree.

PID reuse is mitigated by rechecking the live process command marker immediately
before signaling. PGID reuse or collision is mitigated by refusing to signal a
group if any live member lacks the unique experiment marker. A production
supervisor should retain stronger launch identity where available, including
PID, PGID, executable identity, start time, and an internal launch nonce.

## Security Implications

PID-only shutdown can leave Bridge-owned descendants running after the Bridge
believes shutdown completed. Process-group shutdown is safer and more complete,
but only when the group is created specifically for the Bridge-owned launch and
verified before each signal. The supervisor must never signal by process name or
unverified PGID, and it must fail closed when identity verification is
ambiguous.

## Recommendation

HermesProcessSupervisor should create a dedicated process group for every
Bridge-owned Hermes launch, retain PID plus PGID plus launch identity, send
`SIGTERM` to only the verified owned process group, wait for bounded shutdown,
and escalate with `SIGKILL` only to the same verified owned group.

The supervisor should also detect descendants that escape the owned process
group. Escaped descendants should be treated as residual risk and cleaned only
when their exact recorded identity can be verified.

SPK-03 VERDICT: CONDITIONAL GO
