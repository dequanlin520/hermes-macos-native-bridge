# Audit Signing

Hermes Bridge can sign finalized audit segment manifests with a Bridge-owned
P-256 key stored by macOS Security.framework. The private key remains in the
current user's Keychain and is never exported through Hermes product models.

Audit signing is separate from:

- hash-chain integrity, which detects tampering in retained audit records and
  segment manifests;
- Hermes installation audit signer authenticity, which proves that a finalized
  segment manifest was signed by a known Hermes Bridge audit key;
- Apple Developer ID code signing, which authenticates the app or executable
  bundle distributed by Apple platform tooling.

## Key Material

The production provider uses a fixed Hermes Bridge application-tag namespace:

```text
com.hermes.bridge.audit.signing.p256
```

Keys are P-256 signing keys. Lookup is by exact Hermes signer ID and key
generation identifier; the provider does not enumerate unrelated Keychain
items. Lookup, creation and rotation are explicit. Missing, duplicate, locked
and inaccessible Keychain states are represented as typed states.

Private keys are never returned as raw bytes. Public verification data may be
exported as trust anchors.

## Manifest Signature

Only closed segment manifests are signed. The active audit segment remains
mutable and is never treated as finalized.

Signed manifest metadata includes signer ID, algorithm identifier, SHA-256
public-key fingerprint, encoded ECDSA signature, signing timestamp and key
generation identifier.

The signed payload is the canonical finalized segment-manifest digest computed
with signature metadata omitted.

## Trust Anchors

Public trust anchors contain only schema version, signer ID, algorithm, public
key, SHA-256 public-key fingerprint, creation timestamp, active or retired
state, key generation identifier and checksum.

Trust anchors do not contain private-key bytes or private-key persistent
references.

## Operational Setup

M6-004 adds an explicit setup operation described in
`Docs/Security/AuditSigningOperations.md`. `configureAuditSigningAccess` is
required before unattended per-user service signing is considered ready. It
verifies code identity, applies the narrowest supported Keychain
trusted-application access policy, performs and verifies a test signature, and
records only safe access-policy metadata.

Hermes Bridge does not configure audit signing access automatically at launch.
When `signingRequired` is configured, locked, missing, inaccessible, or
identity-mismatched signing state fails closed and is reported as typed state.
Unsigned compatibility remains available only under explicit legacy/preferred
policy.

Private-key backup and export remain forbidden. Public trust-anchor export and
import are allowed for verification recovery.
