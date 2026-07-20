# Audit Signing Operations

M6-004 makes Keychain-backed audit signing an explicit operational setup, not
an automatic launch side effect.

## Access Policy

`HermesAuditKeyAccessPolicy` records safe metadata only:

- current app and service code identity summaries;
- signing policy: `signingRequired`, `signingPreferred`, or
  `unsignedAllowedForLegacyOnly`;
- access-policy state;
- whether a setup test signature proved non-interactive signing;
- the last successful signature timestamp.

It does not contain private-key references, persistent Keychain references,
passwords, prompts, executable paths, tokens, or raw certificate material.

Access-policy states are typed:

- `setupRequired`;
- `configuredForCurrentApp`;
- `configuredForCurrentService`;
- `configuredForAppAndService`;
- `locked`;
- `identityMismatch`;
- `inaccessible`;
- `unsupported`.

Where Security.framework supports trusted-application ACLs, setup configures
the audit signing key for the intended Hermes app and service identities. Empty
or broad application access is rejected.

## Explicit Setup

`configureAuditSigningAccess` is the only setup operation. It:

1. evaluates the current app and optional service code identity;
2. creates or locates the active P-256 signing key;
3. applies the narrow trusted-application access policy;
4. performs a test signature;
5. verifies the signature;
6. persists safe policy metadata;
7. writes an `auditSigningAccessConfigured` audit event;
8. reports whether future signing is expected to be non-interactive.

Setup is not run automatically at process launch.

## Unattended Signing

When signing is required, lookup checks the default Keychain lock state through
public Security.framework APIs before returning a signer. A locked or
inaccessible Keychain fails closed with a typed state. Required signing never
falls back to unsigned manifests. Unsigned compatibility is limited to explicit
`signingPreferred` or `unsignedAllowedForLegacyOnly` policy.

## Status Surfaces

CLI, Doctor, and menu-bar status expose only safe fields:

- active signer ID and fingerprint prefix;
- access-policy state;
- signing-required policy;
- non-interactive proof;
- last successful signature time;
- rotation transaction state;
- recovery operation;
- release identity validation result.

Private keys and Keychain references are never displayed.
