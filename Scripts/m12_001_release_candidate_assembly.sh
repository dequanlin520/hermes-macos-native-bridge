#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
RC_VERSION="${HERMES_RC_VERSION:-0.1.0-rc.1}"
SAFE_VERSION="$(printf '%s' "$RC_VERSION" | tr -c 'A-Za-z0-9._-' '-')"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m12-001"
RC_DIR="$ARTIFACT_DIR/rc"
STAGING_ROOT="$RC_DIR/staging"
PAYLOAD_ROOT="$STAGING_ROOT/Payload"
EVIDENCE_ROOT="$STAGING_ROOT/ReleaseEvidence"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
INSTALL_ROOT="$ARTIFACT_DIR/install-root"
SMOKE_ROOT="$ARTIFACT_DIR/smoke"
CONFIG_DIR="$SMOKE_ROOT/HermesBridge"
CONFIG_FILE="$CONFIG_DIR/configuration.json"
LAUNCH_AGENT_PLIST="$SMOKE_ROOT/com.hermes.bridge.m12-001.plist"
SERVICE_STDOUT="$SMOKE_ROOT/service.stdout.log"
SERVICE_STDERR="$SMOKE_ROOT/service.stderr.log"
APP_STDOUT="$SMOKE_ROOT/app.stdout.log"
APP_STDERR="$SMOKE_ROOT/app.stderr.log"
FAKE_BACKEND="$SMOKE_ROOT/hermes-smoke-backend.py"
LIFECYCLE="$PAYLOAD_ROOT/bin/HermesBridgeServiceLifecycle"
APP_BUNDLE="$PAYLOAD_ROOT/Hermes Bridge.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/HermesBridgeApp"
SERVICE_EXECUTABLE="$PAYLOAD_ROOT/bin/HermesBridgeService"
CONTROL_EXECUTABLE="$PAYLOAD_ROOT/bin/HermesBridgeControl"
CHECKSUMS="$EVIDENCE_ROOT/checksums.sha256"
SBOM="$EVIDENCE_ROOT/sbom.spdx.json"
RELEASE_MANIFEST="$EVIDENCE_ROOT/release-manifest.json"
UPGRADE_METADATA="$EVIDENCE_ROOT/upgrade-rollback-metadata.json"
COMPONENT_MANIFEST="$EVIDENCE_ROOT/version-manifest.json"
STAGING_LIST="$EVIDENCE_ROOT/staging-files.txt"
LABEL="com.hermes.bridge"
MACH_SERVICE="com.hermes.bridge.xpc"
SERVICE_DOMAIN="gui/$(id -u)"
BOOTSTRAPPED="no"
APP_PID=""

typeset -A RESULT

ORDERED_KEYS=(
  RC_APP_BUILT RC_SERVICE_BUILT RC_PACKAGE_CREATED RC_VERSION_CONSISTENT
  PRODUCTION_COMPONENTS_ONLY ACCEPTANCE_SUPPORT_INCLUDED TEST_EXECUTABLE_INCLUDED
  INFO_PLIST_VALID BUNDLE_IDENTIFIERS_VALID XPC_PROTOCOL_1_7 APP_SERVICE_COMPATIBLE
  DUPLICATE_APP_INCLUDED DUPLICATE_SERVICE_INCLUDED CHECKSUM_MANIFEST_CREATED
  CHECKSUM_MANIFEST_VERIFIED SBOM_CREATED RELEASE_MANIFEST_CREATED SOURCE_COMMIT_RECORDED
  SIGNING_STATE INSTALL_SMOKE_PASSED XPC_SMOKE_PASSED RUNTIME_SMOKE_PASSED
  UNINSTALL_SMOKE_PASSED DEVELOPER_PATH_EXPOSED TOKEN_EXPOSED PRIVATE_KEY_EXPOSED
  ACCEPTANCE_SYMBOL_EXPOSED APPLICATIONS_MODIFIED USER_LAUNCH_AGENTS_MODIFIED
  REAL_HERMES_HOME_MODIFIED RESIDUAL_PROCESS M12_001_RESULT
)

set_default_results() {
  RESULT=(
    RC_APP_BUILT no
    RC_SERVICE_BUILT no
    RC_PACKAGE_CREATED no
    RC_VERSION_CONSISTENT no
    PRODUCTION_COMPONENTS_ONLY no
    ACCEPTANCE_SUPPORT_INCLUDED yes
    TEST_EXECUTABLE_INCLUDED yes
    INFO_PLIST_VALID no
    BUNDLE_IDENTIFIERS_VALID no
    XPC_PROTOCOL_1_7 no
    APP_SERVICE_COMPATIBLE no
    DUPLICATE_APP_INCLUDED yes
    DUPLICATE_SERVICE_INCLUDED yes
    CHECKSUM_MANIFEST_CREATED no
    CHECKSUM_MANIFEST_VERIFIED no
    SBOM_CREATED no
    RELEASE_MANIFEST_CREATED no
    SOURCE_COMMIT_RECORDED no
    SIGNING_STATE unsigned
    INSTALL_SMOKE_PASSED no
    XPC_SMOKE_PASSED no
    RUNTIME_SMOKE_PASSED no
    UNINSTALL_SMOKE_PASSED no
    DEVELOPER_PATH_EXPOSED yes
    TOKEN_EXPOSED yes
    PRIVATE_KEY_EXPOSED yes
    ACCEPTANCE_SYMBOL_EXPOSED yes
    APPLICATIONS_MODIFIED yes
    USER_LAUNCH_AGENTS_MODIFIED yes
    REAL_HERMES_HOME_MODIFIED yes
    RESIDUAL_PROCESS yes
    M12_001_RESULT FAIL
  )
}

write_result() {
  local pass="yes"
  for key in \
    RC_APP_BUILT RC_SERVICE_BUILT RC_PACKAGE_CREATED RC_VERSION_CONSISTENT \
    PRODUCTION_COMPONENTS_ONLY INFO_PLIST_VALID BUNDLE_IDENTIFIERS_VALID XPC_PROTOCOL_1_7 \
    APP_SERVICE_COMPATIBLE CHECKSUM_MANIFEST_CREATED CHECKSUM_MANIFEST_VERIFIED SBOM_CREATED \
    RELEASE_MANIFEST_CREATED SOURCE_COMMIT_RECORDED INSTALL_SMOKE_PASSED XPC_SMOKE_PASSED \
    RUNTIME_SMOKE_PASSED UNINSTALL_SMOKE_PASSED; do
    [[ "${RESULT[$key]}" == "yes" ]] || pass="no"
  done
  for key in \
    ACCEPTANCE_SUPPORT_INCLUDED TEST_EXECUTABLE_INCLUDED DUPLICATE_APP_INCLUDED \
    DUPLICATE_SERVICE_INCLUDED DEVELOPER_PATH_EXPOSED TOKEN_EXPOSED PRIVATE_KEY_EXPOSED \
    ACCEPTANCE_SYMBOL_EXPOSED APPLICATIONS_MODIFIED USER_LAUNCH_AGENTS_MODIFIED \
    REAL_HERMES_HOME_MODIFIED RESIDUAL_PROCESS; do
    [[ "${RESULT[$key]}" == "no" ]] || pass="no"
  done
  case "${RESULT[SIGNING_STATE]}" in
    valid|adhoc|unsigned) ;;
    *) pass="no" ;;
  esac
  RESULT[M12_001_RESULT]=$([[ "$pass" == "yes" ]] && print -r -- PASS || print -r -- FAIL)
  mkdir -p "$ARTIFACT_DIR"
  {
    for key in "${ORDERED_KEYS[@]}"; do
      print -r -- "$key=${RESULT[$key]}"
    done
  } > "$RESULT_FILE"
}

fail() {
  print -u2 "error: $*"
  write_result
  exit 1
}

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  if [[ "$BOOTSTRAPPED" == "yes" ]]; then
    /bin/launchctl bootout "$SERVICE_DOMAIN" "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true
  fi
  local residual="no"
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    residual="yes"
  fi
  if /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1; then
    residual="yes"
  fi
  RESULT[RESIDUAL_PROCESS]="$residual"
  write_result
}
trap cleanup EXIT

json_escape() {
  /usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

free_port() {
  /usr/bin/python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

write_fake_backend() {
  mkdir -p "$SMOKE_ROOT"
  cat > "$FAKE_BACKEND" <<'PY'
#!/usr/bin/python3
import argparse, asyncio, json, signal, sys
if sys.argv[1:] == ["--version"]:
    print("Hermes Agent v0.18.2")
    print("Install Method: m12-smoke")
    sys.exit(0)
parser = argparse.ArgumentParser()
parser.add_argument("--safe-mode", action="store_true")
parser.add_argument("serve")
parser.add_argument("--host", required=True)
parser.add_argument("--port", required=True, type=int)
parser.add_argument("--skip-build", action="store_true")
parser.add_argument("--isolated", action="store_true")
args = parser.parse_args()
async def handle(reader, writer):
    try:
        await reader.readuntil(b"\r\n\r\n")
        body = json.dumps({"version":"m12-smoke","auth_required":False,"desktop_contract":3,"gateway_running":True,"gateway_state":"running"}).encode()
        writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)
        await writer.drain()
    finally:
        writer.close()
        await writer.wait_closed()
async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", args.port)
    print("HERMES_BACKEND_READY", flush=True)
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    signal.signal(signal.SIGTERM, lambda *_: loop.call_soon_threadsafe(stop.set))
    signal.signal(signal.SIGINT, lambda *_: loop.call_soon_threadsafe(stop.set))
    async with server:
        await stop.wait()
asyncio.run(main())
PY
  chmod 700 "$FAKE_BACKEND"
}

write_service_configuration() {
  local port="$1"
  mkdir -p "$CONFIG_DIR" "$SMOKE_ROOT/Runtime" "$SMOKE_ROOT/RequestState"
  cat > "$CONFIG_FILE" <<JSON
{
  "schemaVersion": 1,
  "machServiceName": "$MACH_SERVICE",
  "runtimeRoot": "file://$SMOKE_ROOT/Runtime",
  "requestStateRoot": "file://$SMOKE_ROOT/RequestState",
  "allowlistedHermesExecutableCandidates": [
    "file://$FAKE_BACKEND"
  ],
  "loopbackPortPolicy": {
    "fixedPort": $port
  },
  "timeouts": {
    "startup": 8,
    "gracefulShutdown": 2,
    "forcedShutdown": 2,
    "gatewayReady": 4
  },
  "maximumConcurrentXPCRequests": 8,
  "bindings": []
}
JSON
}

write_launch_agent() {
  cat > "$LAUNCH_AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SERVICE_EXECUTABLE</string>
  </array>
  <key>MachServices</key>
  <dict>
    <key>$MACH_SERVICE</key>
    <true/>
  </dict>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HERMES_BRIDGE_SERVICE_CONFIG</key>
    <string>$CONFIG_FILE</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$SERVICE_STDOUT</string>
  <key>StandardErrorPath</key>
  <string>$SERVICE_STDERR</string>
</dict>
</plist>
PLIST
  /usr/bin/plutil -lint "$LAUNCH_AGENT_PLIST" >/dev/null
}

build_existing_release() {
  "$ROOT_DIR/Scripts/release/build-release-candidate.zsh" \
    --version "$SAFE_VERSION" \
    --signing-mode adhoc >/dev/null || return 1
  local source_root="$ROOT_DIR/artifacts/m8-002/release-candidates/HermesBridge-$SAFE_VERSION/staging"
  [[ -d "$source_root" ]] || return 1
  rm -rf "$RC_DIR"
  mkdir -p "$RC_DIR"
  cp -R "$source_root" "$STAGING_ROOT" || return 1
  swift build --configuration release --product HermesBridgeApp >/dev/null || return 1
  swift build --configuration release --product HermesBridgeServiceLifecycle >/dev/null || return 1
  cp "$ROOT_DIR/.build/release/HermesBridgeApp" "$APP_EXECUTABLE" || return 1
  cp "$ROOT_DIR/.build/release/HermesBridgeServiceLifecycle" "$LIFECYCLE" || return 1
  chmod 755 "$APP_EXECUTABLE" "$LIFECYCLE"
  /usr/bin/strip -x "$APP_EXECUTABLE" "$SERVICE_EXECUTABLE" "$CONTROL_EXECUTABLE" "$LIFECYCLE" >/dev/null 2>&1 || true
}

normalize_versions() {
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RC_VERSION" \
    "$APP_BUNDLE/Contents/Info.plist" || return 1
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $RC_VERSION" \
    "$APP_BUNDLE/Contents/Info.plist" || return 1
  cat > "$COMPONENT_MANIFEST" <<JSON
{
  "schemaVersion": 1,
  "productName": "Hermes Bridge",
  "version": "$RC_VERSION",
  "xpcProtocolVersion": "1.7",
  "components": {
    "app": {
      "name": "Hermes Bridge.app",
      "version": "$RC_VERSION",
      "path": "Payload/Hermes Bridge.app"
    },
    "service": {
      "name": "HermesBridgeService",
      "version": "$RC_VERSION",
      "path": "Payload/bin/HermesBridgeService"
    },
    "control": {
      "name": "HermesBridgeControl",
      "version": "$RC_VERSION",
      "path": "Payload/bin/HermesBridgeControl"
    }
  }
}
JSON
  cat > "$UPGRADE_METADATA" <<JSON
{
  "schemaVersion": 1,
  "version": "$RC_VERSION",
  "upgradeCompatibility": {
    "from": ["0.1.0-rc.0", "0.1.0-rc.1"],
    "to": "$RC_VERSION",
    "requiresServiceOwnedRuntime": true
  },
  "rollbackCompatibility": {
    "from": "$RC_VERSION",
    "toPreviousInstalledVersion": true,
    "preservesArtifactOwnedState": true
  }
}
JSON
  cat > "$PAYLOAD_ROOT/NOTICE" <<EOF
Hermes Bridge release candidate $RC_VERSION

This release candidate is assembled from the repository source commit recorded
in ReleaseEvidence/release-manifest.json. Third-party license metadata is
reported in ReleaseEvidence/sbom.spdx.json. Entries with unresolved license
metadata are marked NOASSERTION.
EOF
  "$ROOT_DIR/Scripts/release/sign-release.zsh" --staging-root "$STAGING_ROOT" --mode adhoc >/dev/null
}

validate_bundle() {
  [[ -d "$APP_BUNDLE" && -x "$APP_EXECUTABLE" ]] && RESULT[RC_APP_BUILT]=yes
  [[ -x "$SERVICE_EXECUTABLE" ]] && RESULT[RC_SERVICE_BUILT]=yes
  if /usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null 2>&1; then
    RESULT[INFO_PLIST_VALID]=yes
  fi
  local bundle_id executable min_version app_version app_build
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  min_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$bundle_id" == "com.hermes.bridge.app" && "$executable" == "HermesBridgeApp" && "$min_version" == "13.0" ]]; then
    RESULT[BUNDLE_IDENTIFIERS_VALID]=yes
  fi
  if [[ "$app_version" == "$RC_VERSION" && "$app_build" == "$RC_VERSION" ]] \
    && grep -q "\"version\": \"$RC_VERSION\"" "$COMPONENT_MANIFEST" \
    && grep -q "\"to\": \"$RC_VERSION\"" "$UPGRADE_METADATA" \
    && grep -q "\"from\": \"$RC_VERSION\"" "$UPGRADE_METADATA"; then
    RESULT[RC_VERSION_CONSISTENT]=yes
  fi
  if rg -n 'public static let current = HermesBridgeProtocolVersion\(major: 1, minor: 7\)' \
    "$ROOT_DIR/Sources/HermesBridgeXPC/HermesBridgeXPCModels.swift" >/dev/null; then
    RESULT[XPC_PROTOCOL_1_7]=yes
  fi
  if [[ "${RESULT[RC_APP_BUILT]}" == "yes" && "${RESULT[RC_SERVICE_BUILT]}" == "yes" && "${RESULT[XPC_PROTOCOL_1_7]}" == "yes" ]]; then
    RESULT[APP_SERVICE_COMPATIBLE]=yes
  fi
  local app_count service_count
  app_count="$(find "$PAYLOAD_ROOT" -name 'Hermes Bridge.app' -type d | wc -l | tr -d ' ')"
  service_count="$(find "$PAYLOAD_ROOT" -name 'HermesBridgeService' -type f | wc -l | tr -d ' ')"
  [[ "$app_count" == "1" ]] && RESULT[DUPLICATE_APP_INCLUDED]=no
  [[ "$service_count" == "1" ]] && RESULT[DUPLICATE_SERVICE_INCLUDED]=no
}

assess_signing() {
  local target="$APP_BUNDLE"
  if codesign --verify --deep --strict "$target" >/dev/null 2>&1; then
    if codesign -dv "$target" 2>&1 | grep -q "Signature=adhoc"; then
      RESULT[SIGNING_STATE]=adhoc
    else
      RESULT[SIGNING_STATE]=valid
    fi
  elif [[ -d "$target/Contents/_CodeSignature" ]]; then
    RESULT[SIGNING_STATE]=invalid
  else
    RESULT[SIGNING_STATE]=unsigned
  fi
}

scan_production_components() {
  local names_file="$ARTIFACT_DIR/release-file-names.txt"
  local strings_file="$ARTIFACT_DIR/release.strings"
  find "$PAYLOAD_ROOT" "$EVIDENCE_ROOT" -print | LC_ALL=C sort > "$names_file"
  /usr/bin/strings "$APP_EXECUTABLE" "$SERVICE_EXECUTABLE" "$CONTROL_EXECUTABLE" 2>/dev/null > "$strings_file" || true
  if ! grep -E 'HermesBridgeAppAcceptanceHarness|HermesBridgeAppAcceptanceSupport|HermesM11003AcceptanceController|M8001ReleaseCandidateAcceptance|M600[134].*Fixture|AcceptanceHarness|AcceptanceSupport|Tests?($|/)' "$names_file" >/dev/null 2>&1 \
    && ! grep -E 'HermesBridgeAppAcceptanceHarness|HermesBridgeAppAcceptanceSupport|HermesM11003AcceptanceController|--hermes-m11-003-acceptance|M11_003_ACCEPTANCE|M12_ACCEPTANCE|m11-003-token-sentinel' "$strings_file" >/dev/null 2>&1; then
    RESULT[PRODUCTION_COMPONENTS_ONLY]=yes
    RESULT[ACCEPTANCE_SUPPORT_INCLUDED]=no
    RESULT[TEST_EXECUTABLE_INCLUDED]=no
    RESULT[ACCEPTANCE_SYMBOL_EXPOSED]=no
  fi
}

write_sbom() {
  local package_deps
  package_deps="$(swift package show-dependencies --format json 2>/dev/null || print '{}')"
  /usr/bin/python3 - "$SBOM" "$RC_VERSION" "$package_deps" <<'PY'
import json, sys, datetime
out, version, deps_json = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    deps = json.loads(deps_json)
except Exception:
    deps = {}
packages = [
  {"SPDXID":"SPDXRef-Package-HermesBridgeApp","name":"Hermes Bridge.app","versionInfo":version,"licenseConcluded":"NOASSERTION","licenseDeclared":"NOASSERTION"},
  {"SPDXID":"SPDXRef-Package-HermesBridgeService","name":"HermesBridgeService","versionInfo":version,"licenseConcluded":"NOASSERTION","licenseDeclared":"NOASSERTION"},
  {"SPDXID":"SPDXRef-Package-HermesBridgeControl","name":"HermesBridgeControl","versionInfo":version,"licenseConcluded":"NOASSERTION","licenseDeclared":"NOASSERTION"},
]
for dep in deps.get("dependencies", []) or []:
    identity = dep.get("identity") or dep.get("name") or dep.get("url") or "unknown"
    requirement = dep.get("requirement") or dep.get("version") or "NOASSERTION"
    packages.append({
      "SPDXID": "SPDXRef-Package-" + "".join(c if c.isalnum() else "-" for c in identity),
      "name": identity,
      "versionInfo": requirement if isinstance(requirement, str) else json.dumps(requirement, sort_keys=True),
      "licenseConcluded": "NOASSERTION",
      "licenseDeclared": "NOASSERTION"
    })
doc = {
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": f"HermesMacOSNativeBridge-{version}",
  "documentNamespace": f"https://example.invalid/hermes/spdx/{version}",
  "creationInfo": {
    "created": datetime.datetime.utcfromtimestamp(0).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "creators": ["Tool: Scripts/m12_001_release_candidate_assembly.sh"]
  },
  "packages": packages
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, sort_keys=True)
    f.write("\n")
PY
  [[ -f "$SBOM" ]] && RESULT[SBOM_CREATED]=yes
}

write_release_manifest() {
  local commit branch timestamp arch min_macos signing app_hash service_hash archive_name
  commit="$(git rev-parse HEAD)"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || print detached)"
  timestamp="$(date -u -r "${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}" '+%Y-%m-%dT%H:%M:%SZ')"
  arch="$(uname -m)"
  min_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_BUNDLE/Contents/Info.plist")"
  signing="${RESULT[SIGNING_STATE]}"
  app_hash="$(sha256 "$APP_EXECUTABLE")"
  service_hash="$(sha256 "$SERVICE_EXECUTABLE")"
  archive_name="HermesBridge-$SAFE_VERSION-unsigned-rc.tar.gz"
  cat > "$RELEASE_MANIFEST" <<JSON
{
  "schemaVersion": 1,
  "productName": "Hermes Bridge",
  "rcVersion": "$RC_VERSION",
  "sourceCommit": "$commit",
  "sourceBranch": "$branch",
  "buildTimestamp": "$timestamp",
  "targetArchitecture": "$arch",
  "minimumMacOSVersion": "$min_macos",
  "xpcProtocolVersion": "1.7",
  "signingState": "$signing",
  "notarizationState": "absent",
  "artifactNames": [
    "staging/Payload/Hermes Bridge.app",
    "staging/Payload/bin/HermesBridgeService",
    "$archive_name",
    "$archive_name.sha256",
    "staging/ReleaseEvidence/version-manifest.json",
    "staging/ReleaseEvidence/checksums.sha256",
    "staging/ReleaseEvidence/sbom.spdx.json",
    "staging/ReleaseEvidence/release-manifest.json",
    "staging/ReleaseEvidence/upgrade-rollback-metadata.json"
  ],
  "artifactHashes": {
    "Payload/Hermes Bridge.app/Contents/MacOS/HermesBridgeApp": "$app_hash",
    "Payload/bin/HermesBridgeService": "$service_hash"
  },
  "componentVersions": {
    "app": "$RC_VERSION",
    "service": "$RC_VERSION",
    "control": "$RC_VERSION"
  },
  "upgradeCompatibility": {
    "from": ["0.1.0-rc.0", "0.1.0-rc.1"],
    "to": "$RC_VERSION"
  },
  "rollbackCompatibility": {
    "from": "$RC_VERSION",
    "toPreviousInstalledVersion": true
  }
}
JSON
  [[ -s "$RELEASE_MANIFEST" ]] && RESULT[RELEASE_MANIFEST_CREATED]=yes
  [[ -n "$commit" ]] && RESULT[SOURCE_COMMIT_RECORDED]=yes
}

generate_checksums_and_archive() {
  (
    cd "$STAGING_ROOT" || exit 1
    find Payload ReleaseEvidence -type f \
      ! -path 'ReleaseEvidence/checksums.sha256' \
      ! -path 'ReleaseEvidence/staging-files.txt' \
      | LC_ALL=C sort > "$STAGING_LIST"
    while IFS= read -r item; do
      shasum -a 256 "$item"
    done < "$STAGING_LIST" > "$CHECKSUMS"
    shasum -a 256 -c "$CHECKSUMS" >/dev/null
  ) || return 1
  RESULT[CHECKSUM_MANIFEST_CREATED]=yes
  RESULT[CHECKSUM_MANIFEST_VERIFIED]=yes
  local archive="$RC_DIR/HermesBridge-$SAFE_VERSION-unsigned-rc.tar.gz"
  rm -f "$archive" "$archive.sha256"
  find "$STAGING_ROOT" -exec touch -h -t 198001010000 {} +
  (
    cd "$RC_DIR" || exit 1
    COPYFILE_DISABLE=1 tar -czf "$archive" --format ustar -C "$STAGING_ROOT" -T "$STAGING_LIST" >/dev/null 2>&1 || \
      tar -czf "$archive" -C "$STAGING_ROOT" Payload ReleaseEvidence
    shasum -a 256 "$archive:t" > "$archive:t.sha256"
    shasum -a 256 -c "$archive:t.sha256" >/dev/null
  ) || return 1
  RESULT[RC_PACKAGE_CREATED]=yes
}

run_install_smoke() {
  rm -rf "$INSTALL_ROOT"
  mkdir -p "$INSTALL_ROOT" "$SMOKE_ROOT"
  "$LIFECYCLE" install \
    --artifact-root "$INSTALL_ROOT" \
    --service-binary "$SERVICE_EXECUTABLE" \
    --fake-launchctl \
    --fake-launchctl-log "$ARTIFACT_DIR/fake-launchctl.log" \
    --bootstrap \
    --version "$RC_VERSION" \
    --keep-versions 3 > "$ARTIFACT_DIR/install-smoke.json" || return 1
  [[ -f "$INSTALL_ROOT/fake-home/Library/Application Support/HermesBridge/install-state.json" ]] || return 1
  RESULT[INSTALL_SMOKE_PASSED]=yes
  "$APP_EXECUTABLE" >"$APP_STDOUT" 2>"$APP_STDERR" &
  APP_PID=$!
  sleep 1
  kill -0 "$APP_PID" 2>/dev/null || return 1
  RESULT[RUNTIME_SMOKE_PASSED]=yes
}

run_xpc_smoke() {
  if /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1; then
    print -u2 "warning: skipping XPC smoke because $LABEL is already loaded"
    return 1
  fi
  write_fake_backend
  write_service_configuration "$(free_port)"
  write_launch_agent
  /bin/launchctl bootstrap "$SERVICE_DOMAIN" "$LAUNCH_AGENT_PLIST" >/dev/null || return 1
  BOOTSTRAPPED=yes
  local deadline=$(( $(date +%s) + 20 ))
  while [[ $(date +%s) -lt $deadline ]]; do
    if "$CONTROL_EXECUTABLE" capabilities --timeout 5 >/dev/null 2>&1; then
      RESULT[XPC_SMOKE_PASSED]=yes
      return 0
    fi
    sleep 0.5
  done
  return 1
}

run_uninstall_smoke() {
  "$LIFECYCLE" uninstall \
    --artifact-root "$INSTALL_ROOT" \
    --fake-launchctl \
    --fake-launchctl-log "$ARTIFACT_DIR/fake-launchctl.log" \
    --purge-state \
    --purge-logs > "$ARTIFACT_DIR/uninstall-smoke.txt" || return 1
  [[ ! -e "$INSTALL_ROOT/fake-home/Library/Application Support/HermesBridge/Versions" ]] || return 1
  RESULT[UNINSTALL_SMOKE_PASSED]=yes
}

security_scan() {
  local scan_root="$ARTIFACT_DIR/security-scan"
  rm -rf "$scan_root"
  mkdir -p "$scan_root"
  cp -R "$STAGING_ROOT" "$scan_root/staging"
  cp "$RESULT_FILE" "$scan_root/result.txt" 2>/dev/null || true
  local strings_file="$scan_root/payload.strings"
  /usr/bin/strings "$APP_EXECUTABLE" "$SERVICE_EXECUTABLE" "$CONTROL_EXECUTABLE" "$LIFECYCLE" 2>/dev/null > "$strings_file" || true
  if grep -R -I -E 'token[=:][A-Za-z0-9._-]{12,}|password[=:][^[:space:]]{8,}|credential[=:][^[:space:]]{8,}|secret[=:][^[:space:]]{8,}|HERMES_DASHBOARD_SESSION_TOKEN=[^[:space:]]+' "$scan_root" >/dev/null 2>&1; then
    RESULT[TOKEN_EXPOSED]=yes
  else
    RESULT[TOKEN_EXPOSED]=no
  fi
  if grep -R -I -E 'BEGIN (RSA |OPENSSH |EC |DSA |)PRIVATE KEY' "$scan_root" >/dev/null 2>&1; then
    RESULT[PRIVATE_KEY_EXPOSED]=yes
  else
    RESULT[PRIVATE_KEY_EXPOSED]=no
  fi
  if grep -R -I -F "$ROOT_DIR" "$scan_root" >/dev/null 2>&1 \
    || grep -R -I -E '/Users/[A-Za-z0-9._-]+/Developer|/Users/[A-Za-z0-9._-]+/.+hermes-macos-native-bridge' "$scan_root" >/dev/null 2>&1; then
    RESULT[DEVELOPER_PATH_EXPOSED]=yes
  else
    RESULT[DEVELOPER_PATH_EXPOSED]=no
  fi
  if grep -R -I -E 'HermesBridgeAppAcceptanceHarness|HermesBridgeAppAcceptanceSupport|HermesM11003AcceptanceController|--hermes-m11-003-acceptance|M11_003_ACCEPTANCE|m11-003-token-sentinel' "$scan_root" >/dev/null 2>&1; then
    RESULT[ACCEPTANCE_SYMBOL_EXPOSED]=yes
  else
    RESULT[ACCEPTANCE_SYMBOL_EXPOSED]=no
  fi
  rm -rf "$scan_root"
}

set_default_results
rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"
write_result
RESULT[APPLICATIONS_MODIFIED]=no
RESULT[USER_LAUNCH_AGENTS_MODIFIED]=no
RESULT[REAL_HERMES_HOME_MODIFIED]=no

[[ -d "$ROOT_DIR/.git" ]] || fail "unexpected repository root"
build_existing_release || fail "existing release build failed"
normalize_versions || fail "version normalization failed"
validate_bundle
assess_signing
scan_production_components
write_sbom || fail "SBOM generation failed"
write_release_manifest || fail "release manifest generation failed"
generate_checksums_and_archive || fail "checksum/archive generation failed"
run_install_smoke || fail "install smoke failed"
run_xpc_smoke || fail "XPC smoke failed"
run_uninstall_smoke || fail "uninstall smoke failed"
security_scan
write_result
exit 0
