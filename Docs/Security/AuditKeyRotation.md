# Audit Key Rotation

Audit signing-key rotation is an explicit operation. Hermes Bridge does not
replace valid signing keys automatically and does not delete old keys
automatically.

The rotation flow is:

1. Finalize the active audit segment.
2. Sign that segment with the current active audit signing key.
3. Create a replacement P-256 signing key in the current user's Keychain.
4. Retain the old public trust anchor as retired verification data.
5. Emit a typed `auditSigningKeyRotated` audit event.
6. Activate the new signer for subsequent segment manifests.
7. Keep historical segments verifiable through retained public trust anchors.

Verification distinguishes `verifiedUnsigned`, `verifiedSigned`,
`retiredSignerValid`, `signatureUnavailable`, `signatureInvalid`,
`unknownSigner` and `keyUnavailable`.

Unsigned historical segments remain unsigned. They are not reinterpreted as
signed after a key is created.
