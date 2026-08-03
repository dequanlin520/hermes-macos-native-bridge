# M14-011 External Installation Checklist

Use this checklist for deterministic second-Mac validation of the unsigned RC1 handoff. The target machine should be an Apple Silicon Mac with a clean standard user account, no existing Hermes Bridge installation, and Hermes Agent 0.18.2 available through a documented `PATH`.

## Preconditions

- Confirm the artifact filename is `Hermes-macOS-Native-Bridge-0.1.0-rc.1-unsigned.zip`.
- Confirm `release-manifest.json` reports `DISTRIBUTION_CLASSIFICATION=unsigned-internal-validation` or `distributionClassification` as `unsigned-internal-validation`.
- Confirm `PUBLIC_DISTRIBUTION_ALLOWED=no`.
- Confirm the operator acknowledges the artifact is unsigned, not notarized, and not for general public installation.
- Confirm no existing Hermes Bridge app, LaunchAgent, service binary, or bridge support directory is present for the test account.
- Confirm the real `~/.hermes` directory is not read, modified, moved, or deleted during the test.

## Installation Test

1. Copy the ZIP and `SHA256SUMS` to the clean standard user account.
2. Run `shasum -a 256 -c SHA256SUMS` from the directory containing the ZIP.
3. Record checksum success or mismatch as sanitized evidence.
4. Open or extract the ZIP without using `sudo`.
5. Observe Gatekeeper behavior for the unsigned build.
6. Classify expected unsigned Gatekeeper warnings separately from functional failures.
7. Do not use `xattr -dr com.apple.quarantine` as the normal installation workflow.
8. Copy/install the app with the bundled user-scoped install script.
9. Confirm the LaunchAgent asset is installed for the current user only.
10. Launch the app for the first time.
11. Confirm XPC connection to the Bridge service.
12. Confirm Hermes executable discovery and version discovery report Hermes Agent 0.18.2.
13. Start the isolated Hermes Agent through the Bridge.
14. Confirm readiness/status visibility through `/api/status`.
15. Quit and relaunch the app.
16. Restart the service and confirm reconnect.
17. Stop the exact isolated Agent started by the Bridge.
18. Run the bundled uninstall script.
19. Confirm app, LaunchAgent, bridge support files, and bridge logs are removed or accounted for.
20. Confirm real `~/.hermes` isolation: no profile data was accessed, changed, or required.

## Failure Classification

- Expected unsigned Gatekeeper warning: macOS warning attributable to unsigned or unnotarized code, with no evidence of product malfunction after explicit operator acknowledgement.
- Functional failure: install, LaunchAgent load, first launch, XPC connection, Hermes discovery, isolated Agent start, readiness/status, reconnect, exact Agent stop, or uninstall does not work as specified.
- Security boundary failure: use of `sudo`, another user account modification, real Keychain access, real Hermes profile access, Gatekeeper weakening, arbitrary shell execution, arbitrary AppleScript/JXA, GUI computer use, browser automation, or broad process control.
- Environmental incompatibility: non-Apple-Silicon hardware, unsupported macOS baseline, missing Hermes Agent 0.18.2 on documented `PATH`, account policy restrictions, or local endpoint conflicts not caused by the Bridge.

## Sanitized Evidence

Collect only privacy-safe evidence:

- Checksum verification result
- macOS version category
- Apple Silicon confirmation
- Hermes Agent version string
- XPC protocol version
- Install/uninstall pass or failure classification
- Gatekeeper warning category
- Redacted screenshots only if needed
- Final residue checklist

Do not collect credentials, tokens, usernames, identity names, certificate hashes, absolute paths, Keychain items, real Hermes profiles, logs containing private data, or runtime acceptance state.
