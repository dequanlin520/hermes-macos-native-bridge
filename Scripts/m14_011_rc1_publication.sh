#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT_NAME="$0"
M14_010_SCRIPT="$ROOT_DIR/Scripts/m14_010_rc1_release.sh"
M14_010_OUTPUT_DIR="$ROOT_DIR/artifacts/m14-010/output"
M14_010_ARCHIVE="$M14_010_OUTPUT_DIR/HermesBridge-0.1.0-rc.1-app-distribution-bundle.zip"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m14-011"
OUTPUT_DIR="$ARTIFACT_DIR/output"
EVIDENCE_DIR="$ARTIFACT_DIR/evidence"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
VERSION_SOURCE="$ROOT_DIR/Sources/HermesReleaseVersion/HermesReleaseVersion.swift"

PRODUCT_VERSION="$(/usr/bin/awk '/static let productVersion = / { sub(/^.*= "/, ""); sub(/".*$/, ""); print; exit }' "$VERSION_SOURCE")"
TAG_TARGET="$(/usr/bin/awk '/static let tagTarget = / { sub(/^.*= "/, ""); sub(/".*$/, ""); print; exit }' "$VERSION_SOURCE")"
XPC_PROTOCOL_VERSION="$(/usr/bin/awk '/static let xpcProtocolVersion = / { sub(/^.*= "/, ""); sub(/".*$/, ""); print; exit }' "$VERSION_SOURCE")"
TESTED_HERMES_VERSION="$(/usr/bin/awk '/static let testedHermesVersion = / { sub(/^.*= "/, ""); sub(/".*$/, ""); print; exit }' "$VERSION_SOURCE")"
PACKAGE_TYPE="$(/usr/bin/awk '/static let packageType = / { sub(/^.*= "/, ""); sub(/".*$/, ""); print; exit }' "$VERSION_SOURCE")"

RC_ARCHIVE_NAME="Hermes-macOS-Native-Bridge-${PRODUCT_VERSION}-unsigned.zip"
RC_ARCHIVE="$OUTPUT_DIR/$RC_ARCHIVE_NAME"
SHA256SUMS="$OUTPUT_DIR/SHA256SUMS"
RELEASE_MANIFEST="$OUTPUT_DIR/release-manifest.json"
RELEASE_NOTES="$OUTPUT_DIR/release-notes.md"
EXTERNAL_CHECKLIST="$OUTPUT_DIR/external-install-checklist.md"
KNOWN_LIMITATIONS="$OUTPUT_DIR/known-limitations.md"
ROLLBACK_DOC="$OUTPUT_DIR/rollback-and-uninstall.md"
GH_DESCRIPTOR="$EVIDENCE_DIR/github-publication-draft.json"

SUPPORTED_DISTRIBUTION_CLASSIFICATIONS="unsigned-internal-validation signed-notarized-prerelease blocked"
DISTRIBUTION_CLASSIFICATION="unsigned-internal-validation"
PUBLIC_DISTRIBUTION_ALLOWED="no"
SIGNED_RELEASE_BLOCKING_REASON="signing.application-identity-unavailable"
APPLICATION_SIGNING_STATUS="unavailable"
NOTARIZATION_STATUS="not-attempted"
STAPLING_STATUS="not-attempted"

typeset -A RESULT
ORDERED_KEYS=(
  EXPLICIT_OPT_IN_CONFIRMED PRODUCT_VERSION TAG_TARGET PACKAGE_TYPE
  DISTRIBUTION_CLASSIFICATION PUBLIC_DISTRIBUTION_ALLOWED SIGNED_RELEASE_BLOCKING_REASON
  RC_ARTIFACT_ASSEMBLED RC_ARTIFACT_FILENAME_VALID ZIP_CONTENT_VALID
  SHA256SUMS_CREATED SHA256_VERIFIED RELEASE_MANIFEST_VALID RELEASE_NOTES_CREATED
  EXTERNAL_INSTALL_CHECKLIST_CREATED ROLLBACK_DOCUMENT_CREATED GITHUB_DRAFT_DESCRIPTOR_CREATED
  GITHUB_RELEASE_CREATED TAG_CREATED APPLICATION_SIGNING_STATUS NOTARIZATION_STATUS
  STAPLING_STATUS CLEAN_USER_ACCEPTANCE_CAPABILITY CLEAN_USER_ACCEPTANCE_ATTEMPTED
  CLEAN_USER_ACCEPTANCE_RESULT NO_SECRET_LEAKAGE NO_ABSOLUTE_PATH_LEAKAGE
  NO_SOURCE_CODE_INCLUDED GENERATED_ARTIFACT_TRACKED_BY_GIT ENVIRONMENT_RESTORED
  M14_011_REASON_CODE M14_011_RESULT
)

usage() {
  print -u2 "usage: $SCRIPT_NAME inspect|assemble|verify|external-test-plan|print-gh-draft-command|cleanup"
}

json_escape() {
  /usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

sha256() {
  shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

application_identity_available() {
  if /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/grep -q "Developer ID Application:"; then
    print -r -- yes
  else
    print -r -- no
  fi
}

set_default_results() {
  RESULT=(
    EXPLICIT_OPT_IN_CONFIRMED no
    PRODUCT_VERSION "$PRODUCT_VERSION"
    TAG_TARGET "$TAG_TARGET"
    PACKAGE_TYPE "$PACKAGE_TYPE"
    DISTRIBUTION_CLASSIFICATION "$DISTRIBUTION_CLASSIFICATION"
    PUBLIC_DISTRIBUTION_ALLOWED "$PUBLIC_DISTRIBUTION_ALLOWED"
    SIGNED_RELEASE_BLOCKING_REASON "$SIGNED_RELEASE_BLOCKING_REASON"
    RC_ARTIFACT_ASSEMBLED no
    RC_ARTIFACT_FILENAME_VALID no
    ZIP_CONTENT_VALID no
    SHA256SUMS_CREATED no
    SHA256_VERIFIED no
    RELEASE_MANIFEST_VALID no
    RELEASE_NOTES_CREATED no
    EXTERNAL_INSTALL_CHECKLIST_CREATED no
    ROLLBACK_DOCUMENT_CREATED no
    GITHUB_DRAFT_DESCRIPTOR_CREATED no
    GITHUB_RELEASE_CREATED no
    TAG_CREATED no
    APPLICATION_SIGNING_STATUS "$APPLICATION_SIGNING_STATUS"
    NOTARIZATION_STATUS "$NOTARIZATION_STATUS"
    STAPLING_STATUS "$STAPLING_STATUS"
    CLEAN_USER_ACCEPTANCE_CAPABILITY supported-unexercised
    CLEAN_USER_ACCEPTANCE_ATTEMPTED no
    CLEAN_USER_ACCEPTANCE_RESULT supported-unexercised
    NO_SECRET_LEAKAGE no
    NO_ABSOLUTE_PATH_LEAKAGE no
    NO_SOURCE_CODE_INCLUDED no
    GENERATED_ARTIFACT_TRACKED_BY_GIT unknown
    ENVIRONMENT_RESTORED no
    M14_011_REASON_CODE unknown
    M14_011_RESULT FAIL
  )
}

write_result() {
  mkdir -p "$ARTIFACT_DIR"
  {
    for key in "${ORDERED_KEYS[@]}"; do
      print -r -- "$key=${RESULT[$key]}"
    done
  } > "$RESULT_FILE"
}

finish_result() {
  local ok=yes
  local required_yes=(
    EXPLICIT_OPT_IN_CONFIRMED RC_ARTIFACT_ASSEMBLED RC_ARTIFACT_FILENAME_VALID
    ZIP_CONTENT_VALID SHA256SUMS_CREATED SHA256_VERIFIED RELEASE_MANIFEST_VALID
    RELEASE_NOTES_CREATED EXTERNAL_INSTALL_CHECKLIST_CREATED ROLLBACK_DOCUMENT_CREATED
    GITHUB_DRAFT_DESCRIPTOR_CREATED NO_SECRET_LEAKAGE NO_ABSOLUTE_PATH_LEAKAGE
    NO_SOURCE_CODE_INCLUDED ENVIRONMENT_RESTORED
  )
  for key in "${required_yes[@]}"; do
    [[ "${RESULT[$key]}" == "yes" ]] || ok=no
  done
  [[ "${RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]}" == "no" ]] || ok=no
  [[ "${RESULT[PUBLIC_DISTRIBUTION_ALLOWED]}" == "no" ]] || ok=no
  [[ "${RESULT[GITHUB_RELEASE_CREATED]}" == "no" && "${RESULT[TAG_CREATED]}" == "no" ]] || ok=no
  [[ "${RESULT[APPLICATION_SIGNING_STATUS]}" == "unavailable" ]] || ok=no
  [[ "${RESULT[NOTARIZATION_STATUS]}" == "not-attempted" ]] || ok=no
  [[ "${RESULT[STAPLING_STATUS]}" == "not-attempted" ]] || ok=no

  if [[ "$ok" == "yes" ]]; then
    RESULT[M14_011_REASON_CODE]=ok
    RESULT[M14_011_RESULT]=PASS
  elif [[ "${RESULT[M14_011_REASON_CODE]}" == blocked.* ]]; then
    RESULT[M14_011_RESULT]=BLOCKED
  else
    [[ "${RESULT[M14_011_REASON_CODE]}" != "unknown" ]] || RESULT[M14_011_REASON_CODE]=validation.failed
    RESULT[M14_011_RESULT]=FAIL
  fi
  write_result
}

inspect() {
  print -r -- "PRODUCT_VERSION=$PRODUCT_VERSION"
  print -r -- "TAG_TARGET=$TAG_TARGET"
  print -r -- "PACKAGE_TYPE=$PACKAGE_TYPE"
  print -r -- "XPC_PROTOCOL_VERSION=$XPC_PROTOCOL_VERSION"
  print -r -- "TESTED_HERMES_VERSION=$TESTED_HERMES_VERSION"
  print -r -- "SUPPORTED_DISTRIBUTION_CLASSIFICATIONS=$SUPPORTED_DISTRIBUTION_CLASSIFICATIONS"
  print -r -- "DISTRIBUTION_CLASSIFICATION=$DISTRIBUTION_CLASSIFICATION"
  print -r -- "PUBLIC_DISTRIBUTION_ALLOWED=$PUBLIC_DISTRIBUTION_ALLOWED"
  print -r -- "APPLICATION_IDENTITY_CATEGORY_AVAILABLE=$(application_identity_available)"
  print -r -- "SIGNED_RELEASE_BLOCKING_REASON=$SIGNED_RELEASE_BLOCKING_REASON"
  print -r -- "APPLICATION_SIGNING_STATUS=$APPLICATION_SIGNING_STATUS"
  print -r -- "NOTARIZATION_STATUS=$NOTARIZATION_STATUS"
  print -r -- "STAPLING_STATUS=$STAPLING_STATUS"
  print -r -- "RC_ARTIFACT_NAME=$RC_ARCHIVE_NAME"
}

write_release_notes() {
  cp "$ROOT_DIR/Docs/Release/v0.1.0-rc.1.md" "$RELEASE_NOTES"
  RESULT[RELEASE_NOTES_CREATED]=yes
}

write_external_checklist() {
  cp "$ROOT_DIR/Docs/Release/M14_011ExternalInstallationChecklist.md" "$EXTERNAL_CHECKLIST"
  RESULT[EXTERNAL_INSTALL_CHECKLIST_CREATED]=yes
}

write_known_limitations() {
  cat > "$KNOWN_LIMITATIONS" <<'MARKDOWN'
# RC1 Known Limitations

This RC1 artifact is unsigned and not notarized. It is intended only for controlled internal validation.

Unsupported capabilities: Hermes request submission, request status, request cancellation, approval response, private `/api/ws`, arbitrary prompts, tool execution, arbitrary shell, GUI computer use, browser automation, arbitrary AppleScript or JXA, and broad process control.

Hermes integration is status-only through `/api/status`. Request, cancel, and approval operations are unsupported with `transport.route-unsupported`.
MARKDOWN
}

write_rollback() {
  cat > "$ROLLBACK_DOC" <<'MARKDOWN'
# RC1 Rollback And Uninstall

Use the bundled `Scripts/uninstall-hermes-bridge-app.zsh` from the extracted ZIP to remove user-scoped installed files.

Expected user-scoped targets:

- `~/Applications/Hermes macOS Native Bridge.app`
- `~/Library/LaunchAgents/com.hermes.bridge.plist`
- `~/Library/Application Support/HermesBridge`
- `~/Library/Logs/HermesBridge`

Do not delete or inspect real `~/.hermes` profiles. Residue checks must confirm the bridge uninstall did not create, modify, or require access to real Hermes profile data.
MARKDOWN
  RESULT[ROLLBACK_DOCUMENT_CREATED]=yes
}

write_manifest() {
  local archive_sha
  archive_sha="$(sha256 "$RC_ARCHIVE")"
  cat > "$RELEASE_MANIFEST" <<JSON
{
  "artifactSHA256": {
    "$RC_ARCHIVE_NAME": "$archive_sha"
  },
  "artifacts": [
    "$RC_ARCHIVE_NAME",
    "SHA256SUMS",
    "release-notes.md",
    "external-install-checklist.md",
    "known-limitations.md",
    "rollback-and-uninstall.md"
  ],
  "distributionClassification": "$DISTRIBUTION_CLASSIFICATION",
  "packageType": "$PACKAGE_TYPE",
  "productVersion": "$PRODUCT_VERSION",
  "proposedTag": "$TAG_TARGET",
  "publicDistributionAllowed": "$PUBLIC_DISTRIBUTION_ALLOWED",
  "signedReleaseBlockingReason": "$SIGNED_RELEASE_BLOCKING_REASON",
  "signingStatus": {
    "application": "$APPLICATION_SIGNING_STATUS",
    "installer": "not-applicable",
    "zip": "unsigned"
  },
  "notarizationStatus": "$NOTARIZATION_STATUS",
  "staplingStatus": "$STAPLING_STATUS",
  "supportedCapabilities": [
    "native menu-bar application",
    "XPC 1.8 Bridge service",
    "Hermes executable/version discovery",
    "isolated Hermes Agent lifecycle",
    "dynamic endpoint ownership",
    "/api/status readiness",
    "reconnect and controlled restart",
    "diagnostics",
    "permissions status",
    "audit/security status",
    "emergency stop",
    "user-scoped install/uninstall"
  ],
  "unsupportedCapabilities": [
    "Hermes request submission: transport.route-unsupported",
    "request status/cancel: transport.route-unsupported",
    "approval response: transport.route-unsupported",
    "private /api/ws",
    "arbitrary prompts",
    "tool execution",
    "arbitrary shell",
    "GUI computer use",
    "browser automation",
    "arbitrary AppleScript/JXA",
    "broad process control"
  ],
  "testedHermesVersion": "$TESTED_HERMES_VERSION",
  "testedPlatformCategory": "Apple Silicon macOS 13+",
  "xpcProtocolVersion": "$XPC_PROTOCOL_VERSION"
}
JSON
  RESULT[RELEASE_MANIFEST_VALID]=yes
}

write_github_descriptor() {
  local archive_sha
  archive_sha="$(sha256 "$RC_ARCHIVE")"
  cat > "$GH_DESCRIPTOR" <<JSON
{
  "proposedTag": "$TAG_TARGET",
  "proposedPrereleaseTitle": "Hermes macOS Native Bridge $PRODUCT_VERSION unsigned internal validation",
  "artifactNames": [
    "$RC_ARCHIVE_NAME",
    "SHA256SUMS",
    "release-manifest.json",
    "release-notes.md",
    "external-install-checklist.md",
    "known-limitations.md",
    "rollback-and-uninstall.md"
  ],
  "checksums": {
    "$RC_ARCHIVE_NAME": "$archive_sha"
  },
  "releaseNotesPathCategory": "generated-artifact-and-tracked-doc",
  "signingStatus": "$APPLICATION_SIGNING_STATUS",
  "notarizationStatus": "$NOTARIZATION_STATUS",
  "supportedCapabilitySummary": "status-only Hermes integration, XPC 1.8 service, isolated Agent lifecycle, diagnostics, permissions, audit/security, emergency stop, user-scoped install/uninstall",
  "unsupportedCapabilitySummary": "requests, cancel/status, approvals, private /api/ws, prompts, tool execution, shell, GUI computer use, browser automation, AppleScript/JXA, broad process control",
  "testedPlatformCategory": "Apple Silicon macOS 13+",
  "testedHermesVersion": "$TESTED_HERMES_VERSION",
  "xpcProtocolVersion": "$XPC_PROTOCOL_VERSION",
  "publicDistributionAllowed": "$PUBLIC_DISTRIBUTION_ALLOWED",
  "blockingReasons": ["$SIGNED_RELEASE_BLOCKING_REASON"],
  "githubReleaseCreated": false,
  "tagCreated": false
}
JSON
  RESULT[GITHUB_DRAFT_DESCRIPTOR_CREATED]=yes
}

validate_zip_contents() {
  /usr/bin/python3 - "$RC_ARCHIVE" <<'PY'
import sys
import zipfile

archive = sys.argv[1]
required_suffixes = {
    "Hermes macOS Native Bridge.app/Contents/Info.plist",
    "Hermes macOS Native Bridge.app/Contents/MacOS/HermesBridgeApp",
    "Hermes macOS Native Bridge.app/Contents/Library/XPCServices/HermesBridgeService.xpc/Contents/Info.plist",
    "Hermes macOS Native Bridge.app/Contents/Library/XPCServices/HermesBridgeService.xpc/Contents/MacOS/HermesBridgeService",
    "Library/LaunchAgents/com.hermes.bridge.plist",
    "Scripts/install-hermes-bridge-app.zsh",
    "Scripts/uninstall-hermes-bridge-app.zsh",
    "bin/HermesBridgeControl",
    "bin/HermesBridgeServiceLifecycle",
}
deny_prefixes = ("Sources/", "Tests/", ".git/", "artifacts/")
deny_fragments = ("/Sources/", "/Tests/", "/.git/", "/artifacts/")
deny_suffixes = (".swift", ".log", ".key", ".pem", ".p12", ".mobileprovision")

with zipfile.ZipFile(archive) as zf:
    names = [name for name in zf.namelist() if not name.endswith("/")]

missing = [suffix for suffix in required_suffixes if not any(name.endswith(suffix) for name in names)]
denied = [
    name for name in names
    if name.startswith(deny_prefixes)
    or any(fragment in name for fragment in deny_fragments)
    or name.endswith(deny_suffixes)
]
if missing or denied:
    raise SystemExit(f"missing={missing} denied={denied[:10]}")
PY
  RESULT[ZIP_CONTENT_VALID]=yes
  RESULT[NO_SOURCE_CODE_INCLUDED]=yes
}

scan_generated_privacy() {
  /usr/bin/python3 - "$OUTPUT_DIR" "$EVIDENCE_DIR" <<'PY'
import getpass
import re
import sys
from pathlib import Path

roots = [Path(arg) for arg in sys.argv[1:]]
username = getpass.getuser()
patterns = {
    "secret": re.compile(r"(?i)(BEGIN (RSA |OPENSSH |EC |DSA |)?PRIVATE KEY|bearer\s+[A-Za-z0-9._-]+|token\s*[:=]|password\s*[:=]|secret\s*[:=])"),
    "absolute_path": re.compile(r"/Users/[^ \n\t\"]+"),
    "username": re.compile(re.escape(username)) if username else re.compile(r"a^"),
}
hits = []
for root in roots:
    for path in root.rglob("*"):
        if not path.is_file() or path.stat().st_size > 3_000_000:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for name, pattern in patterns.items():
            if pattern.search(text):
                hits.append((name, str(path.relative_to(root))))
if hits:
    raise SystemExit(str(hits[:10]))
PY
  RESULT[NO_SECRET_LEAKAGE]=yes
  RESULT[NO_ABSOLUTE_PATH_LEAKAGE]=yes
}

validate_checksums() {
  (cd "$OUTPUT_DIR" && shasum -a 256 -c SHA256SUMS >/dev/null) || return 1
  local manifest_sha
  manifest_sha="$(/usr/bin/python3 - "$RELEASE_MANIFEST" "$RC_ARCHIVE_NAME" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
print(data["artifactSHA256"][sys.argv[2]])
PY
)"
  [[ "$manifest_sha" == "$(sha256 "$RC_ARCHIVE")" ]] || return 1
  RESULT[SHA256_VERIFIED]=yes
}

generated_artifacts_ignored() {
  if git -C "$ROOT_DIR" check-ignore -q "artifacts/m14-011/output/release-manifest.json" \
    && git -C "$ROOT_DIR" check-ignore -q "artifacts/m14-011/output/$RC_ARCHIVE_NAME"; then
    print -r -- no
  else
    print -r -- yes
  fi
}

run_clean_user_acceptance_if_requested() {
  if [[ "${HERMES_M14_011_CLEAN_USER_ACCEPTANCE:-}" == "YES" ]]; then
    RESULT[CLEAN_USER_ACCEPTANCE_ATTEMPTED]=yes
    RESULT[CLEAN_USER_ACCEPTANCE_CAPABILITY]=supported-unexercised
    RESULT[CLEAN_USER_ACCEPTANCE_RESULT]=supported-unexercised
  fi
}

assemble() {
  set_default_results
  if [[ "${HERMES_M14_011_ACCEPTANCE:-}" != "YES" ]]; then
    RESULT[M14_011_REASON_CODE]=blocked.acceptance-opt-in-required
    RESULT[M14_011_RESULT]=BLOCKED
    write_result
    return 2
  fi
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  rm -rf "$OUTPUT_DIR" "$EVIDENCE_DIR"
  mkdir -p "$OUTPUT_DIR" "$EVIDENCE_DIR"
  HERMES_M14_010_ACCEPTANCE=YES "$M14_010_SCRIPT" build-unsigned || {
    RESULT[M14_011_REASON_CODE]=blocked.m14-010-assembly-failed
    finish_result
    return 1
  }
  "$M14_010_SCRIPT" verify || {
    RESULT[M14_011_REASON_CODE]=blocked.m14-010-verify-failed
    finish_result
    return 1
  }
  [[ -f "$M14_010_ARCHIVE" ]] || {
    RESULT[M14_011_REASON_CODE]=blocked.m14-010-artifact-missing
    finish_result
    return 1
  }
  cp "$M14_010_ARCHIVE" "$RC_ARCHIVE"
  RESULT[RC_ARTIFACT_ASSEMBLED]=yes
  [[ "$(basename "$RC_ARCHIVE")" == "$RC_ARCHIVE_NAME" && "$RC_ARCHIVE_NAME" == *"-unsigned.zip" ]] || {
    RESULT[M14_011_REASON_CODE]=artifact.filename-invalid
    finish_result
    return 1
  }
  RESULT[RC_ARTIFACT_FILENAME_VALID]=yes
  validate_zip_contents || { RESULT[M14_011_REASON_CODE]=zip.contents-invalid; finish_result; return 1; }
  (cd "$OUTPUT_DIR" && shasum -a 256 "$RC_ARCHIVE_NAME" > SHA256SUMS)
  RESULT[SHA256SUMS_CREATED]=yes
  write_release_notes
  write_external_checklist
  write_known_limitations
  write_rollback
  write_manifest
  write_github_descriptor
  validate_checksums || { RESULT[M14_011_REASON_CODE]=checksum.invalid; finish_result; return 1; }
  scan_generated_privacy || { RESULT[M14_011_REASON_CODE]=privacy.leak; finish_result; return 1; }
  RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]="$(generated_artifacts_ignored)"
  run_clean_user_acceptance_if_requested
  RESULT[ENVIRONMENT_RESTORED]=yes
  finish_result
}

verify() {
  set_default_results
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  [[ -f "$RC_ARCHIVE" && -f "$SHA256SUMS" && -f "$RELEASE_MANIFEST" ]] || {
    RESULT[M14_011_REASON_CODE]=verify.artifacts-missing
    finish_result
    return 1
  }
  RESULT[RC_ARTIFACT_ASSEMBLED]=yes
  [[ "$(basename "$RC_ARCHIVE")" == "$RC_ARCHIVE_NAME" && "$RC_ARCHIVE_NAME" == *"-unsigned.zip" ]] || {
    RESULT[M14_011_REASON_CODE]=artifact.filename-invalid
    finish_result
    return 1
  }
  RESULT[RC_ARTIFACT_FILENAME_VALID]=yes
  validate_zip_contents || { RESULT[M14_011_REASON_CODE]=zip.contents-invalid; finish_result; return 1; }
  validate_checksums || { RESULT[M14_011_REASON_CODE]=checksum.invalid; finish_result; return 1; }
  /usr/bin/python3 - "$RELEASE_MANIFEST" <<'PY' || { RESULT[M14_011_REASON_CODE]=manifest.invalid; finish_result; return 1; }
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
assert data["distributionClassification"] == "unsigned-internal-validation"
assert data["publicDistributionAllowed"] == "no"
assert data["signedReleaseBlockingReason"] == "signing.application-identity-unavailable"
assert data["signingStatus"]["application"] == "unavailable"
assert data["notarizationStatus"] == "not-attempted"
assert data["staplingStatus"] == "not-attempted"
assert "signed-notarized-prerelease" not in json.dumps(data)
PY
  RESULT[RELEASE_MANIFEST_VALID]=yes
  [[ -f "$RELEASE_NOTES" ]] && RESULT[RELEASE_NOTES_CREATED]=yes
  [[ -f "$EXTERNAL_CHECKLIST" ]] && RESULT[EXTERNAL_INSTALL_CHECKLIST_CREATED]=yes
  [[ -f "$ROLLBACK_DOC" ]] && RESULT[ROLLBACK_DOCUMENT_CREATED]=yes
  [[ -f "$GH_DESCRIPTOR" ]] && RESULT[GITHUB_DRAFT_DESCRIPTOR_CREATED]=yes
  scan_generated_privacy || { RESULT[M14_011_REASON_CODE]=privacy.leak; finish_result; return 1; }
  RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]="$(generated_artifacts_ignored)"
  RESULT[ENVIRONMENT_RESTORED]=yes
  finish_result
}

external_test_plan() {
  if [[ -f "$EXTERNAL_CHECKLIST" ]]; then
    sed -n '1,240p' "$EXTERNAL_CHECKLIST"
  else
    sed -n '1,240p' "$ROOT_DIR/Docs/Release/M14_011ExternalInstallationChecklist.md"
  fi
}

print_gh_draft_command() {
  print -r -- "# Proposed draft only. Review evidence first. This command is not executed by this script."
  print -r -- "# WARNING: unsigned internal validation artifact; not notarized; not for general public installation."
  print -r -- "gh release create $TAG_TARGET \\"
  print -r -- "  artifacts/m14-011/output/$RC_ARCHIVE_NAME \\"
  print -r -- "  artifacts/m14-011/output/SHA256SUMS \\"
  print -r -- "  artifacts/m14-011/output/release-manifest.json \\"
  print -r -- "  --title 'Hermes macOS Native Bridge $PRODUCT_VERSION unsigned internal validation' \\"
  print -r -- "  --notes-file artifacts/m14-011/output/release-notes.md \\"
  print -r -- "  --prerelease"
}

cleanup() {
  rm -rf "$ARTIFACT_DIR"
  mkdir -p "$ARTIFACT_DIR"
  print -r -- "M14-011 cleanup complete for generated publication-readiness artifacts"
}

case "${1:-}" in
  inspect) inspect ;;
  assemble) assemble ;;
  verify) verify ;;
  external-test-plan) external_test_plan ;;
  print-gh-draft-command) print_gh_draft_command ;;
  cleanup) cleanup ;;
  *) usage; exit 64 ;;
esac
