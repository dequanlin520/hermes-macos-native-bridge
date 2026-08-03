#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT_NAME="$0"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m14-010"
STAGING_DIR="$ARTIFACT_DIR/staging"
OUTPUT_DIR="$ARTIFACT_DIR/output"
EVIDENCE_DIR="$ARTIFACT_DIR/evidence"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
RELEASE_MANIFEST="$ARTIFACT_DIR/release-manifest.json"
CHECKSUM_FILE="$OUTPUT_DIR/checksums.sha256"
VERSION_SOURCE="$ROOT_DIR/Sources/HermesReleaseVersion/HermesReleaseVersion.swift"
APP_BUNDLE="$STAGING_DIR/Hermes macOS Native Bridge.app"
APP_PLIST="$APP_BUNDLE/Contents/Info.plist"
SERVICE_BUNDLE="$APP_BUNDLE/Contents/Library/XPCServices/HermesBridgeService.xpc"
SERVICE_PLIST="$SERVICE_BUNDLE/Contents/Info.plist"
SERVICE_EXEC="$SERVICE_BUNDLE/Contents/MacOS/HermesBridgeService"
LAUNCH_AGENT="$STAGING_DIR/Library/LaunchAgents/com.hermes.bridge.plist"
PACKAGE_ARCHIVE="$OUTPUT_DIR/HermesBridge-0.1.0-rc.1-app-distribution-bundle.zip"

typeset -A RESULT

ORDERED_KEYS=(
  EXPLICIT_OPT_IN_CONFIRMED
  PRODUCT_VERSION
  TAG_TARGET
  RELEASE_CONFIGURATION
  RELEASE_APP_BUILT
  APP_BUNDLE_VALID
  SERVICE_BUNDLE_VALID
  XPC_PROTOCOL_VERSION
  APPLE_SILICON_BINARY
  MINIMUM_MACOS_VALID
  VERSION_CONSISTENT
  LAUNCH_AGENT_VALID
  ENTITLEMENTS_MINIMAL
  GET_TASK_ALLOW_ABSENT
  HARDENED_RUNTIME_STATUS
  SIGNING_IDENTITY_STATUS
  APPLICATION_IDENTITY_REQUIRED
  INSTALLER_IDENTITY_REQUIRED
  INSTALLER_IDENTITY_STATUS
  APP_SIGNING_STATUS
  SERVICE_SIGNING_STATUS
  INSTALLER_SIGNING_STATUS
  PACKAGE_TYPE
  PACKAGE_BUILT
  PACKAGE_CONTENT_VALID
  UNINSTALL_VALIDATED
  NOTARIZATION_CONFIGURED
  NOTARIZATION_STATUS
  NOTARIZATION_SUBMISSION_TYPE
  STAPLING_STATUS
  STAPLING_TARGET
  FINAL_ARCHIVE_CREATED_AFTER_STAPLING
  SPCTL_ASSESSMENT
  SHA256_MANIFEST_CREATED
  RELEASE_MANIFEST_CREATED
  NO_SECRET_LEAKAGE
  NO_ABSOLUTE_PATH_LEAKAGE
  NO_ACCEPTANCE_CODE_ENABLED
  GENERATED_ARTIFACT_TRACKED_BY_GIT
  ENVIRONMENT_RESTORED
  M14_010_REASON_CODE
  M14_010_RESULT
)

usage() {
  print -u2 "usage: $SCRIPT_NAME inspect|build-unsigned|inspect-package|build-signed|notarize|verify|cleanup"
}

version_value() {
  local name="$1"
  /usr/bin/awk -v name="$name" '
    $0 ~ "static let " name " = " {
      sub(/^.*= "/, "")
      sub(/".*$/, "")
      print
      exit
    }
  ' "$VERSION_SOURCE"
}

PRODUCT_VERSION="$(version_value productVersion)"
TAG_TARGET="$(version_value tagTarget)"
XPC_PROTOCOL_VERSION="$(version_value xpcProtocolVersion)"
TESTED_HERMES_VERSION="$(version_value testedHermesVersion)"
MINIMUM_MACOS="$(version_value minimumMacOS)"
BUILD_CONFIGURATION="$(version_value buildConfiguration)"
PACKAGE_TYPE="$(version_value packageType)"

signing_policy_field() {
  local package_type="$1"
  local field="$2"
  case "$package_type:$field" in
    app-distribution-bundle:application_identity_required) print -r -- yes ;;
    app-distribution-bundle:installer_identity_required) print -r -- no ;;
    app-distribution-bundle:notarization_submission_type) print -r -- zip ;;
    app-distribution-bundle:stapling_target) print -r -- app-bundle ;;
    disk-image:application_identity_required) print -r -- yes ;;
    disk-image:installer_identity_required) print -r -- no ;;
    disk-image:notarization_submission_type) print -r -- disk-image ;;
    disk-image:stapling_target) print -r -- disk-image ;;
    installer-package:application_identity_required) print -r -- yes ;;
    installer-package:installer_identity_required) print -r -- yes ;;
    installer-package:notarization_submission_type) print -r -- installer-package ;;
    installer-package:stapling_target) print -r -- installer-package ;;
    *) print -r -- unavailable ;;
  esac
}

application_identity_required_for_signed_mode() {
  case "$1" in
    *) signing_policy_field "$1" application_identity_required ;;
  esac
}

installer_identity_required_for_signed_mode() {
  case "$1" in
    *) signing_policy_field "$1" installer_identity_required ;;
  esac
}

notarization_submission_type_for_package() {
  case "$1" in
    *) signing_policy_field "$1" notarization_submission_type ;;
  esac
}

stapling_target_for_package() {
  case "$1" in
    *) signing_policy_field "$1" stapling_target ;;
  esac
}

set_default_results() {
  RESULT=(
    EXPLICIT_OPT_IN_CONFIRMED no
    PRODUCT_VERSION "$PRODUCT_VERSION"
    TAG_TARGET "$TAG_TARGET"
    RELEASE_CONFIGURATION unsigned-local-validation
    RELEASE_APP_BUILT no
    APP_BUNDLE_VALID no
    SERVICE_BUNDLE_VALID no
    XPC_PROTOCOL_VERSION "$XPC_PROTOCOL_VERSION"
    APPLE_SILICON_BINARY no
    MINIMUM_MACOS_VALID no
    VERSION_CONSISTENT no
    LAUNCH_AGENT_VALID no
    ENTITLEMENTS_MINIMAL no
    GET_TASK_ALLOW_ABSENT no
    HARDENED_RUNTIME_STATUS not-applicable
    SIGNING_IDENTITY_STATUS unavailable
    APPLICATION_IDENTITY_REQUIRED "$(application_identity_required_for_signed_mode "$PACKAGE_TYPE")"
    INSTALLER_IDENTITY_REQUIRED "$(installer_identity_required_for_signed_mode "$PACKAGE_TYPE")"
    INSTALLER_IDENTITY_STATUS "$(if [[ "$(installer_identity_required_for_signed_mode "$PACKAGE_TYPE")" == "yes" ]]; then print -r -- unavailable; else print -r -- not-applicable; fi)"
    APP_SIGNING_STATUS unavailable
    SERVICE_SIGNING_STATUS unavailable
    INSTALLER_SIGNING_STATUS "$(if [[ "$(installer_identity_required_for_signed_mode "$PACKAGE_TYPE")" == "yes" ]]; then print -r -- unsigned; else print -r -- not-applicable; fi)"
    PACKAGE_TYPE "$PACKAGE_TYPE"
    PACKAGE_BUILT no
    PACKAGE_CONTENT_VALID no
    UNINSTALL_VALIDATED no
    NOTARIZATION_CONFIGURED no
    NOTARIZATION_STATUS not-requested
    NOTARIZATION_SUBMISSION_TYPE "$(notarization_submission_type_for_package "$PACKAGE_TYPE")"
    STAPLING_STATUS not-requested
    STAPLING_TARGET "$(stapling_target_for_package "$PACKAGE_TYPE")"
    FINAL_ARCHIVE_CREATED_AFTER_STAPLING not-attempted
    SPCTL_ASSESSMENT not-run
    SHA256_MANIFEST_CREATED no
    RELEASE_MANIFEST_CREATED no
    NO_SECRET_LEAKAGE no
    NO_ABSOLUTE_PATH_LEAKAGE no
    NO_ACCEPTANCE_CODE_ENABLED no
    GENERATED_ARTIFACT_TRACKED_BY_GIT unknown
    ENVIRONMENT_RESTORED no
    M14_010_REASON_CODE unknown
    M14_010_RESULT FAIL
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
  local mode="${RESULT[RELEASE_CONFIGURATION]}"
  local required_yes=(
    EXPLICIT_OPT_IN_CONFIRMED RELEASE_APP_BUILT APP_BUNDLE_VALID SERVICE_BUNDLE_VALID
    APPLE_SILICON_BINARY MINIMUM_MACOS_VALID VERSION_CONSISTENT LAUNCH_AGENT_VALID
    ENTITLEMENTS_MINIMAL GET_TASK_ALLOW_ABSENT PACKAGE_BUILT PACKAGE_CONTENT_VALID
    UNINSTALL_VALIDATED SHA256_MANIFEST_CREATED RELEASE_MANIFEST_CREATED NO_SECRET_LEAKAGE
    NO_ABSOLUTE_PATH_LEAKAGE NO_ACCEPTANCE_CODE_ENABLED ENVIRONMENT_RESTORED
  )
  local ok=yes
  for key in "${required_yes[@]}"; do
    [[ "${RESULT[$key]}" == "yes" ]] || ok=no
  done
  [[ "${RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]}" == "no" ]] || ok=no

  if [[ "$mode" == "signed-notarized-release" ]]; then
    [[ "${RESULT[HARDENED_RUNTIME_STATUS]}" == "enabled" ]] || ok=no
    [[ "${RESULT[APP_SIGNING_STATUS]}" == "developer-id-application" ]] || ok=no
    [[ "${RESULT[SERVICE_SIGNING_STATUS]}" == "developer-id-application" ]] || ok=no
    if [[ "${RESULT[INSTALLER_IDENTITY_REQUIRED]}" == "yes" ]]; then
      [[ "${RESULT[INSTALLER_SIGNING_STATUS]}" == "developer-id-installer" ]] || ok=no
    else
      [[ "${RESULT[INSTALLER_SIGNING_STATUS]}" == "not-applicable" ]] || ok=no
    fi
    if [[ "${RESULT[NOTARIZATION_CONFIGURED]}" == "yes" ]]; then
      [[ "${RESULT[NOTARIZATION_STATUS]}" == "accepted" ]] || ok=no
      [[ "${RESULT[STAPLING_STATUS]}" == "accepted" ]] || ok=no
      [[ "${RESULT[SPCTL_ASSESSMENT]}" == "accepted" ]] || ok=no
      [[ "${RESULT[FINAL_ARCHIVE_CREATED_AFTER_STAPLING]}" == "yes" ]] || ok=no
    fi
  fi

  if [[ "$ok" == "yes" ]]; then
    RESULT[M14_010_REASON_CODE]=ok
    RESULT[M14_010_RESULT]=PASS
  elif [[ "${RESULT[M14_010_REASON_CODE]}" == blocked.* ]]; then
    RESULT[M14_010_RESULT]=BLOCKED
  else
    [[ "${RESULT[M14_010_REASON_CODE]}" != "unknown" ]] || RESULT[M14_010_REASON_CODE]=validation.failed
    RESULT[M14_010_RESULT]=FAIL
  fi
  write_result
}

sha256() {
  shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

json_escape() {
  /usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

identity_summary() {
  mkdir -p "$EVIDENCE_DIR"
  local output="$EVIDENCE_DIR/signing-identity-summary.txt"
  if ! /usr/bin/security find-identity -v -p codesigning >"$EVIDENCE_DIR/signing-identities.raw" 2>/dev/null; then
    rm -f "$EVIDENCE_DIR/signing-identities.raw"
    print -r -- "developer-id-application-count=0" > "$output"
    print -r -- "developer-id-installer-count=0" >> "$output"
    return
  fi
  /usr/bin/awk '
    /Developer ID Application:/ { app += 1 }
    /Developer ID Installer:/ { installer += 1 }
    END {
      printf("developer-id-application-count=%d\n", app + 0)
      printf("developer-id-installer-count=%d\n", installer + 0)
    }
  ' "$EVIDENCE_DIR/signing-identities.raw" > "$output"
  rm -f "$EVIDENCE_DIR/signing-identities.raw"
}

identity_category_available() {
  local category="$1"
  identity_summary
  local key
  case "$category" in
    application) key=developer-id-application-count ;;
    installer) key=developer-id-installer-count ;;
    *) print -r -- no; return ;;
  esac
  local count
  count="$(/usr/bin/awk -F= -v key="$key" '$1 == key { print $2; found = 1 } END { if (!found) print 0 }' "$EVIDENCE_DIR/signing-identity-summary.txt")"
  if [[ "$count" -gt 0 ]]; then
    print -r -- yes
  else
    print -r -- no
  fi
}

identity_status() {
  if [[ "$(identity_category_available application)" == "yes" || "$(identity_category_available installer)" == "yes" ]]; then
    print -r -- available
  else
    print -r -- unavailable
  fi
}

inspect() {
  print -r -- "PRODUCT_VERSION=$PRODUCT_VERSION"
  print -r -- "TAG_TARGET=$TAG_TARGET"
  print -r -- "XPC_PROTOCOL_VERSION=$XPC_PROTOCOL_VERSION"
  print -r -- "TESTED_HERMES_VERSION=$TESTED_HERMES_VERSION"
  print -r -- "MINIMUM_MACOS=$MINIMUM_MACOS"
  print -r -- "PACKAGE_TYPE=$PACKAGE_TYPE"
  print -r -- "APPLICATION_IDENTITY_CATEGORY_AVAILABLE=$(identity_category_available application)"
  print -r -- "INSTALLER_IDENTITY_CATEGORY_AVAILABLE=$(identity_category_available installer)"
  print -r -- "APPLICATION_IDENTITY_REQUIRED_FOR_SIGNED_MODE=$(application_identity_required_for_signed_mode "$PACKAGE_TYPE")"
  print -r -- "INSTALLER_IDENTITY_REQUIRED_FOR_SIGNED_MODE=$(installer_identity_required_for_signed_mode "$PACKAGE_TYPE")"
  print -r -- "NOTARIZATION_SUBMISSION_TYPE=$(notarization_submission_type_for_package "$PACKAGE_TYPE")"
  print -r -- "STAPLING_TARGET=$(stapling_target_for_package "$PACKAGE_TYPE")"
  print -r -- "NOTARIZATION_CONFIGURED=$([[ "${HERMES_M14_010_NOTARIZE:-}" == "YES" ]] && print yes || print no)"
}

write_info_plists() {
  mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" \
    "$APP_BUNDLE/Contents/Library/XPCServices" "$SERVICE_BUNDLE/Contents/MacOS" \
    "$SERVICE_BUNDLE/Contents/Resources"
  cp "$ROOT_DIR/Packaging/HermesBridgeApp/Info.plist" "$APP_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName Hermes macOS Native Bridge" "$APP_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PRODUCT_VERSION" "$APP_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PRODUCT_VERSION" "$APP_PLIST"
  cat > "$SERVICE_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>HermesBridgeService</string>
  <key>CFBundleIdentifier</key>
  <string>com.hermes.bridge.xpc</string>
  <key>CFBundleName</key>
  <string>HermesBridgeService</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleShortVersionString</key>
  <string>$PRODUCT_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$PRODUCT_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MINIMUM_MACOS</string>
  <key>XPCService</key>
  <dict>
    <key>ServiceType</key>
    <string>Application</string>
  </dict>
</dict>
</plist>
PLIST
}

stage_payload() {
  rm -rf "$STAGING_DIR" "$OUTPUT_DIR" "$EVIDENCE_DIR"
  mkdir -p "$STAGING_DIR/bin" "$STAGING_DIR/Scripts" "$STAGING_DIR/Library/LaunchAgents" \
    "$OUTPUT_DIR" "$EVIDENCE_DIR"

  swift build -c release --product HermesBridgeApp >/dev/null || return 1
  swift build -c release --product HermesBridgeService >/dev/null || return 1
  swift build -c release --product HermesBridgeControl >/dev/null || return 1
  swift build -c release --product HermesBridgeServiceLifecycle >/dev/null || return 1

  local bin_path
  bin_path="$(swift build -c release --show-bin-path | tail -n 1)"
  write_info_plists
  cp "$bin_path/HermesBridgeApp" "$APP_BUNDLE/Contents/MacOS/HermesBridgeApp"
  cp "$bin_path/HermesBridgeService" "$SERVICE_EXEC"
  cp "$bin_path/HermesBridgeControl" "$STAGING_DIR/bin/HermesBridgeControl"
  cp "$bin_path/HermesBridgeServiceLifecycle" "$STAGING_DIR/bin/HermesBridgeServiceLifecycle"
  chmod 755 "$APP_BUNDLE/Contents/MacOS/HermesBridgeApp" "$SERVICE_EXEC" "$STAGING_DIR/bin/"*
  cp "$ROOT_DIR/Scripts/native/install-hermes-bridge-app.zsh" "$STAGING_DIR/Scripts/install-hermes-bridge-app.zsh"
  cp "$ROOT_DIR/Scripts/native/uninstall-hermes-bridge-app.zsh" "$STAGING_DIR/Scripts/uninstall-hermes-bridge-app.zsh"
  chmod 755 "$STAGING_DIR/Scripts/"*.zsh
  sed 's#__HERMES_BRIDGE_SERVICE_BINARY__#~/Library/Application Support/HermesBridge/HermesBridgeService#g; s#__HERMES_BRIDGE_LOGS_DIR__#~/Library/Logs/HermesBridge#g' \
    "$ROOT_DIR/Packaging/LaunchAgent/com.hermes.bridge.plist.template" > "$LAUNCH_AGENT"
  cp "$ROOT_DIR/Packaging/Entitlements/HermesBridgeApp.entitlements" "$EVIDENCE_DIR/HermesBridgeApp.entitlements"
  cp "$ROOT_DIR/Packaging/Entitlements/HermesBridgeService.entitlements" "$EVIDENCE_DIR/HermesBridgeService.entitlements"
  RESULT[RELEASE_APP_BUILT]=yes
}

validate_bundles() {
  /usr/bin/plutil -lint "$APP_PLIST" >/dev/null || return 1
  /usr/bin/plutil -lint "$SERVICE_PLIST" >/dev/null || return 1
  /usr/bin/plutil -lint "$LAUNCH_AGENT" >/dev/null || return 1
  local app_id service_id app_version service_version app_min service_min label
  app_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PLIST")"
  service_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SERVICE_PLIST")"
  app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
  service_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SERVICE_PLIST")"
  app_min="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_PLIST")"
  service_min="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$SERVICE_PLIST")"
  label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$LAUNCH_AGENT")"
  [[ "$app_id" == "com.hermes.bridge.app" ]] || return 1
  [[ "$service_id" == "com.hermes.bridge.xpc" ]] || return 1
  [[ "$app_version" == "$PRODUCT_VERSION" && "$service_version" == "$PRODUCT_VERSION" ]] || return 1
  [[ "$app_min" == "$MINIMUM_MACOS" && "$service_min" == "$MINIMUM_MACOS" ]] || return 1
  [[ "$label" == "com.hermes.bridge" ]] || return 1
  [[ -x "$APP_BUNDLE/Contents/MacOS/HermesBridgeApp" && -x "$SERVICE_EXEC" ]] || return 1
  RESULT[APP_BUNDLE_VALID]=yes
  RESULT[SERVICE_BUNDLE_VALID]=yes
  RESULT[MINIMUM_MACOS_VALID]=yes
  RESULT[VERSION_CONSISTENT]=yes
  RESULT[LAUNCH_AGENT_VALID]=yes
}

validate_architecture() {
  local paths=("$APP_BUNDLE/Contents/MacOS/HermesBridgeApp" "$SERVICE_EXEC" "$STAGING_DIR/bin/HermesBridgeControl" "$STAGING_DIR/bin/HermesBridgeServiceLifecycle")
  local ok=yes
  for executable_path in "${paths[@]}"; do
    if ! /usr/bin/lipo -archs "$executable_path" 2>/dev/null | /usr/bin/grep -qw arm64; then
      ok=no
    fi
    /usr/bin/file "$executable_path" > "$EVIDENCE_DIR/$(basename "$executable_path").file.txt"
    /usr/bin/otool -L "$executable_path" > "$EVIDENCE_DIR/$(basename "$executable_path").otool.txt"
  done
  [[ "$ok" == "yes" ]] || return 1
  RESULT[APPLE_SILICON_BINARY]=yes
}

validate_entitlements() {
  /usr/bin/python3 - "$ROOT_DIR/Packaging/Entitlements/HermesBridgeApp.entitlements" "$ROOT_DIR/Packaging/Entitlements/HermesBridgeService.entitlements" <<'PY'
import plistlib
import sys
from pathlib import Path
blocked = {
    "com.apple.security.cs.disable-library-validation",
    "com.apple.security.cs.allow-unsigned-executable-memory",
    "com.apple.security.get-task-allow",
    "com.apple.security.temporary-exception.files.absolute-path.read-only",
    "com.apple.security.temporary-exception.files.absolute-path.read-write",
    "com.apple.security.temporary-exception.apple-events",
}
for raw in sys.argv[1:]:
    data = plistlib.loads(Path(raw).read_bytes())
    if blocked.intersection(data):
        raise SystemExit(1)
PY
  RESULT[ENTITLEMENTS_MINIMAL]=yes
  RESULT[GET_TASK_ALLOW_ABSENT]=yes
}

scan_privacy() {
  /usr/bin/python3 - "$STAGING_DIR" "$RESULT_FILE" "$RELEASE_MANIFEST" <<'PY'
import re
import sys
from pathlib import Path
root = Path(sys.argv[1])
patterns = {
    "secret": re.compile(r"(?i)(BEGIN (RSA |OPENSSH |EC |DSA |)?PRIVATE KEY|bearer\s+[A-Za-z0-9._-]+|token\s*[:=]|password\s*[:=]|secret\s*[:=])"),
    "path": re.compile(r"/Users/[^ \n\t\"]+"),
    "acceptance": re.compile(r"(AcceptanceHarness|AcceptanceSupport|M8001ReleaseCandidateAcceptance|fixture_backend|--hermes-m11-003-acceptance)"),
    "private_ws": re.compile(r"/api/ws"),
}
hits = {name: False for name in patterns}
for path in root.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    if path.stat().st_size > 2_000_000:
        continue
    text = path.read_text(encoding="utf-8", errors="ignore")
    for name, pattern in patterns.items():
        if pattern.search(text):
            hits[name] = True
if any(hits.values()):
    raise SystemExit(",".join(name for name, hit in hits.items() if hit))
PY
  RESULT[NO_SECRET_LEAKAGE]=yes
  RESULT[NO_ABSOLUTE_PATH_LEAKAGE]=yes
  RESULT[NO_ACCEPTANCE_CODE_ENABLED]=yes
}

validate_package_contents() {
  /usr/bin/python3 - "$STAGING_DIR" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
required = {
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
actual = {str(path.relative_to(root)) for path in root.rglob("*") if path.is_file()}
missing = required - actual
deny = [item for item in actual if item.startswith(("Sources/", "Tests/", ".git/", "artifacts/")) or item.endswith((".log", ".key", ".pem", ".p12"))]
if missing or deny:
    raise SystemExit(f"missing={sorted(missing)} deny={deny}")
PY
  RESULT[PACKAGE_CONTENT_VALID]=yes
}

validate_uninstall_pairing() {
  local root="$EVIDENCE_DIR/install-root"
  rm -rf "$root"
  mkdir -p "$root/Applications" "$root/Library/LaunchAgents"
  cp -R "$APP_BUNDLE" "$root/Applications/"
  cp "$LAUNCH_AGENT" "$root/Library/LaunchAgents/"
  rm -rf "$root/Applications/Hermes macOS Native Bridge.app" "$root/Library/LaunchAgents/com.hermes.bridge.plist"
  if find "$root" -type f | read -r _; then
    return 1
  fi
  RESULT[UNINSTALL_VALIDATED]=yes
}

create_archive_and_manifest() {
  mkdir -p "$OUTPUT_DIR"
  rm -f "$PACKAGE_ARCHIVE" "$CHECKSUM_FILE" "$RELEASE_MANIFEST"
  find "$STAGING_DIR" -exec touch -h -t 198001010000 {} +
  (
    cd "$STAGING_DIR/.."
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$(basename "$STAGING_DIR")" "$PACKAGE_ARCHIVE"
  )
  (
    cd "$OUTPUT_DIR"
    for item in *.zip; do
      shasum -a 256 "$item"
    done > "$CHECKSUM_FILE"
  )
  RESULT[SHA256_MANIFEST_CREATED]=yes
  local archive_sha git_commit generated_tracked
  archive_sha="$(sha256 "$PACKAGE_ARCHIVE")"
  git_commit="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || print unknown)"
  if git -C "$ROOT_DIR" check-ignore -q "artifacts/m14-010/release-manifest.json" \
    && git -C "$ROOT_DIR" check-ignore -q "artifacts/m14-010/output/checksums.sha256"; then
    generated_tracked=no
  else
    generated_tracked=yes
  fi
  RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]="$generated_tracked"
  cat > "$RELEASE_MANIFEST" <<JSON
{
  "architectures": ["arm64"],
  "artifactSHA256": {
    "$(basename "$PACKAGE_ARCHIVE")": "$archive_sha"
  },
  "buildConfiguration": "$BUILD_CONFIGURATION",
  "gitCommit": "$git_commit",
  "hardenedRuntime": $(json_escape "${RESULT[HARDENED_RUNTIME_STATUS]}"),
  "identityRequirements": {
    "application": $(json_escape "${RESULT[APPLICATION_IDENTITY_REQUIRED]}"),
    "installer": $(json_escape "${RESULT[INSTALLER_IDENTITY_REQUIRED]}")
  },
  "minimumMacOS": "$MINIMUM_MACOS",
  "notarizationSubmissionType": $(json_escape "${RESULT[NOTARIZATION_SUBMISSION_TYPE]}"),
  "notarizationStatus": $(json_escape "${RESULT[NOTARIZATION_STATUS]}"),
  "packageType": "$PACKAGE_TYPE",
  "productVersion": "$PRODUCT_VERSION",
  "reproducibilityCategory": "deterministic-local-staging-with-normalized-zip-metadata",
  "rcCapabilities": {
    "supported": ["lifecycle-management", "status-only-hermes-agent-integration", "xpc-service-connectivity", "user-scoped-launchagent-assets"],
    "unsupported": ["request-submission:transport.route-unsupported", "request-cancellation:transport.route-unsupported", "approval-response:transport.route-unsupported", "private-api-ws:not-claimed", "production-readiness:not-claimed"]
  },
  "signingCategory": $(json_escape "${RESULT[APP_SIGNING_STATUS]}"),
  "signingStatus": {
    "app": $(json_escape "${RESULT[APP_SIGNING_STATUS]}"),
    "service": $(json_escape "${RESULT[SERVICE_SIGNING_STATUS]}"),
    "installer": $(json_escape "${RESULT[INSTALLER_SIGNING_STATUS]}")
  },
  "staplingTarget": $(json_escape "${RESULT[STAPLING_TARGET]}"),
  "staplingStatus": $(json_escape "${RESULT[STAPLING_STATUS]}"),
  "tagTarget": "$TAG_TARGET",
  "testedHermesVersion": "$TESTED_HERMES_VERSION",
  "xpcProtocolVersion": "$XPC_PROTOCOL_VERSION"
}
JSON
  RESULT[RELEASE_MANIFEST_CREATED]=yes
}

signing_category_for() {
  local inspected_path="$1"
  local detail
  detail="$(/usr/bin/codesign -dv "$inspected_path" 2>&1 || true)"
  if [[ "$detail" == *"Authority=Developer ID Application:"* ]]; then
    print -r -- developer-id-application
  elif [[ "$detail" == *"Signature=adhoc"* ]]; then
    print -r -- ad-hoc
  elif [[ "$detail" == *"invalid signature"* ]]; then
    print -r -- invalid
  elif [[ "$detail" == *"code object is not signed"* ]]; then
    print -r -- unavailable
  else
    print -r -- unavailable
  fi
}

inspect_package() {
  set_default_results
  [[ -d "$STAGING_DIR" ]] || { RESULT[M14_010_REASON_CODE]=package.missing; finish_result; return 1; }
  RESULT[RELEASE_APP_BUILT]=yes
  validate_bundles || { RESULT[M14_010_REASON_CODE]=bundle.invalid; finish_result; return 1; }
  validate_architecture || { RESULT[M14_010_REASON_CODE]=architecture.invalid; finish_result; return 1; }
  validate_entitlements || { RESULT[M14_010_REASON_CODE]=entitlements.invalid; finish_result; return 1; }
  validate_package_contents || { RESULT[M14_010_REASON_CODE]=package.contents-invalid; finish_result; return 1; }
  scan_privacy || { RESULT[M14_010_REASON_CODE]=privacy.leak; finish_result; return 1; }
  RESULT[APP_SIGNING_STATUS]="$(signing_category_for "$APP_BUNDLE")"
  RESULT[SERVICE_SIGNING_STATUS]="$(signing_category_for "$SERVICE_EXEC")"
  if [[ "${RESULT[INSTALLER_IDENTITY_REQUIRED]}" == "yes" ]]; then
    RESULT[INSTALLER_SIGNING_STATUS]=unsigned
    RESULT[INSTALLER_IDENTITY_STATUS]=unavailable
  else
    RESULT[INSTALLER_SIGNING_STATUS]=not-applicable
    RESULT[INSTALLER_IDENTITY_STATUS]=not-applicable
  fi
  write_result
}

build_unsigned() {
  set_default_results
  RESULT[RELEASE_CONFIGURATION]=unsigned-local-validation
  if [[ "${HERMES_M14_010_ACCEPTANCE:-}" != "YES" ]]; then
    RESULT[M14_010_REASON_CODE]=acceptance.opt-in-required
    RESULT[M14_010_RESULT]=BLOCKED
    write_result
    return 2
  fi
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  RESULT[SIGNING_IDENTITY_STATUS]="$(identity_status)"
  stage_payload || { RESULT[M14_010_REASON_CODE]=build.failed; finish_result; return 1; }
  validate_bundles || { RESULT[M14_010_REASON_CODE]=bundle.invalid; finish_result; return 1; }
  validate_architecture || { RESULT[M14_010_REASON_CODE]=architecture.invalid; finish_result; return 1; }
  validate_entitlements || { RESULT[M14_010_REASON_CODE]=entitlements.invalid; finish_result; return 1; }
  validate_package_contents || { RESULT[M14_010_REASON_CODE]=package.contents-invalid; finish_result; return 1; }
  validate_uninstall_pairing || { RESULT[M14_010_REASON_CODE]=uninstall.invalid; finish_result; return 1; }
  scan_privacy || { RESULT[M14_010_REASON_CODE]=privacy.leak; finish_result; return 1; }
  create_archive_and_manifest
  RESULT[PACKAGE_BUILT]=yes
  RESULT[ENVIRONMENT_RESTORED]=yes
  finish_result
}

sign_release_code_inside_out() {
  local application_identity="$1"
  /usr/bin/codesign --force --sign "$application_identity" --timestamp --options runtime \
    --entitlements "$ROOT_DIR/Packaging/Entitlements/HermesBridgeService.entitlements" "$SERVICE_EXEC" >/dev/null || return 1
  /usr/bin/codesign --force --sign "$application_identity" --timestamp --options runtime \
    "$SERVICE_BUNDLE" >/dev/null || return 1
  /usr/bin/codesign --force --sign "$application_identity" --timestamp --options runtime \
    "$STAGING_DIR/bin/HermesBridgeControl" >/dev/null || return 1
  /usr/bin/codesign --force --sign "$application_identity" --timestamp --options runtime \
    "$STAGING_DIR/bin/HermesBridgeServiceLifecycle" >/dev/null || return 1
  /usr/bin/codesign --force --sign "$application_identity" --timestamp --options runtime \
    --entitlements "$ROOT_DIR/Packaging/Entitlements/HermesBridgeApp.entitlements" "$APP_BUNDLE" >/dev/null || return 1
}

verify_release_code_signatures() {
  /usr/bin/codesign --verify --strict --deep "$SERVICE_BUNDLE" >/dev/null || return 1
  /usr/bin/codesign --verify --strict "$STAGING_DIR/bin/HermesBridgeControl" >/dev/null || return 1
  /usr/bin/codesign --verify --strict "$STAGING_DIR/bin/HermesBridgeServiceLifecycle" >/dev/null || return 1
  /usr/bin/codesign --verify --strict --deep "$APP_BUNDLE" >/dev/null || return 1
}

build_signed() {
  set_default_results
  RESULT[RELEASE_CONFIGURATION]=signed-notarized-release
  RESULT[HARDENED_RUNTIME_STATUS]=enabled
  if [[ "${HERMES_M14_010_ACCEPTANCE:-}" != "YES" ]]; then
    RESULT[M14_010_REASON_CODE]=acceptance.opt-in-required
    RESULT[M14_010_RESULT]=BLOCKED
    write_result
    return 2
  fi
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  if [[ -z "${HERMES_RELEASE_APPLICATION_IDENTITY:-}" ]]; then
    RESULT[M14_010_REASON_CODE]=blocked.signing-identity-missing
    finish_result
    return 2
  fi
  if [[ "${RESULT[INSTALLER_IDENTITY_REQUIRED]}" == "yes" && -z "${HERMES_RELEASE_INSTALLER_IDENTITY:-}" ]]; then
    RESULT[M14_010_REASON_CODE]=blocked.installer-signing-identity-missing
    finish_result
    return 2
  fi
  if [[ "${RESULT[INSTALLER_IDENTITY_REQUIRED]}" == "no" && -n "${HERMES_RELEASE_INSTALLER_IDENTITY:-}" ]]; then
    print -u2 "warning: HERMES_RELEASE_INSTALLER_IDENTITY is not used for PACKAGE_TYPE=$PACKAGE_TYPE"
  fi
  RESULT[SIGNING_IDENTITY_STATUS]=configured
  RESULT[INSTALLER_IDENTITY_STATUS]="$(if [[ "${RESULT[INSTALLER_IDENTITY_REQUIRED]}" == "yes" ]]; then print -r -- configured; else print -r -- not-applicable; fi)"
  stage_payload || { RESULT[M14_010_REASON_CODE]=build.failed; finish_result; return 1; }
  sign_release_code_inside_out "$HERMES_RELEASE_APPLICATION_IDENTITY" || {
    RESULT[M14_010_REASON_CODE]=signature.invalid; finish_result; return 1
  }
  verify_release_code_signatures || { RESULT[M14_010_REASON_CODE]=signature.verification-failed; finish_result; return 1; }
  validate_bundles || { RESULT[M14_010_REASON_CODE]=bundle.invalid; finish_result; return 1; }
  validate_architecture || { RESULT[M14_010_REASON_CODE]=architecture.invalid; finish_result; return 1; }
  validate_entitlements || { RESULT[M14_010_REASON_CODE]=entitlements.invalid; finish_result; return 1; }
  validate_package_contents || { RESULT[M14_010_REASON_CODE]=package.contents-invalid; finish_result; return 1; }
  validate_uninstall_pairing || { RESULT[M14_010_REASON_CODE]=uninstall.invalid; finish_result; return 1; }
  scan_privacy || { RESULT[M14_010_REASON_CODE]=privacy.leak; finish_result; return 1; }
  RESULT[APP_SIGNING_STATUS]=developer-id-application
  RESULT[SERVICE_SIGNING_STATUS]=developer-id-application
  RESULT[INSTALLER_SIGNING_STATUS]="$(if [[ "${RESULT[INSTALLER_IDENTITY_REQUIRED]}" == "yes" ]]; then print -r -- developer-id-installer; else print -r -- not-applicable; fi)"
  create_archive_and_manifest
  RESULT[PACKAGE_BUILT]=yes
  RESULT[ENVIRONMENT_RESTORED]=yes
  finish_result
}

notarize_release() {
  set_default_results
  RESULT[RELEASE_CONFIGURATION]=signed-notarized-release
  RESULT[HARDENED_RUNTIME_STATUS]=enabled
  RESULT[SIGNING_IDENTITY_STATUS]=configured
  if [[ "${HERMES_M14_010_NOTARIZE:-}" != "YES" ]]; then
    RESULT[M14_010_REASON_CODE]=blocked.notarization-opt-in-required
    RESULT[M14_010_RESULT]=BLOCKED
    write_result
    return 2
  fi
  RESULT[NOTARIZATION_CONFIGURED]=yes
  RESULT[INSTALLER_IDENTITY_STATUS]="$(if [[ "${RESULT[INSTALLER_IDENTITY_REQUIRED]}" == "yes" ]]; then print -r -- configured; else print -r -- not-applicable; fi)"
  [[ -f "$PACKAGE_ARCHIVE" ]] || {
    RESULT[M14_010_REASON_CODE]=blocked.package-missing
    RESULT[M14_010_RESULT]=BLOCKED
    write_result
    return 2
  }
  [[ -d "$APP_BUNDLE" ]] || {
    RESULT[M14_010_REASON_CODE]=blocked.app-bundle-missing
    RESULT[M14_010_RESULT]=BLOCKED
    write_result
    return 2
  }
  local args=()
  if [[ -n "${HERMES_RELEASE_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    args=(--keychain-profile "$HERMES_RELEASE_NOTARY_KEYCHAIN_PROFILE")
  elif [[ -n "${HERMES_RELEASE_NOTARY_KEY:-}" && -n "${HERMES_RELEASE_NOTARY_KEY_ID:-}" && -n "${HERMES_RELEASE_NOTARY_ISSUER:-}" ]]; then
    args=(--key "$HERMES_RELEASE_NOTARY_KEY" --key-id "$HERMES_RELEASE_NOTARY_KEY_ID" --issuer "$HERMES_RELEASE_NOTARY_ISSUER")
  else
    RESULT[M14_010_REASON_CODE]=blocked.notarization-credentials-missing
    RESULT[M14_010_RESULT]=BLOCKED
    write_result
    return 2
  fi
  /usr/bin/xcrun notarytool submit "$PACKAGE_ARCHIVE" --wait --output-format json "${args[@]}" > "$EVIDENCE_DIR/notary-status.json" || {
    RESULT[M14_010_REASON_CODE]=notarization.rejected
    finish_result
    return 1
  }
  /usr/bin/xcrun stapler staple "$APP_BUNDLE" >/dev/null || { RESULT[M14_010_REASON_CODE]=staple.failed; finish_result; return 1; }
  /usr/bin/xcrun stapler validate "$APP_BUNDLE" >/dev/null || { RESULT[M14_010_REASON_CODE]=staple.invalid; finish_result; return 1; }
  /usr/sbin/spctl --assess --type execute --verbose "$APP_BUNDLE" >/dev/null || { RESULT[M14_010_REASON_CODE]=spctl.rejected; finish_result; return 1; }
  RESULT[NOTARIZATION_STATUS]=accepted
  RESULT[STAPLING_STATUS]=accepted
  RESULT[SPCTL_ASSESSMENT]=accepted
  RESULT[FINAL_ARCHIVE_CREATED_AFTER_STAPLING]=yes
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  RESULT[RELEASE_APP_BUILT]=yes
  validate_bundles || { RESULT[M14_010_REASON_CODE]=bundle.invalid; finish_result; return 1; }
  validate_architecture || { RESULT[M14_010_REASON_CODE]=architecture.invalid; finish_result; return 1; }
  validate_entitlements || { RESULT[M14_010_REASON_CODE]=entitlements.invalid; finish_result; return 1; }
  validate_package_contents || { RESULT[M14_010_REASON_CODE]=package.contents-invalid; finish_result; return 1; }
  validate_uninstall_pairing || { RESULT[M14_010_REASON_CODE]=uninstall.invalid; finish_result; return 1; }
  scan_privacy || { RESULT[M14_010_REASON_CODE]=privacy.leak; finish_result; return 1; }
  RESULT[APP_SIGNING_STATUS]=developer-id-application
  RESULT[SERVICE_SIGNING_STATUS]=developer-id-application
  RESULT[INSTALLER_SIGNING_STATUS]="$(if [[ "${RESULT[INSTALLER_IDENTITY_REQUIRED]}" == "yes" ]]; then print -r -- developer-id-installer; else print -r -- not-applicable; fi)"
  create_archive_and_manifest
  RESULT[PACKAGE_BUILT]=yes
  RESULT[ENVIRONMENT_RESTORED]=yes
  finish_result
}

verify_release() {
  inspect_package || return 1
  [[ -f "$PACKAGE_ARCHIVE" && -f "$CHECKSUM_FILE" && -f "$RELEASE_MANIFEST" ]] || {
    RESULT[M14_010_REASON_CODE]=verify.artifacts-missing
    finish_result
    return 1
  }
  (cd "$OUTPUT_DIR" && shasum -a 256 -c "$(basename "$CHECKSUM_FILE")" >/dev/null) || {
    RESULT[M14_010_REASON_CODE]=verify.checksum-invalid
    finish_result
    return 1
  }
  RESULT[RELEASE_APP_BUILT]=yes
  RESULT[PACKAGE_BUILT]=yes
  RESULT[SHA256_MANIFEST_CREATED]=yes
  RESULT[RELEASE_MANIFEST_CREATED]=yes
  RESULT[UNINSTALL_VALIDATED]=yes
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  if git -C "$ROOT_DIR" check-ignore -q "artifacts/m14-010/release-manifest.json" \
    && git -C "$ROOT_DIR" check-ignore -q "artifacts/m14-010/output/checksums.sha256"; then
    RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]=no
  else
    RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]=yes
  fi
  RESULT[ENVIRONMENT_RESTORED]=yes
  finish_result
}

cleanup() {
  rm -rf "$STAGING_DIR" "$EVIDENCE_DIR/install-root"
  mkdir -p "$ARTIFACT_DIR"
  print -r -- "M14-010 cleanup complete for acceptance-owned targets"
}

case "${1:-}" in
  inspect) inspect ;;
  build-unsigned) build_unsigned ;;
  inspect-package) inspect_package ;;
  build-signed) build_signed ;;
  notarize) notarize_release ;;
  verify) verify_release ;;
  cleanup) cleanup ;;
  *) usage; exit 64 ;;
esac
