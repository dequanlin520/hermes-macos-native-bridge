# Security Policy

Do not submit API keys, access tokens, private prompts, private file paths,
credentials, or unredacted diagnostic packages through public GitHub issues.

The project must not expose:

- arbitrary shell execution;
- arbitrary executable paths;
- general AppleScript or JXA execution;
- GUI computer use;
- browser automation;
- unauthenticated remote control interfaces.

A private vulnerability reporting mechanism will be established before the
first public preview release.

## Release signing secrets

Developer ID certificates, Apple account credentials, App Store Connect API
keys, app-specific passwords, and decoded key material must only be stored as
encrypted GitHub Actions secrets. They must never be committed, echoed, printed
to logs, or copied into release artifacts.

Release-candidate workflows may produce unsigned/ad-hoc conditional artifacts
when credentials are unavailable. Production workflows must fail before
publication if Developer ID signing, notarization, staple verification, or
Gatekeeper assessment cannot be completed.
