# GitHub Secrets

Release signing and notarization credentials must be stored only as encrypted
GitHub Actions secrets.

Developer ID signing uses:

- `APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64`;
- `APPLE_DEVELOPER_ID_APPLICATION_PASSWORD`;
- `APPLE_SIGNING_IDENTITY`;
- `APPLE_TEAM_ID`.

Notarization may use App Store Connect API key credentials:

- `APPLE_API_KEY_ID`;
- `APPLE_API_ISSUER_ID`;
- `APPLE_API_PRIVATE_KEY_BASE64`.

Or Apple ID credentials:

- `APPLE_ID`;
- `APPLE_APP_SPECIFIC_PASSWORD`;
- `APPLE_TEAM_ID`.

Do not configure both notarization mechanisms for the same run unless the
workflow explicitly chooses one. Secret values must never be printed, committed,
or copied into release artifacts.

The signing script creates a temporary keychain under the runner temporary
directory with a randomized password, restricts the user search list to that
keychain for signing, imports only the Developer ID certificate, and deletes the
keychain in an exit trap.

