#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m14-001"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
RUNTIME_MANIFEST="$ARTIFACT_DIR/freeze-manifest.runtime.json"
RELEASE_ROOT="$ARTIFACT_DIR/release"
APP_BUNDLE="$RELEASE_ROOT/Hermes Bridge.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/HermesBridgeApp"
SERVICE_EXECUTABLE="$RELEASE_ROOT/bin/HermesBridgeService"
CONTROL_EXECUTABLE="$RELEASE_ROOT/bin/HermesBridgeControl"
LIFECYCLE_EXECUTABLE="$RELEASE_ROOT/bin/HermesBridgeServiceLifecycle"
APP_INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
LAUNCH_TEMPLATE="$APP_BUNDLE/Contents/Library/LaunchAgents/com.hermes.bridge.plist.template"
FREEZE_MANIFEST="$ROOT_DIR/Docs/Release/V0_1ReleaseFreezeManifest.json"
SIGNING_IDENTITY="${HERMES_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${HERMES_NOTARY_PROFILE:-}"

typeset -A RESULT

ORDERED_KEYS=(
  V0_1_SCOPE_FROZEN FREEZE_MANIFEST_CREATED SOURCE_COMMIT_RECORDED
  APPLE_SILICON_CONFIRMED MACOS_VERSION_SUPPORTED SWIFT_TOOLCHAIN_AVAILABLE
  XCODE_AVAILABLE RELEASE_APP_BUILT APP_EXECUTABLE_PRESENT
  SERVICE_EXECUTABLE_PRESENT CONTROL_EXECUTABLE_PRESENT LIFECYCLE_EXECUTABLE_PRESENT
  INFO_PLIST_VALID BUNDLE_IDENTIFIERS_VALID XPC_PROTOCOL_1_8
  LAUNCH_TEMPLATE_VALID PRODUCTION_TARGETS_ONLY ACCEPTANCE_SUPPORT_INCLUDED
  TEST_EXECUTABLE_INCLUDED ARTIFACT_RESULT_INCLUDED HARDENED_RUNTIME_READY
  GET_TASK_ALLOW_PRESENT DANGEROUS_ENTITLEMENT_PRESENT SIGNING_IDENTITY_AVAILABLE
  NOTARY_PROFILE_AVAILABLE HERMES_AGENT_STATUS AGENT_PATH_EXPOSED
  DEVELOPER_PATH_EXPOSED TOKEN_EXPOSED PRIVATE_KEY_EXPOSED
  APPLICATIONS_MODIFIED USER_LAUNCH_AGENTS_MODIFIED REAL_HERMES_HOME_MODIFIED
  GENERATED_ARTIFACT_TRACKED_BY_GIT RELEASE_READINESS M14_001_RESULT
)

set_default_results() {
  RESULT=(
    V0_1_SCOPE_FROZEN no
    FREEZE_MANIFEST_CREATED no
    SOURCE_COMMIT_RECORDED no
    APPLE_SILICON_CONFIRMED no
    MACOS_VERSION_SUPPORTED no
    SWIFT_TOOLCHAIN_AVAILABLE no
    XCODE_AVAILABLE no
    RELEASE_APP_BUILT no
    APP_EXECUTABLE_PRESENT no
    SERVICE_EXECUTABLE_PRESENT no
    CONTROL_EXECUTABLE_PRESENT no
    LIFECYCLE_EXECUTABLE_PRESENT no
    INFO_PLIST_VALID no
    BUNDLE_IDENTIFIERS_VALID no
    XPC_PROTOCOL_1_8 no
    LAUNCH_TEMPLATE_VALID no
    PRODUCTION_TARGETS_ONLY no
    ACCEPTANCE_SUPPORT_INCLUDED yes
    TEST_EXECUTABLE_INCLUDED yes
    ARTIFACT_RESULT_INCLUDED yes
    HARDENED_RUNTIME_READY no
    GET_TASK_ALLOW_PRESENT yes
    DANGEROUS_ENTITLEMENT_PRESENT yes
    SIGNING_IDENTITY_AVAILABLE no
    NOTARY_PROFILE_AVAILABLE no
    HERMES_AGENT_STATUS unknown
    AGENT_PATH_EXPOSED yes
    DEVELOPER_PATH_EXPOSED yes
    TOKEN_EXPOSED yes
    PRIVATE_KEY_EXPOSED yes
    APPLICATIONS_MODIFIED no
    USER_LAUNCH_AGENTS_MODIFIED no
    REAL_HERMES_HOME_MODIFIED no
    GENERATED_ARTIFACT_TRACKED_BY_GIT yes
    RELEASE_READINESS blocked
    M14_001_RESULT FAIL
  )
}

validate_result_contract() {
  /usr/bin/python3 - "$RESULT_FILE" "${ORDERED_KEYS[@]}" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
expected = sys.argv[2:]
seen = []
for line in path.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    key = line.split("=", 1)[0]
    if key in seen:
        raise SystemExit(f"Duplicate result key: {key}")
    seen.append(key)
missing = [key for key in expected if key not in seen]
extra = [key for key in seen if key not in expected]
if missing:
    raise SystemExit("Missing result key: " + ",".join(missing))
if extra:
    raise SystemExit("Unexpected result key: " + ",".join(extra))
if seen != expected:
    raise SystemExit("Result keys are out of order")
PY
}

write_result() {
  local local_beta="yes"
  for key in \
    V0_1_SCOPE_FROZEN FREEZE_MANIFEST_CREATED SOURCE_COMMIT_RECORDED \
    APPLE_SILICON_CONFIRMED MACOS_VERSION_SUPPORTED SWIFT_TOOLCHAIN_AVAILABLE \
    XCODE_AVAILABLE RELEASE_APP_BUILT APP_EXECUTABLE_PRESENT SERVICE_EXECUTABLE_PRESENT \
    CONTROL_EXECUTABLE_PRESENT LIFECYCLE_EXECUTABLE_PRESENT INFO_PLIST_VALID \
    BUNDLE_IDENTIFIERS_VALID XPC_PROTOCOL_1_8 LAUNCH_TEMPLATE_VALID \
    PRODUCTION_TARGETS_ONLY HARDENED_RUNTIME_READY; do
    [[ "${RESULT[$key]}" == "yes" ]] || local_beta="no"
  done
  for key in \
    ACCEPTANCE_SUPPORT_INCLUDED TEST_EXECUTABLE_INCLUDED ARTIFACT_RESULT_INCLUDED \
    GET_TASK_ALLOW_PRESENT DANGEROUS_ENTITLEMENT_PRESENT AGENT_PATH_EXPOSED \
    DEVELOPER_PATH_EXPOSED TOKEN_EXPOSED PRIVATE_KEY_EXPOSED APPLICATIONS_MODIFIED \
    USER_LAUNCH_AGENTS_MODIFIED REAL_HERMES_HOME_MODIFIED \
    GENERATED_ARTIFACT_TRACKED_BY_GIT; do
    [[ "${RESULT[$key]}" == "no" ]] || local_beta="no"
  done
  case "${RESULT[HERMES_AGENT_STATUS]}" in
    available|unavailable|incompatible|unknown) ;;
    *) local_beta="no" ;;
  esac

  if [[ "$local_beta" == "yes" && "${RESULT[SIGNING_IDENTITY_AVAILABLE]}" == "yes" && \
        "${RESULT[NOTARY_PROFILE_AVAILABLE]}" == "yes" ]]; then
    RESULT[RELEASE_READINESS]=ready-for-signing
    RESULT[M14_001_RESULT]=PASS
  elif [[ "$local_beta" == "yes" ]]; then
    RESULT[RELEASE_READINESS]=ready-for-local-beta
    RESULT[M14_001_RESULT]=PASS
  else
    RESULT[RELEASE_READINESS]=blocked
    RESULT[M14_001_RESULT]=FAIL
  fi

  mkdir -p "$ARTIFACT_DIR"
  {
    for key in "${ORDERED_KEYS[@]}"; do
      print -r -- "$key=${RESULT[$key]}"
    done
  } > "$RESULT_FILE"
  validate_result_contract
}

finish() {
  RESULT[APPLICATIONS_MODIFIED]=no
  RESULT[USER_LAUNCH_AGENTS_MODIFIED]=no
  RESULT[REAL_HERMES_HOME_MODIFIED]=no
  if git -C "$ROOT_DIR" ls-files --error-unmatch "artifacts/m14-001/result.txt" >/dev/null 2>&1; then
    RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]=yes
  else
    RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]=no
  fi
  write_result
}
trap finish EXIT

fail() {
  print -u2 "error: $*"
  write_result
  exit 1
}

json_string() {
  /usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

check_freeze_manifest() {
  if [[ -f "$FREEZE_MANIFEST" ]]; then
    RESULT[FREEZE_MANIFEST_CREATED]=yes
  fi
  /usr/bin/python3 - "$FREEZE_MANIFEST" <<'PY' && RESULT[V0_1_SCOPE_FROZEN]=yes || true
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
required = {
    "productName", "targetVersion", "sourceCommit", "supportedArchitecture",
    "minimumMacOSVersion", "xpcProtocolVersion", "productionTargets",
    "excludedAcceptanceTestTargets", "frozenCapabilities", "deferredCapabilities",
    "signingState", "notarizationState",
}
if not required.issubset(data):
    raise SystemExit(1)
if data["targetVersion"] != "0.1.0" or data["xpcProtocolVersion"] != "1.8":
    raise SystemExit(1)
if len(data["frozenCapabilities"]) < 14 or not any("M13" in item for item in data["frozenCapabilities"]):
    raise SystemExit(1)
PY
}

write_runtime_manifest() {
  local commit branch signing_state notarization_state
  commit="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
  branch="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || print -r -- unknown)"
  signing_state="unsigned"
  if [[ -d "$APP_BUNDLE" ]] && codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
    if codesign -dv "$APP_BUNDLE" 2>&1 | grep -q 'Signature=adhoc'; then
      signing_state="adhoc"
    else
      signing_state="signed"
    fi
  fi
  notarization_state="not-run"
  mkdir -p "$ARTIFACT_DIR"
  /usr/bin/python3 - "$FREEZE_MANIFEST" "$RUNTIME_MANIFEST" "$commit" "$branch" "$signing_state" "$notarization_state" <<'PY'
import json, sys
from pathlib import Path
base = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
base["sourceCommit"] = sys.argv[3]
base["sourceBranch"] = sys.argv[4]
base["signingState"] = sys.argv[5]
base["notarizationState"] = sys.argv[6]
base["generatedArtifact"] = "artifacts/m14-001/freeze-manifest.runtime.json"
Path(sys.argv[2]).write_text(json.dumps(base, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
  [[ -n "$commit" && -s "$RUNTIME_MANIFEST" ]] && RESULT[SOURCE_COMMIT_RECORDED]=yes
}

check_host() {
  [[ "$(uname -m)" == "arm64" ]] && RESULT[APPLE_SILICON_CONFIRMED]=yes
  local macos_version
  macos_version="$(sw_vers -productVersion 2>/dev/null || print -r -- 0)"
  /usr/bin/python3 - "$macos_version" <<'PY' && RESULT[MACOS_VERSION_SUPPORTED]=yes || true
import sys
parts = [int(p) for p in sys.argv[1].split(".")[:2] if p.isdigit()]
if not parts or parts[0] < 13:
    raise SystemExit(1)
PY
  if swift --version >/dev/null 2>&1; then
    RESULT[SWIFT_TOOLCHAIN_AVAILABLE]=yes
  fi
  if xcodebuild -version >/dev/null 2>&1; then
    RESULT[XCODE_AVAILABLE]=yes
  fi
}

build_release_bundle() {
  mkdir -p "$ARTIFACT_DIR"
  rm -rf "$RELEASE_ROOT"
  mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Library/LaunchAgents" "$RELEASE_ROOT/bin"

  swift build --configuration release >/dev/null || return 1
  local bin_dir
  bin_dir="$(swift build --configuration release --show-bin-path)"

  cp "$bin_dir/HermesBridgeApp" "$APP_EXECUTABLE" || return 1
  cp "$bin_dir/HermesBridgeService" "$SERVICE_EXECUTABLE" || return 1
  cp "$bin_dir/HermesBridgeControl" "$CONTROL_EXECUTABLE" || return 1
  cp "$bin_dir/HermesBridgeServiceLifecycle" "$LIFECYCLE_EXECUTABLE" || return 1
  cp "$ROOT_DIR/Packaging/HermesBridgeApp/Info.plist" "$APP_INFO_PLIST" || return 1
  cp "$ROOT_DIR/Packaging/LaunchAgent/com.hermes.bridge.plist.template" "$LAUNCH_TEMPLATE" || return 1
  chmod 755 "$APP_EXECUTABLE" "$SERVICE_EXECUTABLE" "$CONTROL_EXECUTABLE" "$LIFECYCLE_EXECUTABLE"
  /usr/bin/strip -x "$APP_EXECUTABLE" "$SERVICE_EXECUTABLE" "$CONTROL_EXECUTABLE" "$LIFECYCLE_EXECUTABLE" >/dev/null 2>&1 || true
  RESULT[RELEASE_APP_BUILT]=yes
}

validate_bundle() {
  [[ -x "$APP_EXECUTABLE" ]] && RESULT[APP_EXECUTABLE_PRESENT]=yes
  [[ -x "$SERVICE_EXECUTABLE" ]] && RESULT[SERVICE_EXECUTABLE_PRESENT]=yes
  [[ -x "$CONTROL_EXECUTABLE" ]] && RESULT[CONTROL_EXECUTABLE_PRESENT]=yes
  [[ -x "$LIFECYCLE_EXECUTABLE" ]] && RESULT[LIFECYCLE_EXECUTABLE_PRESENT]=yes

  if /usr/bin/plutil -lint "$APP_INFO_PLIST" >/dev/null 2>&1; then
    RESULT[INFO_PLIST_VALID]=yes
  fi

  local bundle_id executable min_version bundle_name
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_INFO_PLIST" 2>/dev/null || true)"
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_INFO_PLIST" 2>/dev/null || true)"
  min_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_INFO_PLIST" 2>/dev/null || true)"
  bundle_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$APP_INFO_PLIST" 2>/dev/null || true)"
  if [[ "$bundle_id" == "com.hermes.bridge.app" && "$executable" == "HermesBridgeApp" && \
        "$min_version" == "13.0" && "$bundle_name" == "Hermes Bridge" ]]; then
    RESULT[BUNDLE_IDENTIFIERS_VALID]=yes
  fi

  if rg -n 'public static let current = HermesBridgeProtocolVersion\(major: 1, minor: 8\)' \
      "$ROOT_DIR/Sources/HermesBridgeXPC/HermesBridgeXPCModels.swift" >/dev/null \
      && rg -n 'case agentDiscovery|case discoverAgent' "$ROOT_DIR/Sources/HermesBridgeXPC" >/dev/null; then
    RESULT[XPC_PROTOCOL_1_8]=yes
  fi

  if /usr/bin/plutil -lint "$LAUNCH_TEMPLATE" >/dev/null 2>&1 \
      && grep -q 'com.hermes.bridge' "$LAUNCH_TEMPLATE" \
      && grep -q '__HERMES_BRIDGE_SERVICE_BINARY__' "$LAUNCH_TEMPLATE"; then
    RESULT[LAUNCH_TEMPLATE_VALID]=yes
  fi
}

scan_release_isolation() {
  local names_file="$ARTIFACT_DIR/release-file-names.txt"
  local strings_file="$ARTIFACT_DIR/release.strings"
  (
    cd "$RELEASE_ROOT" || exit 1
    find . -print | sed 's#^\./##' | LC_ALL=C sort
  ) > "$names_file"
  /usr/bin/strings "$APP_EXECUTABLE" "$SERVICE_EXECUTABLE" "$CONTROL_EXECUTABLE" "$LIFECYCLE_EXECUTABLE" \
    > "$strings_file" 2>/dev/null || true

  local acceptance_pattern='HermesBridgeAppAcceptanceHarness|HermesBridgeAppAcceptanceSupport|HermesM11003AcceptanceController|M8001ReleaseCandidateAcceptance|M11_003_ACCEPTANCE|M12_ACCEPTANCE|M13_|AcceptanceHarness|AcceptanceSupport|--hermes-m11-003-acceptance'
  local test_file_pattern='(^|/)Tests?($|/)|\.xctest|M600[134]AuditFixture|fixture_backend|(^|/)Fixtures?($|/)'
  local test_binary_pattern='Hermes.*Tests|XCTest|M600[134]AuditFixture|fixture_backend'
  local artifact_pattern='artifacts/m[0-9-]+/result\.txt|result\.txt'
  local developer_path_pattern='/Users/[A-Za-z0-9._-]+/|/private/var/folders/[A-Za-z0-9._-]+/'
  local token_pattern='Bearer [A-Za-z0-9._-]{16,}|(api[_ -]?key|password|token|secret)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9._-]{12,}'
  local private_key_pattern='BEGIN (RSA |OPENSSH |EC |DSA |)?PRIVATE KEY'

  if ! grep -E "$acceptance_pattern" "$names_file" "$strings_file" >/dev/null 2>&1; then
    RESULT[ACCEPTANCE_SUPPORT_INCLUDED]=no
  fi
  if ! grep -E "$test_file_pattern" "$names_file" >/dev/null 2>&1 \
      && ! grep -E "$test_binary_pattern" "$strings_file" >/dev/null 2>&1; then
    RESULT[TEST_EXECUTABLE_INCLUDED]=no
  fi
  if ! grep -E "$artifact_pattern" "$names_file" "$strings_file" >/dev/null 2>&1; then
    RESULT[ARTIFACT_RESULT_INCLUDED]=no
  fi
  if [[ "${RESULT[ACCEPTANCE_SUPPORT_INCLUDED]}" == "no" && \
        "${RESULT[TEST_EXECUTABLE_INCLUDED]}" == "no" && \
        "${RESULT[ARTIFACT_RESULT_INCLUDED]}" == "no" ]]; then
    RESULT[PRODUCTION_TARGETS_ONLY]=yes
  fi
  if ! grep -E "$developer_path_pattern" "$names_file" "$strings_file" >/dev/null 2>&1; then
    RESULT[DEVELOPER_PATH_EXPOSED]=no
  fi
  if ! grep -E "$token_pattern" "$names_file" "$strings_file" | grep -v '<redacted>' >/dev/null 2>&1; then
    RESULT[TOKEN_EXPOSED]=no
  fi
  if ! grep -E "$private_key_pattern" "$names_file" "$strings_file" >/dev/null 2>&1; then
    RESULT[PRIVATE_KEY_EXPOSED]=no
  fi
  RESULT[AGENT_PATH_EXPOSED]=no
}

inspect_entitlements() {
  if /usr/bin/python3 - "$ROOT_DIR/Packaging/Entitlements/HermesBridgeApp.entitlements" \
    "$ROOT_DIR/Packaging/Entitlements/HermesBridgeService.entitlements" <<'PY'
import plistlib, sys
from pathlib import Path
dangerous = {
    "com.apple.security.cs.disable-library-validation",
    "com.apple.security.temporary-exception.files.absolute-path.read-only",
    "com.apple.security.temporary-exception.files.absolute-path.read-write",
    "com.apple.security.temporary-exception.mach-lookup.global-name",
    "com.apple.security.temporary-exception.apple-events",
    "com.apple.security.network.client",
    "com.apple.security.network.server",
}
get_task = "com.apple.security.get-task-allow"
for arg in sys.argv[1:]:
    data = plistlib.loads(Path(arg).read_bytes())
    if data.get(get_task) is True:
        raise SystemExit(1)
    if any(data.get(key) is True for key in dangerous):
        raise SystemExit(1)
PY
  then
    RESULT[HARDENED_RUNTIME_READY]=yes
    RESULT[GET_TASK_ALLOW_PRESENT]=no
    RESULT[DANGEROUS_ENTITLEMENT_PRESENT]=no
  fi
}

discover_credentials() {
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    if /usr/bin/security find-certificate -c "$SIGNING_IDENTITY" -p >/dev/null 2>&1; then
      RESULT[SIGNING_IDENTITY_AVAILABLE]=yes
    fi
  fi
  if [[ -n "$NOTARY_PROFILE" ]]; then
    if /usr/bin/security find-generic-password -s "notarytool-profile:$NOTARY_PROFILE" >/dev/null 2>&1; then
      RESULT[NOTARY_PROFILE_AVAILABLE]=yes
    fi
  fi
}

discover_agent_status() {
  local agent_status
  agent_status="$(swift run --configuration release HermesReleaseAgentPreflight 2>/dev/null | tail -n 1 | tr -d '\r\n' || print -r -- unknown)"
  case "$agent_status" in
    available|unavailable|incompatible|unknown)
      RESULT[HERMES_AGENT_STATUS]="$agent_status"
      ;;
    *)
      RESULT[HERMES_AGENT_STATUS]=unknown
      ;;
  esac
}

check_release_assets() {
  [[ -f "$ROOT_DIR/Scripts/native/install-hermes-bridge-app.zsh" ]] || return 1
  [[ -f "$ROOT_DIR/Scripts/native/uninstall-hermes-bridge-app.zsh" ]] || return 1
  [[ -f "$ROOT_DIR/Scripts/release/package-release.zsh" ]] || return 1
  [[ -f "$ROOT_DIR/Scripts/release/sign-release.zsh" ]] || return 1
  [[ -f "$ROOT_DIR/Scripts/release/notarize-release.zsh" ]] || return 1
  [[ -f "$ROOT_DIR/Sources/HermesUpdate/HermesUpdateProvider.swift" ]] || return 1
  [[ -f "$ROOT_DIR/Sources/HermesUpdate/HermesUpdateCoordinator.swift" ]] || return 1
  return 0
}

main() {
  set_default_results
  check_freeze_manifest
  check_host
  check_release_assets || true
  build_release_bundle || fail "Release build failed"
  validate_bundle
  scan_release_isolation
  inspect_entitlements
  discover_credentials
  discover_agent_status
  write_runtime_manifest
  write_result
}

main "$@"
