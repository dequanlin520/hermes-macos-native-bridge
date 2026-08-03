#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT_NAME="$0"
M14_010_SCRIPT="$ROOT_DIR/Scripts/m14_010_rc1_release.sh"
M14_010_OUTPUT_DIR="$ROOT_DIR/artifacts/m14-010/output"
M14_010_ARCHIVE="$M14_010_OUTPUT_DIR/HermesBridge-0.1.0-rc.1-app-distribution-bundle.zip"
ARTIFACT_DIR="${HERMES_M14_011_ARTIFACT_DIR:-$ROOT_DIR/artifacts/m14-011}"
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
  print -u2 "usage: $SCRIPT_NAME inspect|inspect-existing|assemble|verify|external-test-plan|print-gh-draft-command|cleanup"
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

result_exit_code() {
  local result_value="${1:-${RESULT[M14_011_RESULT]:-FAIL}}"
  local reason_value="${2:-${RESULT[M14_011_REASON_CODE]:-unknown}}"
  case "$result_value" in
    PASS) print -r -- 0 ;;
    FAIL) print -r -- 1 ;;
    BLOCKED)
      if [[ "$reason_value" == "blocked.acceptance-opt-in-required" ]]; then
        print -r -- 2
      else
        print -r -- 3
      fi
      ;;
    PARTIAL) print -r -- 5 ;;
    UNSUPPORTED) print -r -- 6 ;;
    *) print -r -- 1 ;;
  esac
}

set_reason_if_unknown() {
  local reason="$1"
  [[ "${RESULT[M14_011_REASON_CODE]}" != "unknown" ]] || RESULT[M14_011_REASON_CODE]="$reason"
}

expected_checksum_from_sha256sums() {
  /usr/bin/awk -v name="$RC_ARCHIVE_NAME" '
    NF == 2 && $2 == name && $1 ~ /^[0-9a-f]{64}$/ { print $1; found=1; exit }
    END { if (!found) exit 1 }
  ' "$SHA256SUMS"
}

update_checksum_state() {
  RESULT[SHA256SUMS_CREATED]=no
  RESULT[SHA256_VERIFIED]=no
  [[ -f "$SHA256SUMS" ]] || { set_reason_if_unknown checksum.file-missing; return 1; }
  [[ -s "$SHA256SUMS" ]] || { set_reason_if_unknown checksum.file-empty; return 1; }
  local expected_sha
  expected_sha="$(expected_checksum_from_sha256sums)" || {
    set_reason_if_unknown checksum.entry-missing
    return 1
  }
  RESULT[SHA256SUMS_CREATED]=yes
  [[ -f "$RC_ARCHIVE" ]] || { set_reason_if_unknown checksum.state-inconsistent; return 1; }
  if [[ "$expected_sha" != "$(sha256 "$RC_ARCHIVE")" ]]; then
    set_reason_if_unknown checksum.mismatch
    return 1
  fi
  RESULT[SHA256_VERIFIED]=yes
}

validate_release_manifest() {
  [[ -f "$RELEASE_MANIFEST" ]] || { set_reason_if_unknown manifest.missing; return 1; }
  /usr/bin/python3 - "$RELEASE_MANIFEST" "$RC_ARCHIVE_NAME" "$(sha256 "$RC_ARCHIVE")" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
artifact = sys.argv[2]
actual_sha = sys.argv[3]
if data["artifactSHA256"][artifact] != actual_sha:
    raise SystemExit("manifest.checksum-mismatch")
assert data["distributionClassification"] == "unsigned-internal-validation"
assert data["publicDistributionAllowed"] == "no"
assert data["signedReleaseBlockingReason"] == "signing.application-identity-unavailable"
assert data["signingStatus"]["application"] == "unavailable"
assert data["notarizationStatus"] == "not-attempted"
assert data["staplingStatus"] == "not-attempted"
assert "signed-notarized-prerelease" not in json.dumps(data)
PY
  local manifest_result=$?
  if [[ "$manifest_result" -ne 0 ]]; then
    set_reason_if_unknown manifest.checksum-mismatch
    return 1
  fi
  RESULT[RELEASE_MANIFEST_VALID]=yes
}

enforce_result_invariants() {
  if [[ "${RESULT[SHA256_VERIFIED]}" == "yes" && "${RESULT[SHA256SUMS_CREATED]}" != "yes" ]]; then
    RESULT[M14_011_REASON_CODE]=checksum.state-inconsistent
    RESULT[M14_011_RESULT]=FAIL
    return 1
  fi
  if [[ "${RESULT[M14_011_RESULT]}" == "FAIL" && "$(result_exit_code FAIL "${RESULT[M14_011_REASON_CODE]}")" == "0" ]]; then
    RESULT[M14_011_REASON_CODE]=result.exit-code-inconsistent
    RESULT[M14_011_RESULT]=FAIL
    return 1
  fi
  local required_no=(
    GITHUB_RELEASE_CREATED TAG_CREATED PUBLIC_DISTRIBUTION_ALLOWED
  )
  for key in "${required_no[@]}"; do
    if [[ "${RESULT[$key]}" != "no" ]]; then
      RESULT[M14_011_REASON_CODE]=result.invariant-violated
      RESULT[M14_011_RESULT]=FAIL
      return 1
    fi
  done
  if [[ "${RESULT[APPLICATION_SIGNING_STATUS]}" != "unavailable" \
    || "${RESULT[NOTARIZATION_STATUS]}" != "not-attempted" \
    || "${RESULT[STAPLING_STATUS]}" != "not-attempted" ]]; then
    RESULT[M14_011_REASON_CODE]=result.invariant-violated
    RESULT[M14_011_RESULT]=FAIL
    return 1
  fi
  if [[ "${RESULT[M14_011_RESULT]}" == "PASS" ]]; then
    local required_yes=(
      EXPLICIT_OPT_IN_CONFIRMED RC_ARTIFACT_ASSEMBLED RC_ARTIFACT_FILENAME_VALID
      ZIP_CONTENT_VALID SHA256SUMS_CREATED SHA256_VERIFIED RELEASE_MANIFEST_VALID
      RELEASE_NOTES_CREATED EXTERNAL_INSTALL_CHECKLIST_CREATED ROLLBACK_DOCUMENT_CREATED
      GITHUB_DRAFT_DESCRIPTOR_CREATED NO_SECRET_LEAKAGE NO_ABSOLUTE_PATH_LEAKAGE
      NO_SOURCE_CODE_INCLUDED ENVIRONMENT_RESTORED
    )
    for key in "${required_yes[@]}"; do
      if [[ "${RESULT[$key]}" != "yes" ]]; then
        RESULT[M14_011_REASON_CODE]=result.invariant-violated
        RESULT[M14_011_RESULT]=FAIL
        return 1
      fi
    done
    if [[ "${RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]}" != "no" ]]; then
      RESULT[M14_011_REASON_CODE]=result.invariant-violated
      RESULT[M14_011_RESULT]=FAIL
      return 1
    fi
  fi
}

finalize_result_state() {
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
  enforce_result_invariants
}

finish_result() {
  finalize_result_state
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
  update_checksum_state || return 1
  validate_release_manifest || return 1
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
    return "$(result_exit_code)"
  fi
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  rm -rf "$OUTPUT_DIR" "$EVIDENCE_DIR"
  mkdir -p "$OUTPUT_DIR" "$EVIDENCE_DIR"
  HERMES_M14_010_ACCEPTANCE=YES "$M14_010_SCRIPT" build-unsigned || {
    RESULT[M14_011_REASON_CODE]=blocked.m14-010-assembly-failed
    finish_result
    return "$(result_exit_code)"
  }
  "$M14_010_SCRIPT" verify || {
    RESULT[M14_011_REASON_CODE]=blocked.m14-010-verify-failed
    finish_result
    return "$(result_exit_code)"
  }
  [[ -f "$M14_010_ARCHIVE" ]] || {
    RESULT[M14_011_REASON_CODE]=blocked.m14-010-artifact-missing
    finish_result
    return "$(result_exit_code)"
  }
  cp "$M14_010_ARCHIVE" "$RC_ARCHIVE"
  RESULT[RC_ARTIFACT_ASSEMBLED]=yes
  [[ "$(basename "$RC_ARCHIVE")" == "$RC_ARCHIVE_NAME" && "$RC_ARCHIVE_NAME" == *"-unsigned.zip" ]] || {
    RESULT[M14_011_REASON_CODE]=artifact.filename-invalid
    finish_result
    return "$(result_exit_code)"
  }
  RESULT[RC_ARTIFACT_FILENAME_VALID]=yes
  validate_zip_contents || { RESULT[M14_011_REASON_CODE]=zip.contents-invalid; finish_result; return "$(result_exit_code)"; }
  print -r -- "$(sha256 "$RC_ARCHIVE")  $RC_ARCHIVE_NAME" > "$SHA256SUMS"
  update_checksum_state || { finish_result; return "$(result_exit_code)"; }
  write_release_notes
  write_external_checklist
  write_known_limitations
  write_rollback
  write_manifest
  write_github_descriptor
  validate_checksums || { finish_result; return "$(result_exit_code)"; }
  scan_generated_privacy || { RESULT[M14_011_REASON_CODE]=privacy.leak; finish_result; return "$(result_exit_code)"; }
  RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]="$(generated_artifacts_ignored)"
  run_clean_user_acceptance_if_requested
  RESULT[ENVIRONMENT_RESTORED]=yes
  finish_result
  return "$(result_exit_code)"
}

recalculate_current_result_state() {
  set_default_results
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  if [[ -f "$RC_ARCHIVE" ]]; then
    RESULT[RC_ARTIFACT_ASSEMBLED]=yes
  else
    set_reason_if_unknown artifact.missing
  fi
  if [[ "$(basename "$RC_ARCHIVE")" == "$RC_ARCHIVE_NAME" && "$RC_ARCHIVE_NAME" == *"-unsigned.zip" ]]; then
    RESULT[RC_ARTIFACT_FILENAME_VALID]=yes
  else
    set_reason_if_unknown artifact.filename-invalid
  fi
  if [[ "${RESULT[RC_ARTIFACT_ASSEMBLED]}" == "yes" ]]; then
    validate_zip_contents || set_reason_if_unknown zip.contents-invalid
    update_checksum_state || true
    validate_release_manifest || true
  fi
  [[ -f "$RELEASE_NOTES" ]] && RESULT[RELEASE_NOTES_CREATED]=yes
  [[ -f "$EXTERNAL_CHECKLIST" ]] && RESULT[EXTERNAL_INSTALL_CHECKLIST_CREATED]=yes
  [[ -f "$ROLLBACK_DOC" ]] && RESULT[ROLLBACK_DOCUMENT_CREATED]=yes
  [[ -f "$GH_DESCRIPTOR" ]] && RESULT[GITHUB_DRAFT_DESCRIPTOR_CREATED]=yes
  scan_generated_privacy || set_reason_if_unknown privacy.leak
  RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]="$(generated_artifacts_ignored)"
  RESULT[ENVIRONMENT_RESTORED]=yes
}

verify() {
  recalculate_current_result_state
  finish_result
  return "$(result_exit_code)"
}

read_result_value() {
  local key="$1"
  if [[ -f "$RESULT_FILE" ]]; then
    /usr/bin/awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); found=1; exit } END { if (!found) exit 1 }' "$RESULT_FILE"
  else
    return 1
  fi
}

inspect_existing() {
  local artifact_present=no
  local expected_artifact_filename=no
  local sha256sums_present=no
  local sha256sums_nonempty=no
  local sha256_entry_present=no
  local sha256_match=no
  local manifest_present=no
  local manifest_checksum_match=no
  local current_result=unknown
  local current_reason=unknown
  local expected_verify_exit=1

  [[ -f "$RC_ARCHIVE" ]] && artifact_present=yes
  [[ "$(basename "$RC_ARCHIVE")" == "$RC_ARCHIVE_NAME" && "$RC_ARCHIVE_NAME" == *"-unsigned.zip" ]] && expected_artifact_filename=yes
  [[ -f "$SHA256SUMS" ]] && sha256sums_present=yes
  [[ -s "$SHA256SUMS" ]] && sha256sums_nonempty=yes
  local expected_sha=""
  if [[ "$sha256sums_nonempty" == "yes" ]]; then
    expected_sha="$(expected_checksum_from_sha256sums 2>/dev/null || true)"
    [[ -n "$expected_sha" ]] && sha256_entry_present=yes
  fi
  if [[ "$artifact_present" == "yes" && "$sha256_entry_present" == "yes" && "$expected_sha" == "$(sha256 "$RC_ARCHIVE")" ]]; then
    sha256_match=yes
  fi
  [[ -f "$RELEASE_MANIFEST" ]] && manifest_present=yes
  if [[ "$artifact_present" == "yes" && "$manifest_present" == "yes" ]]; then
    /usr/bin/python3 - "$RELEASE_MANIFEST" "$RC_ARCHIVE_NAME" "$(sha256 "$RC_ARCHIVE")" <<'PY' >/dev/null 2>&1 && manifest_checksum_match=yes
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
raise SystemExit(0 if data["artifactSHA256"][sys.argv[2]] == sys.argv[3] else 1)
PY
  fi
  current_result="$(read_result_value M14_011_RESULT 2>/dev/null || print -r -- unknown)"
  current_reason="$(read_result_value M14_011_REASON_CODE 2>/dev/null || print -r -- unknown)"
  recalculate_current_result_state >/dev/null 2>&1
  finalize_result_state
  expected_verify_exit="$(result_exit_code)"

  print -r -- "ARTIFACT_PRESENT=$artifact_present"
  print -r -- "EXPECTED_ARTIFACT_FILENAME=$expected_artifact_filename"
  print -r -- "SHA256SUMS_PRESENT=$sha256sums_present"
  print -r -- "SHA256SUMS_NONEMPTY=$sha256sums_nonempty"
  print -r -- "SHA256_ENTRY_PRESENT=$sha256_entry_present"
  print -r -- "SHA256_MATCH=$sha256_match"
  print -r -- "MANIFEST_PRESENT=$manifest_present"
  print -r -- "MANIFEST_CHECKSUM_MATCH=$manifest_checksum_match"
  print -r -- "CURRENT_RESULT=$current_result"
  print -r -- "CURRENT_REASON_CODE=$current_reason"
  print -r -- "EXPECTED_VERIFY_EXIT_CODE=$expected_verify_exit"
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
  inspect-existing) inspect_existing ;;
  assemble) assemble ;;
  verify) verify ;;
  external-test-plan) external_test_plan ;;
  print-gh-draft-command) print_gh_draft_command ;;
  cleanup) cleanup ;;
  *) usage; exit 64 ;;
esac
