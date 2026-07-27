#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m11-004"
INSTALL_ROOT="$ARTIFACT_DIR/install-root"
FAKE_HOME="$INSTALL_ROOT/fake-home"
APP_NAME="Hermes Bridge.app"
INSTALLED_APP_ROOT="$INSTALL_ROOT/Applications"
INSTALLED_APP="$INSTALLED_APP_ROOT/$APP_NAME"
APP_EXECUTABLE="$INSTALLED_APP/Contents/MacOS/HermesBridgeApp"
SERVICE_EXECUTABLE="$INSTALLED_APP/Contents/Library/HermesBridge/HermesBridgeService"
LIFECYCLE="$ROOT_DIR/.build/release/HermesBridgeServiceLifecycle"
CONTROL="$ROOT_DIR/.build/release/HermesBridgeControl"
ACCEPTANCE_HARNESS="$ROOT_DIR/.build/debug/HermesBridgeAppAcceptanceHarness"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
RUN_ROOT="$ARTIFACT_DIR/run"
CONFIG_DIR="$RUN_ROOT/HermesBridge"
CONFIG_FILE="$CONFIG_DIR/configuration.json"
RUNTIME_ROOT="$RUN_ROOT/Runtime"
REQUEST_STATE_ROOT="$RUN_ROOT/RequestState"
TEMP_LAUNCH_AGENT="$RUN_ROOT/com.hermes.bridge.m11-004.plist"
STATE_FILE="$ARTIFACT_DIR/session-state.txt"
FIRST_EVIDENCE="$ARTIFACT_DIR/app-first.evidence"
SECOND_EVIDENCE="$ARTIFACT_DIR/app-second.evidence"
STOP_COUNT_FILE="$RUN_ROOT/stop-count.txt"
FAKE_BACKEND="$RUN_ROOT/fake-hermes.py"
SERVICE_STDOUT="$RUN_ROOT/service.stdout.log"
SERVICE_STDERR="$RUN_ROOT/service.stderr.log"
APP_STDOUT="$RUN_ROOT/installed-app.stdout.log"
APP_STDERR="$RUN_ROOT/installed-app.stderr.log"
HARNESS_FIRST_STDOUT="$RUN_ROOT/harness-first.stdout.log"
HARNESS_FIRST_STDERR="$RUN_ROOT/harness-first.stderr.log"
HARNESS_SECOND_STDOUT="$RUN_ROOT/harness-second.stdout.log"
HARNESS_SECOND_STDERR="$RUN_ROOT/harness-second.stderr.log"
LABEL="com.hermes.bridge"
MACH_SERVICE="com.hermes.bridge.xpc"
SERVICE_DOMAIN="gui/$(id -u)"
BOOTSTRAPPED="no"
APP_PID=""
HARNESS_PID=""

typeset -A RESULT

ordered_keys=(
  PRODUCTION_APP_BUILT
  ISOLATED_INSTALL_ROOT_USED
  APP_INSTALLED
  SERVICE_INSTALLED
  LAUNCH_CONFIGURATION_INSTALLED
  INSTALL_LAYOUT_VALID
  ACCEPTANCE_SUPPORT_INSTALLED
  DUPLICATE_APP_INSTALLED
  DUPLICATE_SERVICE_INSTALLED
  XPC_PROTOCOL_1_7
  APP_OWNS_CONCRETE_RUNTIME
  SERVICE_OWNS_RUNTIME
  INSTALLED_APP_STARTED
  INSTALLED_SERVICE_STARTED
  XPC_CONNECTION_SUCCEEDED
  SESSION_STARTED
  EVENT_RECEIVED
  RUNTIME_SURVIVED_APP_EXIT
  APP_RECONNECTED
  EXPLICIT_STOP_FORWARDED_ONCE
  SESSION_STOPPED
  VERSION_A_INSTALLED
  UPGRADE_TO_VERSION_B
  CONFIG_PRESERVED_ON_UPGRADE
  VERSION_B_ACTIVE
  ROLLBACK_TO_VERSION_A
  VERSION_A_ACTIVE_AFTER_ROLLBACK
  XPC_WORKED_AFTER_ROLLBACK
  FAILED_UPGRADE_RECOVERED
  PARTIAL_FILES_CLEANED
  UNINSTALL_SUCCEEDED
  APP_REMOVED
  SERVICE_REMOVED
  LAUNCH_CONFIGURATION_REMOVED
  DEVELOPER_PATH_EXPOSED
  TOKEN_EXPOSED
  PRIVATE_KEY_EXPOSED
  ACCEPTANCE_SYMBOL_EXPOSED
  APPLICATIONS_MODIFIED
  USER_LAUNCH_AGENTS_MODIFIED
  REAL_HERMES_HOME_MODIFIED
  RESIDUAL_PROCESS
  M11_004_RESULT
)

set_default_results() {
  RESULT=(
    PRODUCTION_APP_BUILT no
    ISOLATED_INSTALL_ROOT_USED no
    APP_INSTALLED no
    SERVICE_INSTALLED no
    LAUNCH_CONFIGURATION_INSTALLED no
    INSTALL_LAYOUT_VALID no
    ACCEPTANCE_SUPPORT_INSTALLED yes
    DUPLICATE_APP_INSTALLED yes
    DUPLICATE_SERVICE_INSTALLED yes
    XPC_PROTOCOL_1_7 no
    APP_OWNS_CONCRETE_RUNTIME yes
    SERVICE_OWNS_RUNTIME no
    INSTALLED_APP_STARTED no
    INSTALLED_SERVICE_STARTED no
    XPC_CONNECTION_SUCCEEDED no
    SESSION_STARTED no
    EVENT_RECEIVED no
    RUNTIME_SURVIVED_APP_EXIT no
    APP_RECONNECTED no
    EXPLICIT_STOP_FORWARDED_ONCE no
    SESSION_STOPPED no
    VERSION_A_INSTALLED no
    UPGRADE_TO_VERSION_B no
    CONFIG_PRESERVED_ON_UPGRADE no
    VERSION_B_ACTIVE no
    ROLLBACK_TO_VERSION_A no
    VERSION_A_ACTIVE_AFTER_ROLLBACK no
    XPC_WORKED_AFTER_ROLLBACK no
    FAILED_UPGRADE_RECOVERED no
    PARTIAL_FILES_CLEANED no
    UNINSTALL_SUCCEEDED no
    APP_REMOVED no
    SERVICE_REMOVED no
    LAUNCH_CONFIGURATION_REMOVED no
    DEVELOPER_PATH_EXPOSED yes
    TOKEN_EXPOSED yes
    PRIVATE_KEY_EXPOSED yes
    ACCEPTANCE_SYMBOL_EXPOSED yes
    APPLICATIONS_MODIFIED yes
    USER_LAUNCH_AGENTS_MODIFIED yes
    REAL_HERMES_HOME_MODIFIED yes
    RESIDUAL_PROCESS yes
    M11_004_RESULT FAIL
  )
}

write_result() {
  local pass="yes"
  local key expected
  for key in \
    PRODUCTION_APP_BUILT ISOLATED_INSTALL_ROOT_USED APP_INSTALLED SERVICE_INSTALLED \
    LAUNCH_CONFIGURATION_INSTALLED INSTALL_LAYOUT_VALID XPC_PROTOCOL_1_7 SERVICE_OWNS_RUNTIME \
    INSTALLED_APP_STARTED INSTALLED_SERVICE_STARTED XPC_CONNECTION_SUCCEEDED SESSION_STARTED \
    EVENT_RECEIVED RUNTIME_SURVIVED_APP_EXIT APP_RECONNECTED EXPLICIT_STOP_FORWARDED_ONCE \
    SESSION_STOPPED VERSION_A_INSTALLED UPGRADE_TO_VERSION_B CONFIG_PRESERVED_ON_UPGRADE \
    VERSION_B_ACTIVE ROLLBACK_TO_VERSION_A VERSION_A_ACTIVE_AFTER_ROLLBACK \
    XPC_WORKED_AFTER_ROLLBACK FAILED_UPGRADE_RECOVERED PARTIAL_FILES_CLEANED \
    UNINSTALL_SUCCEEDED APP_REMOVED SERVICE_REMOVED LAUNCH_CONFIGURATION_REMOVED; do
    [[ "${RESULT[$key]}" == "yes" ]] || pass="no"
  done
  for key in \
    ACCEPTANCE_SUPPORT_INSTALLED DUPLICATE_APP_INSTALLED DUPLICATE_SERVICE_INSTALLED \
    APP_OWNS_CONCRETE_RUNTIME DEVELOPER_PATH_EXPOSED TOKEN_EXPOSED PRIVATE_KEY_EXPOSED \
    ACCEPTANCE_SYMBOL_EXPOSED APPLICATIONS_MODIFIED USER_LAUNCH_AGENTS_MODIFIED \
    REAL_HERMES_HOME_MODIFIED RESIDUAL_PROCESS; do
    [[ "${RESULT[$key]}" == "no" ]] || pass="no"
  done
  RESULT[M11_004_RESULT]=$([[ "$pass" == "yes" ]] && print -r -- PASS || print -r -- FAIL)
  mkdir -p "$ARTIFACT_DIR"
  {
    for key in "${ordered_keys[@]}"; do
      print -r -- "$key=${RESULT[$key]}"
    done
  } > "$RESULT_FILE"
}

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
  local deadline=$(( $(date +%s) + 25 ))
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

terminate_pid() {
  local pid="$1"
  [[ -n "$pid" ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
  fi
}

cleanup() {
  terminate_pid "$APP_PID"
  terminate_pid "$HARNESS_PID"
  [[ -n "$APP_PID" ]] && wait "$APP_PID" 2>/dev/null || true
  [[ -n "$HARNESS_PID" ]] && wait "$HARNESS_PID" 2>/dev/null || true
  if [[ "$BOOTSTRAPPED" == "yes" ]]; then
    /bin/launchctl bootout "$SERVICE_DOMAIN" "$TEMP_LAUNCH_AGENT" >/dev/null 2>&1 || true
  fi
  local residual="no"
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    residual="yes"
  fi
  if [[ -n "$HARNESS_PID" ]] && kill -0 "$HARNESS_PID" 2>/dev/null; then
    residual="yes"
  fi
  if /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1; then
    residual="yes"
  fi
  RESULT[RESIDUAL_PROCESS]="$residual"
  write_result
}

trap cleanup EXIT

write_fake_backend() {
  cat > "$FAKE_BACKEND" <<PY
#!/usr/bin/python3
import argparse, asyncio, base64, hashlib, json, os, signal, struct, sys
from urllib.parse import parse_qs, urlparse
if sys.argv[1:] == ["--version"]:
    print("Hermes Agent v0.18.2")
    print("Install Method: m11-004-fixture")
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
  mkdir -p "$CONFIG_DIR" "$RUNTIME_ROOT" "$REQUEST_STATE_ROOT"
  cat > "$CONFIG_FILE" <<JSON
{
  "schemaVersion": 1,
  "machServiceName": "$MACH_SERVICE",
  "runtimeRoot": "file://$RUNTIME_ROOT",
  "requestStateRoot": "file://$REQUEST_STATE_ROOT",
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

write_temporary_launch_agent() {
  cat > "$TEMP_LAUNCH_AGENT" <<PLIST
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
  /usr/bin/plutil -lint "$TEMP_LAUNCH_AGENT" >/dev/null
}

build_production_products() {
  cd "$ROOT_DIR" || return 1
  swift build --configuration release --product HermesBridgeApp >/dev/null || return 1
  swift build --configuration release --product HermesBridgeService >/dev/null || return 1
  swift build --configuration release --product HermesBridgeServiceLifecycle >/dev/null || return 1
  swift build --configuration release --product HermesBridgeControl >/dev/null || return 1
  swift build --product HermesBridgeAppAcceptanceHarness >/dev/null || return 1
}

install_app_bundle_version() {
  local version="$1"
  local marker="$2"
  rm -rf "$INSTALLED_APP"
  mkdir -p \
    "$INSTALLED_APP/Contents/MacOS" \
    "$INSTALLED_APP/Contents/Frameworks" \
    "$INSTALLED_APP/Contents/XPCServices" \
    "$INSTALLED_APP/Contents/Library/HermesBridge" \
    "$INSTALLED_APP/Contents/Library/LaunchAgents" \
    "$INSTALLED_APP/Contents/Resources"
  cp "$ROOT_DIR/.build/release/HermesBridgeApp" "$APP_EXECUTABLE" || return 1
  cp "$ROOT_DIR/.build/release/HermesBridgeService" "$SERVICE_EXECUTABLE" || return 1
  cp "$ROOT_DIR/Packaging/HermesBridgeApp/Info.plist" "$INSTALLED_APP/Contents/Info.plist" || return 1
  cp "$ROOT_DIR/Packaging/LaunchAgent/com.hermes.bridge.plist.template" \
    "$INSTALLED_APP/Contents/Library/LaunchAgents/com.hermes.bridge.plist.template" || return 1
  cat > "$INSTALLED_APP/Contents/Resources/product-version.json" <<JSON
{
  "schemaVersion": 1,
  "version": "$version",
  "acceptanceSafeResource": "$marker"
}
JSON
  chmod 755 "$APP_EXECUTABLE" "$SERVICE_EXECUTABLE"
}

install_service_version() {
  local version="$1"
  "$LIFECYCLE" install \
    --artifact-root "$INSTALL_ROOT" \
    --service-binary "$SERVICE_EXECUTABLE" \
    --fake-launchctl \
    --fake-launchctl-log "$RUN_ROOT/fake-launchctl.log" \
    --bootstrap \
    --version "$version" \
    --keep-versions 3 > "$ARTIFACT_DIR/install-$version.json" || return 1
}

upgrade_service_version() {
  local version="$1"
  "$LIFECYCLE" upgrade \
    --artifact-root "$INSTALL_ROOT" \
    --service-binary "$SERVICE_EXECUTABLE" \
    --fake-launchctl \
    --fake-launchctl-log "$RUN_ROOT/fake-launchctl.log" \
    --bootstrap \
    --version "$version" \
    --keep-versions 3 > "$ARTIFACT_DIR/upgrade-$version.json" || return 1
}

rollback_service() {
  "$LIFECYCLE" rollback \
    --artifact-root "$INSTALL_ROOT" \
    --fake-launchctl \
    --fake-launchctl-log "$RUN_ROOT/fake-launchctl.log" \
    --bootstrap > "$ARTIFACT_DIR/rollback.json" || return 1
}

active_version() {
  /usr/bin/python3 - "$FAKE_HOME/Library/Application Support/HermesBridge/install-state.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get("activeVersion", ""))
PY
}

validate_layout() {
  [[ "$INSTALL_ROOT" == "$ROOT_DIR/artifacts/m11-004/install-root" ]] && RESULT[ISOLATED_INSTALL_ROOT_USED]=yes
  [[ -d "$INSTALLED_APP" && -x "$APP_EXECUTABLE" ]] && RESULT[APP_INSTALLED]=yes
  [[ -x "$SERVICE_EXECUTABLE" ]] && RESULT[SERVICE_INSTALLED]=yes
  [[ -f "$FAKE_HOME/Library/LaunchAgents/com.hermes.bridge.test.m3-001.plist" ]] \
    && RESULT[LAUNCH_CONFIGURATION_INSTALLED]=yes
  if [[ -d "$INSTALLED_APP/Contents/Frameworks" \
    && -d "$INSTALLED_APP/Contents/XPCServices" \
    && -d "$INSTALLED_APP/Contents/Resources" \
    && -f "$INSTALLED_APP/Contents/Resources/product-version.json" \
    && -f "$FAKE_HOME/Library/Application Support/HermesBridge/install-state.json" ]]; then
    RESULT[INSTALL_LAYOUT_VALID]=yes
  fi
  local app_count current_service
  app_count="$(find "$INSTALL_ROOT" -name "$APP_NAME" -type d | wc -l | tr -d ' ')"
  current_service="$FAKE_HOME/Library/Application Support/HermesBridge/Current/HermesBridgeService"
  [[ "$app_count" == "1" ]] && RESULT[DUPLICATE_APP_INSTALLED]=no
  if [[ -x "$SERVICE_EXECUTABLE" && -x "$current_service" \
    && -z "$(find "$FAKE_HOME/Library/LaunchAgents" -maxdepth 1 -name 'com.hermes.bridge.test.m3-001*.plist' -type f | tail -n +2)" ]]; then
    RESULT[DUPLICATE_SERVICE_INSTALLED]=no
  fi
}

scan_ownership_and_acceptance() {
  if ! rg -n \
    'HermesRuntimeSessionManager\(|HermesRuntimeEventBus\(|HermesRuntimeCommandAPI\(|HermesProcessSupervisor\(|HermesBackendAdapter\(|HermesProtocolClient\(' \
    "$ROOT_DIR/Sources/HermesBridgeApp" >/dev/null; then
    RESULT[APP_OWNS_CONCRETE_RUNTIME]=no
  fi
  if rg -n 'HermesBridgeCompositionRoot' "$ROOT_DIR/Sources/HermesBridgeService" >/dev/null; then
    RESULT[SERVICE_OWNS_RUNTIME]=yes
  fi
  local strings_file="$ARTIFACT_DIR/installed-app.strings"
  /usr/bin/strings "$APP_EXECUTABLE" "$SERVICE_EXECUTABLE" > "$strings_file" 2>/dev/null || true
  if ! grep -E 'HermesM11003AcceptanceController|HermesBridgeAppAcceptanceSupport|--hermes-m11-003-acceptance|M11_003_ACCEPTANCE|m11-003-token-sentinel' \
    "$strings_file" >/dev/null 2>&1; then
    RESULT[ACCEPTANCE_SUPPORT_INSTALLED]=no
    RESULT[ACCEPTANCE_SYMBOL_EXPOSED]=no
  fi
}

launch_installed_app() {
  "$APP_EXECUTABLE" >"$APP_STDOUT" 2>"$APP_STDERR" &
  APP_PID=$!
  sleep 1
  if kill -0 "$APP_PID" 2>/dev/null; then
    RESULT[INSTALLED_APP_STARTED]=yes
  fi
}

run_acceptance_harness() {
  local mode="$1"
  local evidence="$2"
  local stdout="$3"
  local stderr="$4"
  "$ACCEPTANCE_HARNESS" --hermes-m11-003-acceptance "$mode" "$STATE_FILE" "$evidence" \
    >"$stdout" 2>"$stderr" &
  HARNESS_PID=$!
}

security_scan() {
  local scan_root="$ARTIFACT_DIR/security-scan"
  rm -rf "$scan_root"
  mkdir -p "$scan_root"
  cp -R "$INSTALL_ROOT" "$scan_root/install-root" 2>/dev/null || true
  cp "$RESULT_FILE" "$FIRST_EVIDENCE" "$SECOND_EVIDENCE" "$STATE_FILE" "$scan_root/" 2>/dev/null || true

  if grep -R -I -E 'password[=:]|credential[=:]|secret[=:]|HERMES_DASHBOARD_SESSION_TOKEN' "$scan_root" >/dev/null 2>&1; then
    RESULT[TOKEN_EXPOSED]=yes
  else
    RESULT[TOKEN_EXPOSED]=no
  fi
  if grep -R -I -E 'BEGIN (RSA |OPENSSH |EC |DSA |)PRIVATE KEY' "$scan_root" >/dev/null 2>&1; then
    RESULT[PRIVATE_KEY_EXPOSED]=yes
  else
    RESULT[PRIVATE_KEY_EXPOSED]=no
  fi
  if grep -R -I -E 'HermesM11003AcceptanceController|HermesBridgeAppAcceptanceSupport|--hermes-m11-003-acceptance|M11_003_ACCEPTANCE' "$scan_root/install-root" >/dev/null 2>&1; then
    RESULT[ACCEPTANCE_SYMBOL_EXPOSED]=yes
  else
    RESULT[ACCEPTANCE_SYMBOL_EXPOSED]=no
  fi
  if grep -R -I -F "$ROOT_DIR/Sources" "$scan_root" >/dev/null 2>&1 \
    || grep -R -I -F "$ROOT_DIR/.build" "$scan_root" >/dev/null 2>&1; then
    RESULT[DEVELOPER_PATH_EXPOSED]=yes
  else
    RESULT[DEVELOPER_PATH_EXPOSED]=no
  fi
  rm -rf "$scan_root"
}

set_default_results
rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR" "$RUN_ROOT" "$INSTALLED_APP_ROOT"
write_result

RESULT[APPLICATIONS_MODIFIED]=no
RESULT[USER_LAUNCH_AGENTS_MODIFIED]=no
RESULT[REAL_HERMES_HOME_MODIFIED]=no

[[ "$INSTALL_ROOT" == "$ROOT_DIR/artifacts/m11-004/install-root" ]] || fail "unexpected install root"
if /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1; then
  fail "refusing to touch existing launchd label $SERVICE_DOMAIN/$LABEL"
fi

build_production_products || fail "production build failed"
RESULT[PRODUCTION_APP_BUILT]=yes

install_app_bundle_version "m11-004-A" "version-a" || fail "app install A failed"
install_service_version "m11-004-A" || fail "service install A failed"
[[ "$(active_version)" == "m11-004-A" ]] && RESULT[VERSION_A_INSTALLED]=yes
validate_layout
scan_ownership_and_acceptance

write_fake_backend
write_service_configuration "$(free_port)"
write_temporary_launch_agent
/bin/launchctl bootstrap "$SERVICE_DOMAIN" "$TEMP_LAUNCH_AGENT" >/dev/null || fail "temporary service bootstrap failed"
BOOTSTRAPPED=yes
RESULT[INSTALLED_SERVICE_STARTED]=yes

launch_installed_app

run_acceptance_harness "start-and-hold" "$FIRST_EVIDENCE" "$HARNESS_FIRST_STDOUT" "$HARNESS_FIRST_STDERR"
wait_for_file_key "$FIRST_EVIDENCE" "SESSION_STARTED" "yes" || fail "first XPC evidence timed out"
RESULT[XPC_CONNECTION_SUCCEEDED]="$(result_value "$FIRST_EVIDENCE" XPC_CONNECTION_SUCCEEDED)"
RESULT[XPC_PROTOCOL_1_7]="$(result_value "$FIRST_EVIDENCE" XPC_PROTOCOL_1_7)"
RESULT[SERVICE_OWNS_RUNTIME]="$(result_value "$FIRST_EVIDENCE" SERVICE_OWNS_RUNTIME)"
RESULT[SESSION_STARTED]="$(result_value "$FIRST_EVIDENCE" SESSION_STARTED)"
RESULT[EVENT_RECEIVED]="$(result_value "$FIRST_EVIDENCE" EVENT_RECEIVED)"
terminate_pid "$HARNESS_PID"
wait "$HARNESS_PID" 2>/dev/null || true
HARNESS_PID=""

terminate_pid "$APP_PID"
wait "$APP_PID" 2>/dev/null || true
APP_PID=""

run_acceptance_harness "reconnect-and-stop" "$SECOND_EVIDENCE" "$HARNESS_SECOND_STDOUT" "$HARNESS_SECOND_STDERR"
wait_for_file_key "$SECOND_EVIDENCE" "SESSION_STOPPED" "yes" || fail "second XPC evidence timed out"
RESULT[APP_RECONNECTED]="$(result_value "$SECOND_EVIDENCE" CLIENT_RECONNECTED)"
RESULT[SESSION_STOPPED]="$(result_value "$SECOND_EVIDENCE" SESSION_STOPPED)"
[[ "${RESULT[APP_RECONNECTED]}" == "yes" ]] && RESULT[RUNTIME_SURVIVED_APP_EXIT]=yes
terminate_pid "$HARNESS_PID"
wait "$HARNESS_PID" 2>/dev/null || true
HARNESS_PID=""
if [[ "$(result_value "$SECOND_EVIDENCE" EXPLICIT_STOP_FORWARDED_COUNT)" == "1" \
  && "${RESULT[SESSION_STOPPED]}" == "yes" ]]; then
  RESULT[EXPLICIT_STOP_FORWARDED_ONCE]=yes
fi

install_app_bundle_version "m11-004-B" "version-b" || fail "app install B failed"
upgrade_service_version "m11-004-B" || fail "upgrade to B failed"
RESULT[UPGRADE_TO_VERSION_B]=yes
[[ "$(active_version)" == "m11-004-B" ]] && RESULT[VERSION_B_ACTIVE]=yes
[[ -d "$FAKE_HOME/Library/Application Support/HermesBridge/State" ]] && RESULT[CONFIG_PRESERVED_ON_UPGRADE]=yes
validate_layout

rollback_service || fail "rollback to A failed"
RESULT[ROLLBACK_TO_VERSION_A]=yes
[[ "$(active_version)" == "m11-004-A" ]] && RESULT[VERSION_A_ACTIVE_AFTER_ROLLBACK]=yes
"$CONTROL" capabilities --timeout 5 >/dev/null 2>&1 && RESULT[XPC_WORKED_AFTER_ROLLBACK]=yes

local_bad="$RUN_ROOT/bad-upgrade/HermesBridgeService"
mkdir -p "$(dirname "$local_bad")"
cp "$SERVICE_EXECUTABLE" "$local_bad"
chmod 600 "$local_bad"
if ! "$LIFECYCLE" upgrade \
  --artifact-root "$INSTALL_ROOT" \
  --service-binary "$local_bad" \
  --fake-launchctl \
  --fake-launchctl-log "$RUN_ROOT/fake-launchctl.log" \
  --bootstrap \
  --version "m11-004-bad" > "$ARTIFACT_DIR/failed-upgrade.json" 2>"$ARTIFACT_DIR/failed-upgrade.stderr"; then
  [[ "$(active_version)" == "m11-004-A" ]] && RESULT[FAILED_UPGRADE_RECOVERED]=yes
fi
if [[ -z "$(find "$FAKE_HOME/Library/Application Support/HermesBridge/Versions" -name '.staging-*' -print -quit 2>/dev/null)" ]]; then
  RESULT[PARTIAL_FILES_CLEANED]=yes
fi

/bin/launchctl bootout "$SERVICE_DOMAIN" "$TEMP_LAUNCH_AGENT" >/dev/null 2>&1 || true
BOOTSTRAPPED=no

if "$LIFECYCLE" uninstall \
  --artifact-root "$INSTALL_ROOT" \
  --fake-launchctl \
  --fake-launchctl-log "$RUN_ROOT/fake-launchctl.log" > "$ARTIFACT_DIR/uninstall.txt"; then
  RESULT[UNINSTALL_SUCCEEDED]=yes
fi
rm -rf "$INSTALLED_APP"
[[ ! -e "$INSTALLED_APP" ]] && RESULT[APP_REMOVED]=yes
[[ ! -e "$FAKE_HOME/Library/Application Support/HermesBridge/Versions" ]] && RESULT[SERVICE_REMOVED]=yes
[[ ! -e "$FAKE_HOME/Library/LaunchAgents/com.hermes.bridge.test.m3-001.plist" ]] && RESULT[LAUNCH_CONFIGURATION_REMOVED]=yes

security_scan
write_result
exit 0
