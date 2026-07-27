#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m11-003"
APP_NAME="Hermes Bridge.app"
APP_BUNDLE="$ARTIFACT_DIR/$APP_NAME"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/HermesBridgeApp"
SERVICE_EXECUTABLE="$APP_BUNDLE/Contents/Library/HermesBridge/HermesBridgeService"
RELEASE_DERIVED_DATA="$ARTIFACT_DIR/release-derived"
RELEASE_EXECUTABLE="$ROOT_DIR/.build/release/HermesBridgeApp"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
RUN_ROOT="$ARTIFACT_DIR/run"
CONFIG_DIR="$RUN_ROOT/HermesBridge"
CONFIG_FILE="$CONFIG_DIR/configuration.json"
LAUNCH_AGENT_PLIST="$RUN_ROOT/com.hermes.bridge.m11-003.plist"
STATE_FILE="$ARTIFACT_DIR/session-state.txt"
FIRST_EVIDENCE="$ARTIFACT_DIR/app-first.evidence"
SECOND_EVIDENCE="$ARTIFACT_DIR/app-second.evidence"
STOP_COUNT_FILE="$RUN_ROOT/stop-count.txt"
FAKE_BACKEND="$RUN_ROOT/fake-hermes.py"
SERVICE_STDOUT="$RUN_ROOT/service.stdout.log"
SERVICE_STDERR="$RUN_ROOT/service.stderr.log"
APP_FIRST_STDOUT="$RUN_ROOT/app-first.stdout.log"
APP_FIRST_STDERR="$RUN_ROOT/app-first.stderr.log"
APP_SECOND_STDOUT="$RUN_ROOT/app-second.stdout.log"
APP_SECOND_STDERR="$RUN_ROOT/app-second.stderr.log"
LABEL="com.hermes.bridge"
MACH_SERVICE="com.hermes.bridge.xpc"
BOOTSTRAPPED="no"
APP_PID=""
SERVICE_DOMAIN="gui/$(id -u)"

typeset -A RESULT

set_default_results() {
  RESULT=(
    APP_BUNDLE_BUILT no
    APP_EXECUTABLE_PRESENT no
    INFO_PLIST_VALID no
    BUNDLE_IDENTIFIERS_VALID no
    REQUIRED_COMPONENTS_EMBEDDED no
    XPC_PROTOCOL_1_7 no
    APP_OWNS_CONCRETE_RUNTIME yes
    SERVICE_OWNS_RUNTIME no
    APP_PROCESS_STARTED no
    XPC_CONNECTION_SUCCEEDED no
    DASHBOARD_ROUTE_AVAILABLE no
    LOGS_ROUTE_AVAILABLE no
    SETTINGS_ROUTE_AVAILABLE no
    DIAGNOSTICS_ROUTE_AVAILABLE no
    SESSION_STARTED no
    EVENT_RECEIVED no
    RUNTIME_SURVIVED_APP_EXIT no
    APP_RELAUNCHED no
    CLIENT_RECONNECTED no
    EXPLICIT_STOP_FORWARDED_ONCE no
    SESSION_STOPPED no
    DEVELOPER_PATH_EXPOSED yes
    TOKEN_EXPOSED yes
    PRIVATE_KEY_EXPOSED yes
    PID_EXPOSED yes
    SIGNING_STATE invalid
    APPLICATIONS_MODIFIED yes
    PERMANENT_INSTALLATION yes
    RESIDUAL_PROCESS yes
    ACCEPTANCE_SUPPORT_ISOLATED no
    RELEASE_CONTAINS_ACCEPTANCE_CONTROLLER yes
    RELEASE_ACCEPTS_TEST_LAUNCH_ARGUMENTS yes
    RELEASE_CONTAINS_ACCEPTANCE_SENTINELS yes
    M11_003_RESULT FAIL
  )
}

yes_if() {
  if "$@"; then
    print -r -- "yes"
  else
    print -r -- "no"
  fi
}

write_result() {
  local pass="yes"
  local key
  for key in \
    APP_BUNDLE_BUILT APP_EXECUTABLE_PRESENT INFO_PLIST_VALID BUNDLE_IDENTIFIERS_VALID \
    REQUIRED_COMPONENTS_EMBEDDED XPC_PROTOCOL_1_7 SERVICE_OWNS_RUNTIME APP_PROCESS_STARTED \
    XPC_CONNECTION_SUCCEEDED DASHBOARD_ROUTE_AVAILABLE LOGS_ROUTE_AVAILABLE \
    SETTINGS_ROUTE_AVAILABLE DIAGNOSTICS_ROUTE_AVAILABLE SESSION_STARTED EVENT_RECEIVED \
    RUNTIME_SURVIVED_APP_EXIT APP_RELAUNCHED CLIENT_RECONNECTED \
    EXPLICIT_STOP_FORWARDED_ONCE SESSION_STOPPED; do
    [[ "${RESULT[$key]}" == "yes" ]] || pass="no"
  done
  for key in \
    APP_OWNS_CONCRETE_RUNTIME DEVELOPER_PATH_EXPOSED TOKEN_EXPOSED PRIVATE_KEY_EXPOSED \
    PID_EXPOSED APPLICATIONS_MODIFIED PERMANENT_INSTALLATION RESIDUAL_PROCESS; do
    [[ "${RESULT[$key]}" == "no" ]] || pass="no"
  done
  [[ "${RESULT[ACCEPTANCE_SUPPORT_ISOLATED]}" == "yes" ]] || pass="no"
  [[ "${RESULT[RELEASE_CONTAINS_ACCEPTANCE_CONTROLLER]}" == "no" ]] || pass="no"
  [[ "${RESULT[RELEASE_ACCEPTS_TEST_LAUNCH_ARGUMENTS]}" == "no" ]] || pass="no"
  [[ "${RESULT[RELEASE_CONTAINS_ACCEPTANCE_SENTINELS]}" == "no" ]] || pass="no"
  [[ "${RESULT[SIGNING_STATE]}" == "valid" || "${RESULT[SIGNING_STATE]}" == "adhoc" || "${RESULT[SIGNING_STATE]}" == "unsigned" ]] || pass="no"
  RESULT[M11_003_RESULT]=$([[ "$pass" == "yes" ]] && print -r -- PASS || print -r -- FAIL)

  mkdir -p "$ARTIFACT_DIR"
  {
    print -r -- "APP_BUNDLE_BUILT=${RESULT[APP_BUNDLE_BUILT]}"
    print -r -- "APP_EXECUTABLE_PRESENT=${RESULT[APP_EXECUTABLE_PRESENT]}"
    print -r -- "INFO_PLIST_VALID=${RESULT[INFO_PLIST_VALID]}"
    print -r -- "BUNDLE_IDENTIFIERS_VALID=${RESULT[BUNDLE_IDENTIFIERS_VALID]}"
    print -r -- "REQUIRED_COMPONENTS_EMBEDDED=${RESULT[REQUIRED_COMPONENTS_EMBEDDED]}"
    print -r -- "XPC_PROTOCOL_1_7=${RESULT[XPC_PROTOCOL_1_7]}"
    print -r -- "APP_OWNS_CONCRETE_RUNTIME=${RESULT[APP_OWNS_CONCRETE_RUNTIME]}"
    print -r -- "SERVICE_OWNS_RUNTIME=${RESULT[SERVICE_OWNS_RUNTIME]}"
    print -r -- "APP_PROCESS_STARTED=${RESULT[APP_PROCESS_STARTED]}"
    print -r -- "XPC_CONNECTION_SUCCEEDED=${RESULT[XPC_CONNECTION_SUCCEEDED]}"
    print -r -- "DASHBOARD_ROUTE_AVAILABLE=${RESULT[DASHBOARD_ROUTE_AVAILABLE]}"
    print -r -- "LOGS_ROUTE_AVAILABLE=${RESULT[LOGS_ROUTE_AVAILABLE]}"
    print -r -- "SETTINGS_ROUTE_AVAILABLE=${RESULT[SETTINGS_ROUTE_AVAILABLE]}"
    print -r -- "DIAGNOSTICS_ROUTE_AVAILABLE=${RESULT[DIAGNOSTICS_ROUTE_AVAILABLE]}"
    print -r -- "SESSION_STARTED=${RESULT[SESSION_STARTED]}"
    print -r -- "EVENT_RECEIVED=${RESULT[EVENT_RECEIVED]}"
    print -r -- "RUNTIME_SURVIVED_APP_EXIT=${RESULT[RUNTIME_SURVIVED_APP_EXIT]}"
    print -r -- "APP_RELAUNCHED=${RESULT[APP_RELAUNCHED]}"
    print -r -- "CLIENT_RECONNECTED=${RESULT[CLIENT_RECONNECTED]}"
    print -r -- "EXPLICIT_STOP_FORWARDED_ONCE=${RESULT[EXPLICIT_STOP_FORWARDED_ONCE]}"
    print -r -- "SESSION_STOPPED=${RESULT[SESSION_STOPPED]}"
    print -r -- "DEVELOPER_PATH_EXPOSED=${RESULT[DEVELOPER_PATH_EXPOSED]}"
    print -r -- "TOKEN_EXPOSED=${RESULT[TOKEN_EXPOSED]}"
    print -r -- "PRIVATE_KEY_EXPOSED=${RESULT[PRIVATE_KEY_EXPOSED]}"
    print -r -- "PID_EXPOSED=${RESULT[PID_EXPOSED]}"
    print -r -- "SIGNING_STATE=${RESULT[SIGNING_STATE]}"
    print -r -- "APPLICATIONS_MODIFIED=${RESULT[APPLICATIONS_MODIFIED]}"
    print -r -- "PERMANENT_INSTALLATION=${RESULT[PERMANENT_INSTALLATION]}"
    print -r -- "RESIDUAL_PROCESS=${RESULT[RESIDUAL_PROCESS]}"
    print -r -- "ACCEPTANCE_SUPPORT_ISOLATED=${RESULT[ACCEPTANCE_SUPPORT_ISOLATED]}"
    print -r -- "RELEASE_CONTAINS_ACCEPTANCE_CONTROLLER=${RESULT[RELEASE_CONTAINS_ACCEPTANCE_CONTROLLER]}"
    print -r -- "RELEASE_ACCEPTS_TEST_LAUNCH_ARGUMENTS=${RESULT[RELEASE_ACCEPTS_TEST_LAUNCH_ARGUMENTS]}"
    print -r -- "RELEASE_CONTAINS_ACCEPTANCE_SENTINELS=${RESULT[RELEASE_CONTAINS_ACCEPTANCE_SENTINELS]}"
    print -r -- "M11_003_RESULT=${RESULT[M11_003_RESULT]}"
  } > "$RESULT_FILE"
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
  if [[ -n "$(/usr/bin/pgrep -fl "$RUN_ROOT" 2>/dev/null || true)" ]]; then
    residual="yes"
  fi
  RESULT[RESIDUAL_PROCESS]="$residual"
  write_result
}

trap cleanup EXIT

fail() {
  print -u2 "error: $*"
  exit 1
}

result_value() {
  local file="$1"
  local key="$2"
  awk -F= -v k="$key" '$1 == k { print $2; exit }' "$file" 2>/dev/null
}

wait_for_file_key() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local deadline=$(( $(date +%s) + 20 ))
  while [[ $(date +%s) -lt $deadline ]]; do
    if [[ "$(result_value "$file" "$key")" == "$expected" ]]; then
      return 0
    fi
    sleep 0.2
  done
  return 1
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
  cat > "$FAKE_BACKEND" <<PY
#!/usr/bin/python3
import argparse, asyncio, base64, hashlib, json, os, signal, struct, sys
from urllib.parse import parse_qs, urlparse
if sys.argv[1:] == ["--version"]:
    print("Hermes Agent v0.18.2")
    print("Install Method: m11-003-fixture")
    sys.exit(0)
parser = argparse.ArgumentParser()
parser.add_argument("--safe-mode", action="store_true")
parser.add_argument("serve")
parser.add_argument("--host", required=True)
parser.add_argument("--port", required=True, type=int)
parser.add_argument("--skip-build", action="store_true")
parser.add_argument("--isolated", action="store_true")
args = parser.parse_args()
token = os.environ.get("HERMES_DASHBOARD_SESSION_TOKEN", "")
stop_file = "$STOP_COUNT_FILE"
async def read_req(r):
    data = await r.readuntil(b"\\r\\n\\r\\n")
    lines = data.decode("ascii", "replace").split("\\r\\n")
    method, target, _ = lines[0].split(" ", 2)
    headers = {}
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.lower()] = v.strip()
    return method, target, headers
async def http(w, status, body=b""):
    reason = {200:"OK",403:"Forbidden",404:"Not Found"}.get(status, "Error")
    w.write((f"HTTP/1.1 {status} {reason}\\r\\nContent-Length: {len(body)}\\r\\nConnection: close\\r\\n\\r\\n").encode() + body)
    await w.drain()
    w.close()
    await w.wait_closed()
async def frame(r):
    h = await r.readexactly(2)
    opcode = h[0] & 0x0f
    if opcode == 8:
        return None
    length = h[1] & 0x7f
    masked = h[1] & 0x80
    if length == 126:
        length = struct.unpack("!H", await r.readexactly(2))[0]
    elif length == 127:
        length = struct.unpack("!Q", await r.readexactly(8))[0]
    mask = await r.readexactly(4) if masked else b"\\0\\0\\0\\0"
    data = await r.readexactly(length)
    if masked:
        data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
    return data.decode()
async def send(w, obj):
    data = json.dumps(obj).encode()
    header = bytearray([0x81])
    if len(data) < 126:
        header.append(len(data))
    else:
        header.extend([126])
        header.extend(struct.pack("!H", len(data)))
    w.write(bytes(header) + data)
    await w.drain()
async def ws(r, w, target, headers):
    if parse_qs(urlparse(target).query).get("token", [""])[0] != token:
        return await http(w, 403, b"forbidden")
    key = headers.get("sec-websocket-key", "")
    accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    w.write(("HTTP/1.1 101 Switching Protocols\\r\\nUpgrade: websocket\\r\\nConnection: Upgrade\\r\\nSec-WebSocket-Accept: " + accept + "\\r\\n\\r\\n").encode())
    await w.drain()
    await send(w, {"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready"}})
    while True:
        try:
            raw = await frame(r)
            if raw is None:
                break
            req = json.loads(raw)
        except Exception:
            break
        method = req.get("method")
        rid = req.get("id")
        if method == "session.create":
            resp = {"jsonrpc":"2.0","id":rid,"result":{"session_id":"m11-session","stored_session_id":"stored-m11","message_count":0,"info":{"desktop_contract":3}}}
        elif method == "session.status":
            resp = {"jsonrpc":"2.0","id":rid,"result":{"output":"idle"}}
        elif method == "session.interrupt":
            resp = {"jsonrpc":"2.0","id":rid,"result":{"status":"interrupted"}}
        elif method == "prompt.submit":
            resp = {"jsonrpc":"2.0","id":rid,"result":{"status":"streaming"}}
        elif method == "approval.respond":
            resp = {"jsonrpc":"2.0","id":rid,"result":{"resolved":True}}
        else:
            resp = {"jsonrpc":"2.0","id":rid,"error":{"code":-32601,"message":"unknown"}}
        await send(w, resp)
    w.close()
async def handle(r, w):
    try:
        method, target, headers = await read_req(r)
        path = urlparse(target).path
        if method == "GET" and path == "/api/status":
            body = json.dumps({"version":"m11-fixture","auth_required":True,"auth_mode":"loopback_token","desktop_contract":3,"gateway_running":True,"gateway_state":"running"}).encode()
            return await http(w, 200, body)
        if method == "GET" and path == "/api/ws":
            return await ws(r, w, target, headers)
        return await http(w, 404, b"not found")
    except Exception:
        try:
            w.close()
            await w.wait_closed()
        except Exception:
            pass
async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", args.port)
    print(f"HERMES_BACKEND_READY port={args.port}", flush=True)
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    recorded = {"value": False}
    def on_term(signum, frame):
        if not recorded["value"]:
            recorded["value"] = True
            with open(stop_file, "a") as f:
                f.write("stop\\n")
        loop.call_soon_threadsafe(stop.set)
    signal.signal(signal.SIGTERM, on_term)
    signal.signal(signal.SIGINT, on_term)
    async with server:
        await stop.wait()
asyncio.run(main())
PY
  chmod 700 "$FAKE_BACKEND"
}

write_service_configuration() {
  local port="$1"
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<JSON
{
  "schemaVersion": 1,
  "machServiceName": "$MACH_SERVICE",
  "runtimeRoot": "file://$RUN_ROOT/Runtime",
  "requestStateRoot": "file://$RUN_ROOT/RequestState",
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
}

build_bundle() {
  rm -rf "$ARTIFACT_DIR"
  mkdir -p "$APP_BUNDLE/Contents/MacOS" \
    "$APP_BUNDLE/Contents/Frameworks" \
    "$APP_BUNDLE/Contents/XPCServices" \
    "$APP_BUNDLE/Contents/Library/HermesBridge" \
    "$APP_BUNDLE/Contents/Library/LaunchAgents" \
    "$APP_BUNDLE/Contents/Resources" \
    "$RUN_ROOT"

  cd "$ROOT_DIR" || exit 1
  xcodebuild \
    -project Packaging/HermesBridgeApp/HermesBridgeApp.xcodeproj \
    -scheme HermesBridgeApp \
    -configuration Debug \
    -derivedDataPath "$ARTIFACT_DIR/DerivedData" \
    build >/dev/null || return 1
  swift build --product HermesBridgeAppAcceptanceHarness >/dev/null || return 1
  swift build --product HermesBridgeService >/dev/null || return 1

  cp "$ROOT_DIR/.build/debug/HermesBridgeAppAcceptanceHarness" "$APP_EXECUTABLE" || return 1
  cp "$ROOT_DIR/.build/debug/HermesBridgeService" "$SERVICE_EXECUTABLE" || return 1
  cp "$ROOT_DIR/Packaging/HermesBridgeApp/Info.plist" "$APP_BUNDLE/Contents/Info.plist" || return 1
  cp "$ROOT_DIR/Packaging/LaunchAgent/com.hermes.bridge.plist.template" \
    "$APP_BUNDLE/Contents/Library/LaunchAgents/com.hermes.bridge.plist.template" || return 1
  chmod 755 "$APP_EXECUTABLE" "$SERVICE_EXECUTABLE"
}

validate_bundle() {
  [[ -d "$APP_BUNDLE" ]] && RESULT[APP_BUNDLE_BUILT]=yes
  [[ -x "$APP_EXECUTABLE" ]] && RESULT[APP_EXECUTABLE_PRESENT]=yes
  if /usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null 2>&1; then
    RESULT[INFO_PLIST_VALID]=yes
  fi
  local bundle_id min_version executable
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  min_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$bundle_id" == "com.hermes.bridge.app" && "$min_version" == "13.0" && "$executable" == "HermesBridgeApp" ]]; then
    RESULT[BUNDLE_IDENTIFIERS_VALID]=yes
  fi
  if [[ -d "$APP_BUNDLE/Contents/MacOS" \
    && -f "$APP_BUNDLE/Contents/Info.plist" \
    && -d "$APP_BUNDLE/Contents/Frameworks" \
    && -d "$APP_BUNDLE/Contents/XPCServices" \
    && -d "$APP_BUNDLE/Contents/Library" \
    && -x "$SERVICE_EXECUTABLE" \
    && -f "$APP_BUNDLE/Contents/Library/LaunchAgents/com.hermes.bridge.plist.template" ]]; then
    RESULT[REQUIRED_COMPONENTS_EMBEDDED]=yes
  fi
}

assess_signing() {
  if codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
    if codesign -dv "$APP_BUNDLE" 2>&1 | grep -q "Signature=adhoc"; then
      RESULT[SIGNING_STATE]=adhoc
    else
      RESULT[SIGNING_STATE]=valid
    fi
  elif [[ ! -d "$APP_BUNDLE/Contents/_CodeSignature" ]]; then
    RESULT[SIGNING_STATE]=unsigned
  else
    if codesign -dv "$APP_BUNDLE" >/dev/null 2>&1; then
      RESULT[SIGNING_STATE]=invalid
    else
      RESULT[SIGNING_STATE]=unsigned
    fi
  fi
  spctl --assess --type execute "$APP_BUNDLE" >/dev/null 2>&1 || true
}

scan_runtime_ownership() {
  if ! rg -n \
    'HermesRuntimeSessionManager\(|HermesRuntimeEventBus\(|HermesRuntimeCommandAPI\(|HermesProcessSupervisor\(|HermesBackendAdapter\(|HermesProtocolClient\(' \
    "$ROOT_DIR/Sources/HermesBridgeApp" >/dev/null; then
    RESULT[APP_OWNS_CONCRETE_RUNTIME]=no
  fi
}

validate_acceptance_isolation() {
  if [[ -f "$ROOT_DIR/Sources/HermesBridgeAppAcceptanceSupport/HermesM11003AcceptanceController.swift" ]] \
    && [[ ! -f "$ROOT_DIR/Sources/HermesBridgeApp/HermesM11003AcceptanceController.swift" ]] \
    && ! rg -n 'HermesM11003AcceptanceController|HermesBridgeAppAcceptanceSupport|--hermes-m11-003-acceptance' \
      "$ROOT_DIR/Sources/HermesBridgeApp" >/dev/null \
    && rg -n 'name: "HermesBridgeAppAcceptanceSupport"|name: "HermesBridgeAppAcceptanceHarness"|HERMES_M11_003_ACCEPTANCE_SUPPORT' \
      "$ROOT_DIR/Package.swift" >/dev/null; then
    RESULT[ACCEPTANCE_SUPPORT_ISOLATED]=yes
  fi
}

validate_release_exclusion() {
  rm -rf "$RELEASE_DERIVED_DATA"
  xcodebuild \
    -project Packaging/HermesBridgeApp/HermesBridgeApp.xcodeproj \
    -scheme HermesBridgeApp \
    -configuration Release \
    -derivedDataPath "$RELEASE_DERIVED_DATA" \
    build >/dev/null || return 1

  [[ -x "$RELEASE_EXECUTABLE" ]] || return 1

  local release_strings="$ARTIFACT_DIR/release-executable.strings"
  local release_symbols="$ARTIFACT_DIR/release-executable.symbols"
  /usr/bin/strings "$RELEASE_EXECUTABLE" > "$release_strings"
  /usr/bin/nm -a "$RELEASE_EXECUTABLE" > "$release_symbols" 2>/dev/null || true

  if ! grep -E 'HermesM11003AcceptanceController|HermesBridgeAppAcceptanceSupport' \
    "$release_strings" "$release_symbols" >/dev/null 2>&1; then
    RESULT[RELEASE_CONTAINS_ACCEPTANCE_CONTROLLER]=no
  fi
  if ! grep -E -- '--hermes-m11-003-acceptance|start-and-hold|reconnect-and-stop|M11_003' \
    "$release_strings" "$release_symbols" >/dev/null 2>&1; then
    RESULT[RELEASE_ACCEPTS_TEST_LAUNCH_ARGUMENTS]=no
  fi
  if ! grep -E 'm11-003-token-sentinel|HERMES_M11_003_ACCEPTANCE_SUPPORT|M11_003_ACCEPTANCE|ACCEPTANCE_SUPPORT' \
    "$release_strings" "$release_symbols" >/dev/null 2>&1; then
    RESULT[RELEASE_CONTAINS_ACCEPTANCE_SENTINELS]=no
  fi
}

launch_app() {
  local mode="$1"
  local evidence="$2"
  local stdout="$3"
  local stderr="$4"
  "$APP_EXECUTABLE" --hermes-m11-003-acceptance "$mode" "$STATE_FILE" "$evidence" \
    >"$stdout" 2>"$stderr" &
  APP_PID=$!
  RESULT[APP_PROCESS_STARTED]=yes
  if [[ "$mode" == "reconnect-and-stop" ]]; then
    return 0
  fi
  sleep 1
  kill -0 "$APP_PID" 2>/dev/null && return 0
  return 1
}

terminate_app_and_wait() {
  [[ -n "$APP_PID" ]] || return 0
  if kill -0 "$APP_PID" 2>/dev/null; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  APP_PID=""
}

security_scan() {
  local scan_root="$ARTIFACT_DIR/security-scan"
  rm -rf "$scan_root"
  mkdir -p "$scan_root"
  cp -R "$APP_BUNDLE" "$scan_root/"
  cp "$RESULT_FILE" "$FIRST_EVIDENCE" "$SECOND_EVIDENCE" "$STATE_FILE" "$scan_root/" 2>/dev/null || true

  if grep -R -I -E 'm11-003-token-sentinel|password[=:]|credential[=:]|secret[=:]' "$scan_root" >/dev/null 2>&1; then
    RESULT[TOKEN_EXPOSED]=yes
  else
    RESULT[TOKEN_EXPOSED]=no
  fi
  if grep -R -I -E 'BEGIN (RSA |OPENSSH |EC |DSA |)PRIVATE KEY' "$scan_root" >/dev/null 2>&1; then
    RESULT[PRIVATE_KEY_EXPOSED]=yes
  else
    RESULT[PRIVATE_KEY_EXPOSED]=no
  fi
  if grep -R -I -F "/Users/jerrysmith" "$scan_root" >/dev/null 2>&1 \
    || grep -R -I -F "$ROOT_DIR" "$scan_root" >/dev/null 2>&1; then
    RESULT[DEVELOPER_PATH_EXPOSED]=yes
  else
    RESULT[DEVELOPER_PATH_EXPOSED]=no
  fi
  if grep -R -I -E '(^|[^A-Za-z])pid[ =:][0-9]+' "$scan_root" >/dev/null 2>&1; then
    RESULT[PID_EXPOSED]=yes
  else
    RESULT[PID_EXPOSED]=no
  fi
  rm -rf "$scan_root"
}

set_default_results
mkdir -p "$ARTIFACT_DIR"
write_result

[[ "$ROOT_DIR" != "/Applications"* ]] || fail "repository root is under /Applications"
RESULT[APPLICATIONS_MODIFIED]=no
RESULT[PERMANENT_INSTALLATION]=no

if /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1; then
  fail "refusing to touch existing launchd label $SERVICE_DOMAIN/$LABEL"
fi

build_bundle || fail "bundle build failed"
validate_bundle
assess_signing
scan_runtime_ownership
validate_acceptance_isolation
validate_release_exclusion || fail "release exclusion validation failed"
write_fake_backend
write_service_configuration "$(free_port)"
write_launch_agent
/usr/bin/plutil -lint "$LAUNCH_AGENT_PLIST" >/dev/null || fail "invalid temporary LaunchAgent plist"

/bin/launchctl bootstrap "$SERVICE_DOMAIN" "$LAUNCH_AGENT_PLIST" >/dev/null || fail "temporary service bootstrap failed"
BOOTSTRAPPED=yes

launch_app "start-and-hold" "$FIRST_EVIDENCE" "$APP_FIRST_STDOUT" "$APP_FIRST_STDERR" \
  || fail "first app launch failed"
wait_for_file_key "$FIRST_EVIDENCE" "SESSION_STARTED" "yes" || fail "first app evidence timed out"
RESULT[XPC_CONNECTION_SUCCEEDED]="$(result_value "$FIRST_EVIDENCE" XPC_CONNECTION_SUCCEEDED)"
RESULT[XPC_PROTOCOL_1_7]="$(result_value "$FIRST_EVIDENCE" XPC_PROTOCOL_1_7)"
RESULT[SERVICE_OWNS_RUNTIME]="$(result_value "$FIRST_EVIDENCE" SERVICE_OWNS_RUNTIME)"
RESULT[DASHBOARD_ROUTE_AVAILABLE]="$(result_value "$FIRST_EVIDENCE" DASHBOARD_ROUTE_AVAILABLE)"
RESULT[LOGS_ROUTE_AVAILABLE]="$(result_value "$FIRST_EVIDENCE" LOGS_ROUTE_AVAILABLE)"
RESULT[SETTINGS_ROUTE_AVAILABLE]="$(result_value "$FIRST_EVIDENCE" SETTINGS_ROUTE_AVAILABLE)"
RESULT[DIAGNOSTICS_ROUTE_AVAILABLE]="$(result_value "$FIRST_EVIDENCE" DIAGNOSTICS_ROUTE_AVAILABLE)"
RESULT[SESSION_STARTED]="$(result_value "$FIRST_EVIDENCE" SESSION_STARTED)"
RESULT[EVENT_RECEIVED]="$(result_value "$FIRST_EVIDENCE" EVENT_RECEIVED)"

terminate_app_and_wait

launch_app "reconnect-and-stop" "$SECOND_EVIDENCE" "$APP_SECOND_STDOUT" "$APP_SECOND_STDERR" \
  || fail "second app launch failed"
RESULT[APP_RELAUNCHED]=yes
wait_for_file_key "$SECOND_EVIDENCE" "SESSION_STOPPED" "yes" || fail "second app evidence timed out"
RESULT[CLIENT_RECONNECTED]="$(result_value "$SECOND_EVIDENCE" CLIENT_RECONNECTED)"
if [[ "${RESULT[CLIENT_RECONNECTED]}" == "yes" ]]; then
  RESULT[RUNTIME_SURVIVED_APP_EXIT]=yes
fi
RESULT[SESSION_STOPPED]="$(result_value "$SECOND_EVIDENCE" SESSION_STOPPED)"
terminate_app_and_wait

if [[ -f "$STOP_COUNT_FILE" && "$(wc -l < "$STOP_COUNT_FILE" | tr -d ' ')" == "1" ]]; then
  RESULT[EXPLICIT_STOP_FORWARDED_ONCE]=yes
elif [[ "$(result_value "$SECOND_EVIDENCE" EXPLICIT_STOP_FORWARDED_COUNT)" == "1" \
  && "${RESULT[SESSION_STOPPED]}" == "yes" ]]; then
  RESULT[EXPLICIT_STOP_FORWARDED_ONCE]=yes
fi

write_result
security_scan
exit 0
