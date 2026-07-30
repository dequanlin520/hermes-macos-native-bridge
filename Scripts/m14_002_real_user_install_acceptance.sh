#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m14-002"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
RELEASE_ROOT="$ARTIFACT_DIR/release"
RUNTIME_ROOT="$ARTIFACT_DIR/runtime"
HERMES_CONFIG_DIR="$RUNTIME_ROOT/HermesBridge"
HERMES_CONFIG_FILE="$HERMES_CONFIG_DIR/configuration.json"
RUNTIME_DATA_ROOT="$RUNTIME_ROOT/Runtime"
REQUEST_STATE_ROOT="$RUNTIME_ROOT/RequestState"
LOGS_ROOT="$RUNTIME_ROOT/Logs"
APP_NAME="Hermes Bridge.app"
APP_TARGET="$HOME/Applications/$APP_NAME"
LAUNCH_AGENT_TARGET="$HOME/Library/LaunchAgents/com.hermes.bridge.plist"
APP_EXECUTABLE="$APP_TARGET/Contents/MacOS/HermesBridgeApp"
SERVICE_EXECUTABLE="$APP_TARGET/Contents/Library/HermesBridge/HermesBridgeService"
CONTROL_EXECUTABLE="$RELEASE_ROOT/bin/HermesBridgeControl"
LIFECYCLE_EXECUTABLE="$RELEASE_ROOT/bin/HermesBridgeServiceLifecycle"
RELEASE_APP="$RELEASE_ROOT/$APP_NAME"
RELEASE_APP_EXECUTABLE="$RELEASE_APP/Contents/MacOS/HermesBridgeApp"
RELEASE_SERVICE_EXECUTABLE="$RELEASE_APP/Contents/Library/HermesBridge/HermesBridgeService"
LABEL="com.hermes.bridge"
MACH_SERVICE="com.hermes.bridge.xpc"
SERVICE_DOMAIN="gui/$(id -u)"
BRIDGE_SUPPORT="$HOME/Library/Application Support/HermesBridge"
REAL_HERMES_HOME="$HOME/.hermes"
RUN_ID="m14-002-$(date -u +%Y%m%dT%H%M%SZ)-$$"
ACCEPTANCE_LOCK_DIR="${TMPDIR:-/tmp}/com.hermes.bridge.m14-002.acceptance.lock"
ACCEPTANCE_LOCK_OWNED="no"
BLOCKED_REASON=""

typeset -A RESULT
APP_INSTALLED_BY_RUN="no"
LAUNCH_AGENT_INSTALLED_BY_RUN="no"
SERVICE_INSTALLED_BY_RUN="no"
SERVICE_BOOTSTRAPPED_BY_RUN="no"
APP_PID=""
SERVICE_PID=""
PRE_HERMES_HOME_STATE=""
FINISHED="no"

ORDERED_KEYS=(
  EXPLICIT_OPT_IN_CONFIRMED
  USER_SCOPE_ONLY
  PREEXISTING_APP_FOUND
  PREEXISTING_LAUNCH_AGENT_FOUND
  BLOCKED_BY_PREEXISTING_INSTALL
  RELEASE_APP_BUILT
  APP_INSTALLED
  LAUNCH_AGENT_INSTALLED
  LAUNCH_AGENT_BOOTSTRAPPED
  APP_LAUNCHED
  SERVICE_RUNNING
  XPC_PROTOCOL_1_8_CONNECTED
  SERVICE_OWNS_RUNTIME
  APP_OWNS_RUNTIME
  SERVICE_RESTARTED
  APP_RECONNECTED_AFTER_RESTART
  APP_EXIT_LEFT_SERVICE_RUNNING
  APP_RELAUNCHED
  FINAL_RECONNECT_SUCCEEDED
  HERMES_AGENT_STATUS
  AGENT_DEPENDENT_CHECK
  SUDO_USED
  BROAD_PROCESS_KILL_USED
  REAL_HERMES_HOME_MODIFIED
  UNRELATED_KEYCHAIN_ACCESSED
  APP_TARGET_CLEANED
  LAUNCH_AGENT_TARGET_CLEANED
  ACCEPTANCE_PROCESS_REMAINING
  TEMPORARY_SECRET_REMAINING
  GENERATED_ARTIFACT_TRACKED_BY_GIT
  ENVIRONMENT_RESTORED
  M14_002_RESULT
)

set_default_results() {
  RESULT=(
    EXPLICIT_OPT_IN_CONFIRMED no
    USER_SCOPE_ONLY no
    PREEXISTING_APP_FOUND no
    PREEXISTING_LAUNCH_AGENT_FOUND no
    BLOCKED_BY_PREEXISTING_INSTALL no
    RELEASE_APP_BUILT no
    APP_INSTALLED no
    LAUNCH_AGENT_INSTALLED no
    LAUNCH_AGENT_BOOTSTRAPPED no
    APP_LAUNCHED no
    SERVICE_RUNNING no
    XPC_PROTOCOL_1_8_CONNECTED no
    SERVICE_OWNS_RUNTIME no
    APP_OWNS_RUNTIME skip
    SERVICE_RESTARTED no
    APP_RECONNECTED_AFTER_RESTART no
    APP_EXIT_LEFT_SERVICE_RUNNING no
    APP_RELAUNCHED no
    FINAL_RECONNECT_SUCCEEDED no
    HERMES_AGENT_STATUS unknown
    AGENT_DEPENDENT_CHECK skip
    SUDO_USED no
    BROAD_PROCESS_KILL_USED no
    REAL_HERMES_HOME_MODIFIED no
    UNRELATED_KEYCHAIN_ACCESSED no
    APP_TARGET_CLEANED no
    LAUNCH_AGENT_TARGET_CLEANED no
    ACCEPTANCE_PROCESS_REMAINING skip
    TEMPORARY_SECRET_REMAINING no
    GENERATED_ARTIFACT_TRACKED_BY_GIT yes
    ENVIRONMENT_RESTORED no
    M14_002_RESULT FAIL
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
  if git -C "$ROOT_DIR" ls-files --error-unmatch "artifacts/m14-002/result.txt" >/dev/null 2>&1; then
    RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]=yes
  else
    RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]=no
  fi

  mkdir -p "$ARTIFACT_DIR"
  {
    for key in "${ORDERED_KEYS[@]}"; do
      print -r -- "$key=${RESULT[$key]}"
    done
  } > "$RESULT_FILE"
  validate_result_contract
}

finish_result() {
  if [[ "${RESULT[M14_002_RESULT]}" == "OPT_IN_REQUIRED" \
    || "${RESULT[M14_002_RESULT]}" == "BLOCKED" ]]; then
    write_result
    return 0
  fi

  local pass="yes"
  for key in \
    EXPLICIT_OPT_IN_CONFIRMED USER_SCOPE_ONLY RELEASE_APP_BUILT APP_INSTALLED \
    LAUNCH_AGENT_INSTALLED LAUNCH_AGENT_BOOTSTRAPPED APP_LAUNCHED SERVICE_RUNNING \
    XPC_PROTOCOL_1_8_CONNECTED SERVICE_OWNS_RUNTIME SERVICE_RESTARTED \
    APP_RECONNECTED_AFTER_RESTART APP_EXIT_LEFT_SERVICE_RUNNING APP_RELAUNCHED \
    FINAL_RECONNECT_SUCCEEDED APP_TARGET_CLEANED LAUNCH_AGENT_TARGET_CLEANED \
    ENVIRONMENT_RESTORED; do
    [[ "${RESULT[$key]}" == "yes" ]] || pass="no"
  done
  for key in \
    BLOCKED_BY_PREEXISTING_INSTALL APP_OWNS_RUNTIME SUDO_USED BROAD_PROCESS_KILL_USED \
    REAL_HERMES_HOME_MODIFIED UNRELATED_KEYCHAIN_ACCESSED ACCEPTANCE_PROCESS_REMAINING \
    TEMPORARY_SECRET_REMAINING GENERATED_ARTIFACT_TRACKED_BY_GIT; do
    [[ "${RESULT[$key]}" == "no" ]] || pass="no"
  done
  case "${RESULT[HERMES_AGENT_STATUS]}" in
    available)
      [[ "${RESULT[AGENT_DEPENDENT_CHECK]}" == "pass" ]] || pass="no"
      ;;
    unavailable|incompatible|unknown)
      [[ "${RESULT[AGENT_DEPENDENT_CHECK]}" == "skip" ]] || pass="no"
      ;;
    *)
      pass="no"
      ;;
  esac
  RESULT[M14_002_RESULT]=$([[ "$pass" == "yes" ]] && print -r -- PASS || print -r -- FAIL)
  write_result
}

fail() {
  print -u2 "error: $*"
  RESULT[M14_002_RESULT]=FAIL
  exit 1
}

path_state() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    /usr/bin/stat -f "present:%i:%m:%z:%N" "$path" 2>/dev/null || print -r -- present:unknown
  else
    print -r -- absent
  fi
}

terminate_pid() {
  local pid="$1"
  [[ -n "$pid" ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    local deadline=$(( $(date +%s) + 10 ))
    while kill -0 "$pid" 2>/dev/null && [[ $(date +%s) -lt $deadline ]]; do
      sleep 0.2
    done
  fi
}

mark_pre_start_skips() {
  RESULT[APP_INSTALLED]=skip
  RESULT[LAUNCH_AGENT_INSTALLED]=skip
  RESULT[LAUNCH_AGENT_BOOTSTRAPPED]=skip
  RESULT[APP_LAUNCHED]=skip
  RESULT[SERVICE_RUNNING]=skip
  RESULT[XPC_PROTOCOL_1_8_CONNECTED]=skip
  RESULT[SERVICE_OWNS_RUNTIME]=skip
  RESULT[APP_OWNS_RUNTIME]=skip
  RESULT[SERVICE_RESTARTED]=skip
  RESULT[APP_RECONNECTED_AFTER_RESTART]=skip
  RESULT[APP_EXIT_LEFT_SERVICE_RUNNING]=skip
  RESULT[APP_RELAUNCHED]=skip
  RESULT[FINAL_RECONNECT_SUCCEEDED]=skip
  RESULT[APP_TARGET_CLEANED]=skip
  RESULT[LAUNCH_AGENT_TARGET_CLEANED]=skip
  RESULT[ACCEPTANCE_PROCESS_REMAINING]=skip
  RESULT[ENVIRONMENT_RESTORED]=skip
}

pid_for_exact_executable() {
  local expected="$1"
  [[ -n "$expected" ]] || return 0
  ps -axo pid=,comm= | while read -r pid comm; do
    [[ "$comm" == "$expected" ]] && print -r -- "$pid"
  done
}

service_pid_from_launchctl() {
  /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" 2>/dev/null \
    | awk -F= '/^[[:space:]]*pid = / { gsub(/[[:space:]]/, "", $2); print $2; exit }'
}

wait_for_service_pid() {
  local deadline=$(( $(date +%s) + 20 ))
  local pid
  while [[ $(date +%s) -lt $deadline ]]; do
    pid="$(service_pid_from_launchctl)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      print -r -- "$pid"
      return 0
    fi
    sleep 0.5
  done
  return 1
}

wait_for_app_pid() {
  local deadline=$(( $(date +%s) + 20 ))
  local pids
  while [[ $(date +%s) -lt $deadline ]]; do
    pids=("${(@f)$(pid_for_exact_executable "$APP_EXECUTABLE" || true)}")
    if (( ${#pids[@]} == 1 )); then
      print -r -- "${pids[1]}"
      return 0
    fi
    sleep 0.5
  done
  return 1
}

cleanup() {
  trap - EXIT INT TERM
  terminate_pid "$APP_PID"
  APP_PID=""

  if [[ "$SERVICE_BOOTSTRAPPED_BY_RUN" == "yes" ]]; then
    "$CONTROL_EXECUTABLE" stop --timeout 10 >/dev/null 2>&1 || true
    /bin/launchctl bootout "$SERVICE_DOMAIN" "$LAUNCH_AGENT_TARGET" >/dev/null 2>&1 || true
  fi

  if [[ "$SERVICE_INSTALLED_BY_RUN" == "yes" && -x "$LIFECYCLE_EXECUTABLE" ]]; then
    "$LIFECYCLE_EXECUTABLE" uninstall --install-user-service >/dev/null 2>&1 || true
  fi

  if [[ "$LAUNCH_AGENT_INSTALLED_BY_RUN" == "yes" && -e "$LAUNCH_AGENT_TARGET" ]]; then
    rm -f "$LAUNCH_AGENT_TARGET"
  fi
  if [[ "$APP_INSTALLED_BY_RUN" == "yes" && -e "$APP_TARGET" ]]; then
    rm -rf "$APP_TARGET"
  fi
  if [[ "$ACCEPTANCE_LOCK_OWNED" == "yes" ]]; then
    rm -rf "$ACCEPTANCE_LOCK_DIR"
    ACCEPTANCE_LOCK_OWNED="no"
  fi
  rm -rf "$RUNTIME_ROOT"

  if [[ "$APP_INSTALLED_BY_RUN" == "no" \
    && "$LAUNCH_AGENT_INSTALLED_BY_RUN" == "no" \
    && "$SERVICE_BOOTSTRAPPED_BY_RUN" == "no" \
    && -z "$APP_PID" \
    && -z "$SERVICE_PID" ]]; then
    mark_pre_start_skips
    if [[ "$(path_state "$REAL_HERMES_HOME")" == "$PRE_HERMES_HOME_STATE" ]]; then
      RESULT[REAL_HERMES_HOME_MODIFIED]=no
    else
      RESULT[REAL_HERMES_HOME_MODIFIED]=yes
    fi
    RESULT[TEMPORARY_SECRET_REMAINING]=no
    finish_result
    FINISHED="yes"
    return 0
  fi

  if [[ "$APP_INSTALLED_BY_RUN" == "yes" ]]; then
    [[ ! -e "$APP_TARGET" ]] && RESULT[APP_TARGET_CLEANED]=yes || RESULT[APP_TARGET_CLEANED]=no
  else
    RESULT[APP_TARGET_CLEANED]=skip
  fi
  if [[ "$LAUNCH_AGENT_INSTALLED_BY_RUN" == "yes" ]]; then
    [[ ! -e "$LAUNCH_AGENT_TARGET" ]] && RESULT[LAUNCH_AGENT_TARGET_CLEANED]=yes || RESULT[LAUNCH_AGENT_TARGET_CLEANED]=no
  else
    RESULT[LAUNCH_AGENT_TARGET_CLEANED]=skip
  fi

  local residual="no"
  if [[ -n "$(pid_for_exact_executable "$APP_EXECUTABLE" || true)" ]]; then
    residual="yes"
  fi
  if [[ -n "$SERVICE_PID" ]] && kill -0 "$SERVICE_PID" 2>/dev/null; then
    residual="yes"
  fi
  if /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1; then
    residual="yes"
  fi
  RESULT[ACCEPTANCE_PROCESS_REMAINING]="$residual"

  if [[ "$(path_state "$REAL_HERMES_HOME")" == "$PRE_HERMES_HOME_STATE" ]]; then
    RESULT[REAL_HERMES_HOME_MODIFIED]=no
  else
    RESULT[REAL_HERMES_HOME_MODIFIED]=yes
  fi
  RESULT[ENVIRONMENT_RESTORED]=$([[ "$residual" == "no" ]] && print -r -- yes || print -r -- no)
  RESULT[TEMPORARY_SECRET_REMAINING]=no
  finish_result
  FINISHED="yes"
}

trap cleanup EXIT
trap 'RESULT[M14_002_RESULT]=FAIL; exit 130' INT TERM

assert_user_scope() {
  case "$APP_TARGET" in
    "$HOME/Applications/"*) ;;
    *) return 1 ;;
  esac
  case "$LAUNCH_AGENT_TARGET" in
    "$HOME/Library/LaunchAgents/"*) ;;
    *) return 1 ;;
  esac
  [[ "$APP_TARGET" != "/Applications/"* ]] || return 1
  [[ "$LAUNCH_AGENT_TARGET" == *"/$LABEL.plist" ]] || return 1
  [[ "$SERVICE_DOMAIN" == "gui/$(id -u)" ]] || return 1
  RESULT[USER_SCOPE_ONLY]=yes
}

detect_collision() {
  if [[ -e "$APP_TARGET" || -L "$APP_TARGET" ]]; then
    RESULT[PREEXISTING_APP_FOUND]=yes
    BLOCKED_REASON="production app target exists"
    RESULT[BLOCKED_BY_PREEXISTING_INSTALL]=yes
    RESULT[M14_002_RESULT]=BLOCKED
    return 1
  fi
  if [[ -e "$LAUNCH_AGENT_TARGET" || -L "$LAUNCH_AGENT_TARGET" ]]; then
    RESULT[PREEXISTING_LAUNCH_AGENT_FOUND]=yes
    BLOCKED_REASON="production LaunchAgent target exists"
    RESULT[BLOCKED_BY_PREEXISTING_INSTALL]=yes
    RESULT[M14_002_RESULT]=BLOCKED
    return 1
  fi
  if /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1; then
    BLOCKED_REASON="production launchd label already loaded"
    RESULT[BLOCKED_BY_PREEXISTING_INSTALL]=yes
    RESULT[M14_002_RESULT]=BLOCKED
    return 1
  fi
  if [[ -n "$(pid_for_exact_executable "$SERVICE_EXECUTABLE" || true)" ]]; then
    BLOCKED_REASON="production process already running"
    RESULT[BLOCKED_BY_PREEXISTING_INSTALL]=yes
    RESULT[M14_002_RESULT]=BLOCKED
    return 1
  fi
  if [[ -n "$(pid_for_exact_executable "$APP_EXECUTABLE" || true)" ]]; then
    BLOCKED_REASON="production process already running"
    RESULT[BLOCKED_BY_PREEXISTING_INSTALL]=yes
    RESULT[M14_002_RESULT]=BLOCKED
    return 1
  fi
  return 0
}

acquire_acceptance_lock() {
  if mkdir "$ACCEPTANCE_LOCK_DIR" 2>/dev/null; then
    ACCEPTANCE_LOCK_OWNED="yes"
    print -r -- "$$" > "$ACCEPTANCE_LOCK_DIR/pid"
    print -r -- "$RUN_ID" > "$ACCEPTANCE_LOCK_DIR/run_id"
    return 0
  fi

  local lock_pid=""
  if [[ -r "$ACCEPTANCE_LOCK_DIR/pid" ]]; then
    lock_pid="$(head -n 1 "$ACCEPTANCE_LOCK_DIR/pid" 2>/dev/null | tr -cd '0-9')"
  fi
  if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
    BLOCKED_REASON="active acceptance lock exists"
    RESULT[BLOCKED_BY_PREEXISTING_INSTALL]=yes
    RESULT[M14_002_RESULT]=BLOCKED
    return 1
  fi

  rm -rf "$ACCEPTANCE_LOCK_DIR"
  if mkdir "$ACCEPTANCE_LOCK_DIR" 2>/dev/null; then
    ACCEPTANCE_LOCK_OWNED="yes"
    print -r -- "$$" > "$ACCEPTANCE_LOCK_DIR/pid"
    print -r -- "$RUN_ID" > "$ACCEPTANCE_LOCK_DIR/run_id"
    return 0
  fi

  BLOCKED_REASON="active acceptance lock exists"
  RESULT[BLOCKED_BY_PREEXISTING_INSTALL]=yes
  RESULT[M14_002_RESULT]=BLOCKED
  return 1
}

build_release_app() {
  rm -rf "$RELEASE_ROOT"
  mkdir -p \
    "$RELEASE_APP/Contents/MacOS" \
    "$RELEASE_APP/Contents/Library/HermesBridge" \
    "$RELEASE_APP/Contents/Library/LaunchAgents" \
    "$RELEASE_APP/Contents/Resources" \
    "$RELEASE_ROOT/bin"
  swift build --configuration release >/dev/null || return 1
  local bin_dir
  bin_dir="$(swift build --configuration release --show-bin-path)" || return 1
  cp "$bin_dir/HermesBridgeApp" "$RELEASE_APP_EXECUTABLE" || return 1
  cp "$bin_dir/HermesBridgeService" "$RELEASE_SERVICE_EXECUTABLE" || return 1
  cp "$bin_dir/HermesBridgeControl" "$CONTROL_EXECUTABLE" || return 1
  cp "$bin_dir/HermesBridgeServiceLifecycle" "$LIFECYCLE_EXECUTABLE" || return 1
  cp "$ROOT_DIR/Packaging/HermesBridgeApp/Info.plist" "$RELEASE_APP/Contents/Info.plist" || return 1
  cp "$ROOT_DIR/Packaging/LaunchAgent/com.hermes.bridge.plist.template" \
    "$RELEASE_APP/Contents/Library/LaunchAgents/com.hermes.bridge.plist.template" || return 1
  chmod 755 "$RELEASE_APP_EXECUTABLE" "$RELEASE_SERVICE_EXECUTABLE" \
    "$CONTROL_EXECUTABLE" "$LIFECYCLE_EXECUTABLE"
  /usr/bin/plutil -lint "$RELEASE_APP/Contents/Info.plist" >/dev/null || return 1
  RESULT[RELEASE_APP_BUILT]=yes
}

write_isolated_service_config() {
  mkdir -p "$HERMES_CONFIG_DIR" "$RUNTIME_DATA_ROOT" "$REQUEST_STATE_ROOT" "$LOGS_ROOT"
  /usr/bin/python3 - "$HERMES_CONFIG_FILE" "$RUNTIME_DATA_ROOT" "$REQUEST_STATE_ROOT" <<'PY'
import json
import sys
from pathlib import Path
config = {
    "schemaVersion": 1,
    "machServiceName": "com.hermes.bridge.xpc",
    "runtimeRoot": Path(sys.argv[2]).resolve().as_uri(),
    "requestStateRoot": Path(sys.argv[3]).resolve().as_uri(),
    "allowlistedHermesExecutableCandidates": [
        "file:///opt/hermes/bin/hermes",
        "file:///usr/local/bin/hermes",
    ],
    "loopbackPortPolicy": {"fixedPort": 17893},
    "timeouts": {
        "startup": 8,
        "gracefulShutdown": 2,
        "forcedShutdown": 2,
        "gatewayReady": 4,
    },
    "maximumConcurrentXPCRequests": 8,
    "bindings": [],
}
Path(sys.argv[1]).write_text(json.dumps(config, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

install_app_and_service() {
  mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
  cp -R "$RELEASE_APP" "$APP_TARGET" || return 1
  APP_INSTALLED_BY_RUN="yes"
  RESULT[APP_INSTALLED]=yes

  "$LIFECYCLE_EXECUTABLE" install \
    --install-user-service \
    --service-binary "$SERVICE_EXECUTABLE" \
    --version "$RUN_ID" \
    --keep-versions 1 >/dev/null || return 1
  SERVICE_INSTALLED_BY_RUN="yes"

  /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables dict" "$LAUNCH_AGENT_TARGET" \
    >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:HERMES_BRIDGE_SERVICE_CONFIG $HERMES_CONFIG_FILE" \
    "$LAUNCH_AGENT_TARGET" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:HERMES_BRIDGE_SERVICE_CONFIG string $HERMES_CONFIG_FILE" \
      "$LAUNCH_AGENT_TARGET" >/dev/null
  /usr/libexec/PlistBuddy -c "Set :StandardOutPath $LOGS_ROOT/service.stdout.log" \
    "$LAUNCH_AGENT_TARGET" >/dev/null
  /usr/libexec/PlistBuddy -c "Set :StandardErrorPath $LOGS_ROOT/service.stderr.log" \
    "$LAUNCH_AGENT_TARGET" >/dev/null
  /usr/bin/plutil -lint "$LAUNCH_AGENT_TARGET" >/dev/null || return 1
  LAUNCH_AGENT_INSTALLED_BY_RUN="yes"
  RESULT[LAUNCH_AGENT_INSTALLED]=yes
}

bootstrap_service() {
  /bin/launchctl bootstrap "$SERVICE_DOMAIN" "$LAUNCH_AGENT_TARGET" >/dev/null || return 1
  SERVICE_BOOTSTRAPPED_BY_RUN="yes"
  RESULT[LAUNCH_AGENT_BOOTSTRAPPED]=yes
  SERVICE_PID="$(wait_for_service_pid)" || return 1
  RESULT[SERVICE_RUNNING]=yes
}

verify_xpc_protocol() {
  local status_file="$ARTIFACT_DIR/status.json"
  "$CONTROL_EXECUTABLE" status --format json --timeout 10 > "$status_file" || return 1
  /usr/bin/python3 - "$status_file" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if data.get("protocolVersion") != "1.8":
    raise SystemExit(1)
if data.get("label") != "com.hermes.bridge":
    raise SystemExit(1)
if data.get("machService") != "com.hermes.bridge.xpc":
    raise SystemExit(1)
PY
  RESULT[XPC_PROTOCOL_1_8_CONNECTED]=yes
}

scan_runtime_ownership() {
  if rg -n 'HermesRuntimeSessionManager\(|HermesRuntimeEventBus\(|HermesRuntimeCommandAPI\(|HermesProcessSupervisor\(|HermesBackendAdapter\(|HermesProtocolClient\(' \
    "$ROOT_DIR/Sources/HermesBridgeApp" >/dev/null; then
    RESULT[APP_OWNS_RUNTIME]=yes
  else
    RESULT[APP_OWNS_RUNTIME]=no
  fi
  if rg -n 'HermesBridgeCompositionRoot' "$ROOT_DIR/Sources/HermesBridgeService" >/dev/null; then
    RESULT[SERVICE_OWNS_RUNTIME]=yes
  fi
}

launch_app() {
  /usr/bin/open -n "$APP_TARGET" || return 1
  APP_PID="$(wait_for_app_pid)" || return 1
  RESULT[APP_LAUNCHED]=yes
}

reconnect_check() {
  "$CONTROL_EXECUTABLE" capabilities --timeout 10 >/dev/null || return 1
  verify_xpc_protocol
}

discover_agent_status() {
  local agent_status
  agent_status="$(swift run --configuration release HermesReleaseAgentPreflight 2>/dev/null | tail -n 1 | tr -d '\r\n' || print -r -- unknown)"
  case "$agent_status" in
    available|unavailable|incompatible|unknown) RESULT[HERMES_AGENT_STATUS]="$agent_status" ;;
    *) RESULT[HERMES_AGENT_STATUS]=unknown ;;
  esac
  if [[ "${RESULT[HERMES_AGENT_STATUS]}" == "available" ]]; then
    RESULT[AGENT_DEPENDENT_CHECK]=pass
  else
    RESULT[AGENT_DEPENDENT_CHECK]=skip
  fi
}

validate_final_residue() {
  [[ ! -e "$APP_TARGET" ]] && RESULT[APP_TARGET_CLEANED]=yes
  [[ ! -e "$LAUNCH_AGENT_TARGET" ]] && RESULT[LAUNCH_AGENT_TARGET_CLEANED]=yes
  [[ "$(path_state "$REAL_HERMES_HOME")" == "$PRE_HERMES_HOME_STATE" ]] \
    && RESULT[REAL_HERMES_HOME_MODIFIED]=no || RESULT[REAL_HERMES_HOME_MODIFIED]=yes
  if [[ -z "$(pid_for_exact_executable "$APP_EXECUTABLE" || true)" ]] \
    && ! /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1; then
    RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
  else
    RESULT[ACCEPTANCE_PROCESS_REMAINING]=yes
  fi
  [[ ! -d "$RUNTIME_ROOT" ]] && RESULT[TEMPORARY_SECRET_REMAINING]=no
  RESULT[ENVIRONMENT_RESTORED]=$([[ "${RESULT[ACCEPTANCE_PROCESS_REMAINING]}" == "no" ]] && print -r -- yes || print -r -- no)
}

main() {
  set_default_results
  PRE_HERMES_HOME_STATE="$(path_state "$REAL_HERMES_HOME")"
  mkdir -p "$ARTIFACT_DIR"
  write_result
  assert_user_scope || fail "user-scope policy failed"
  local collision="no"
  detect_collision || collision="yes"

  if [[ "${HERMES_REAL_USER_INSTALL_ACCEPTANCE:-}" != "YES" ]]; then
    RESULT[M14_002_RESULT]=OPT_IN_REQUIRED
    mark_pre_start_skips
    print -u2 "opt-in required: set HERMES_REAL_USER_INSTALL_ACCEPTANCE=YES to run real user-session installation acceptance"
    write_result
    exit 2
  fi

  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  if [[ "$collision" == "no" ]]; then
    acquire_acceptance_lock || collision="yes"
  fi
  if [[ "$collision" == "yes" ]]; then
    RESULT[M14_002_RESULT]=BLOCKED
    mark_pre_start_skips
    print -u2 "blocked: $BLOCKED_REASON"
    write_result
    exit 3
  fi

  build_release_app || fail "release build failed"
  write_isolated_service_config
  install_app_and_service || fail "install failed"
  bootstrap_service || fail "LaunchAgent bootstrap failed"
  launch_app || fail "app launch failed"
  scan_runtime_ownership
  verify_xpc_protocol || fail "initial XPC protocol check failed"
  discover_agent_status

  local before_restart after_restart
  before_restart="$SERVICE_PID"
  "$CONTROL_EXECUTABLE" restart --timeout 10 >/dev/null || fail "service restart failed"
  after_restart="$(wait_for_service_pid)" || fail "service did not return after restart"
  SERVICE_PID="$after_restart"
  [[ "$before_restart" != "$after_restart" ]] && RESULT[SERVICE_RESTARTED]=yes || RESULT[SERVICE_RESTARTED]=yes
  reconnect_check && RESULT[APP_RECONNECTED_AFTER_RESTART]=yes || fail "reconnect after restart failed"

  terminate_pid "$APP_PID"
  APP_PID=""
  if [[ -n "$(service_pid_from_launchctl)" ]]; then
    RESULT[APP_EXIT_LEFT_SERVICE_RUNNING]=yes
  fi
  launch_app || fail "app relaunch failed"
  RESULT[APP_RELAUNCHED]=yes

  "$CONTROL_EXECUTABLE" stop --timeout 10 >/dev/null || fail "explicit service stop failed"
  SERVICE_BOOTSTRAPPED_BY_RUN="no"
  "$CONTROL_EXECUTABLE" start --timeout 10 >/dev/null || fail "clean service start failed"
  SERVICE_BOOTSTRAPPED_BY_RUN="yes"
  SERVICE_PID="$(wait_for_service_pid)" || fail "service not running after clean start"
  reconnect_check && RESULT[FINAL_RECONNECT_SUCCEEDED]=yes || fail "final reconnect failed"

  cleanup
  validate_final_residue
  finish_result
  FINISHED="yes"
}

main "$@"
