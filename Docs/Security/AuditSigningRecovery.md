# Audit Signing Recovery

Audit signing recovery is explicit and typed. Recovery operations must not
delete audit history and must not export private keys.

## Operations

- `recreateMissingSigningKey`: creates a replacement signing key when no active
  private key is available.
- `importPublicTrustAnchors`: imports public trust anchors from a safe backup.
- `retireUnknownSigner`: marks an unknown public signer as retired after
  operator review.
- `resumeInterruptedRotation`: continues a crash-safe rotation transaction.
- `abandonIncompleteRotation`: discards incomplete rotation metadata when no
  state change was committed.
- `resetAuditSigningConfiguration`: removes setup metadata and rotation
  transaction metadata after explicit confirmation.

`resetAuditSigningConfiguration` is destructive for configuration only. It does
not delete audit events, segment manifests, or public trust anchors.

## Backup Rules

Private-key backup and export are forbidden. Public trust-anchor backup and
import are allowed because trust anchors contain only public verification data,
state, generation ID, and checksum.

## Rotation Transactions

Rotation persists a typed transaction with these stages:

- `prepared`;
- `oldSegmentFinalized`;
- `newKeyCreated`;
- `oldAnchorRetired`;
- `newAnchorActivated`;
- `rotationEventWritten`;
- `completed`.

On restart, the coordinator detects incomplete rotation metadata. It resumes
where the saved stage is safe to continue, or reports a fixed recovery action.
The trust-anchor store retires existing active anchors before activating a new
anchor, so two current signers are not activated. Retired public anchors remain
available for historical verification.
