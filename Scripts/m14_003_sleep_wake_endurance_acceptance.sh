#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m14-003"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
RELEASE_ROOT="$ARTIFACT_DIR/release"
RUNTIME_ROOT="$ARTIFACT_DIR/runtime"
HERMES_CONFIG_DIR="$RUNTIME_ROOT/HermesBridge"
HERMES_CONFIG_FILE="$HERMES_CONFIG_DIR/configuration.json"
RUNTIME_DATA_ROOT="$RUNTIME_ROOT/Runtime"
REQUEST_STATE_ROOT="$RUNTIME_ROOT/RequestState"
LOGS_ROOT="$RUNTIME_ROOT/Logs"
ISOLATED_HOME="$RUNTIME_ROOT/Home"
ISOLATED_HERMES_HOME="$RUNTIME_ROOT/hermes-home"
ISOLATED_XDG_CONFIG_HOME="$RUNTIME_ROOT/xdg-config"
ISOLATED_XDG_CACHE_HOME="$RUNTIME_ROOT/xdg-cache"
ISOLATED_XDG_DATA_HOME="$RUNTIME_ROOT/xdg-data"
ISOLATED_XDG_STATE_HOME="$RUNTIME_ROOT/xdg-state"
ISOLATED_XDG_RUNTIME_DIR="$RUNTIME_ROOT/xdg-runtime"
APP_NAME="Hermes Bridge.app"
APP_TARGET="$HOME/Applications/$APP_NAME"
LAUNCH_AGENT_TARGET="$HOME/Library/LaunchAgents/com.hermes.bridge.plist"
APP_EXECUTABLE="$APP_TARGET/Contents/MacOS/HermesBridgeApp"
SERVICE_EXECUTABLE="$APP_TARGET/Contents/Library/HermesBridge/HermesBridgeService"
CONTROL_EXECUTABLE="$RELEASE_ROOT/bin/HermesBridgeControl"
RELEASE_APP="$RELEASE_ROOT/$APP_NAME"
RELEASE_APP_EXECUTABLE="$RELEASE_APP/Contents/MacOS/HermesBridgeApp"
RELEASE_SERVICE_EXECUTABLE="$RELEASE_APP/Contents/Library/HermesBridge/HermesBridgeService"
LABEL="com.hermes.bridge"
MACH_SERVICE="com.hermes.bridge.xpc"
SERVICE_DOMAIN="gui/$(id -u)"
REAL_HERMES_HOME="$HOME/.hermes"
RUN_ID="m14-003-$(date -u +%Y%m%dT%H%M%SZ)-$$"
ACCEPTANCE_LOCK_DIR="${TMPDIR:-/tmp}/com.hermes.bridge.m14-003.acceptance.lock"
ACCEPTANCE_LOCK_OWNED="no"
BLOCKED_REASON=""
WAKE_TIMEOUT_SECONDS="${HERMES_M14_003_WAKE_TIMEOUT_SECONDS:-900}"
RESTART_CYCLES_EXPECTED=5

typeset -A RESULT
APP_INSTALLED_BY_RUN="no"
LAUNCH_AGENT_INSTALLED_BY_RUN="no"
SERVICE_BOOTSTRAPPED_BY_RUN="no"
APP_PID=""
SERVICE_PID=""
INTEGRITY_BEFORE="$ARTIFACT_DIR/real-home-before.snapshot"
INTEGRITY_AFTER="$ARTIFACT_DIR/real-home-after.snapshot"
INTEGRITY_CHANGES="$ARTIFACT_DIR/real-home-changes.txt"
FINISHED="no"

ORDERED_KEYS=(
  EXPLICIT_OPT_IN_CONFIRMED
  USER_SCOPE_ONLY
  COLLISION_CHECK_PASSED
  RELEASE_APP_BUILT
  APP_INSTALLED
  LAUNCH_AGENT_INSTALLED
  INITIAL_XPC_CONNECTED
  PRE_SLEEP_RESTART_CYCLES_EXPECTED
  PRE_SLEEP_RESTART_CYCLES_PASSED
  APP_EXIT_LEFT_SERVICE_RUNNING
  APP_RELAUNCHED_BEFORE_SLEEP
  PRE_SLEEP_RECONNECT_SUCCEEDED
  WAITING_FOR_MANUAL_SLEEP
  REAL_SLEEP_DETECTED
  REAL_WAKE_DETECTED
  WAKE_TIMEOUT_OCCURRED
  SERVICE_RUNNING_AFTER_WAKE
  XPC_CONNECTED_AFTER_WAKE
  APP_RECONNECTED_AFTER_WAKE
  SERVICE_OWNS_RUNTIME_AFTER_WAKE
  APP_OWNS_RUNTIME_AFTER_WAKE
  DUPLICATE_SERVICE_INSTANCE_FOUND
  FINAL_SERVICE_RESTARTED
  FINAL_RECONNECT_SUCCEEDED
  HERMES_AGENT_STATUS
  AGENT_DEPENDENT_CHECK
  SUDO_USED
  BROAD_PROCESS_KILL_USED
  REAL_HERMES_HOME_MODIFIED
  APP_TARGET_CLEANED
  LAUNCH_AGENT_TARGET_CLEANED
  ACCEPTANCE_PROCESS_REMAINING
  ENVIRONMENT_RESTORED
  GENERATED_ARTIFACT_TRACKED_BY_GIT
  M14_003_RESULT
)

set_default_results() {
  RESULT=(
    EXPLICIT_OPT_IN_CONFIRMED no
    USER_SCOPE_ONLY no
    COLLISION_CHECK_PASSED no
    RELEASE_APP_BUILT no
    APP_INSTALLED no
    LAUNCH_AGENT_INSTALLED no
    INITIAL_XPC_CONNECTED no
    PRE_SLEEP_RESTART_CYCLES_EXPECTED "$RESTART_CYCLES_EXPECTED"
    PRE_SLEEP_RESTART_CYCLES_PASSED 0
    APP_EXIT_LEFT_SERVICE_RUNNING no
    APP_RELAUNCHED_BEFORE_SLEEP no
    PRE_SLEEP_RECONNECT_SUCCEEDED no
    WAITING_FOR_MANUAL_SLEEP no
    REAL_SLEEP_DETECTED no
    REAL_WAKE_DETECTED no
    WAKE_TIMEOUT_OCCURRED no
    SERVICE_RUNNING_AFTER_WAKE no
    XPC_CONNECTED_AFTER_WAKE no
    APP_RECONNECTED_AFTER_WAKE no
    SERVICE_OWNS_RUNTIME_AFTER_WAKE no
    APP_OWNS_RUNTIME_AFTER_WAKE skip
    DUPLICATE_SERVICE_INSTANCE_FOUND skip
    FINAL_SERVICE_RESTARTED no
    FINAL_RECONNECT_SUCCEEDED no
    HERMES_AGENT_STATUS unknown
    AGENT_DEPENDENT_CHECK skip
    SUDO_USED no
    BROAD_PROCESS_KILL_USED no
    REAL_HERMES_HOME_MODIFIED no
    APP_TARGET_CLEANED no
    LAUNCH_AGENT_TARGET_CLEANED no
    ACCEPTANCE_PROCESS_REMAINING skip
    ENVIRONMENT_RESTORED no
    GENERATED_ARTIFACT_TRACKED_BY_GIT yes
    M14_003_RESULT FAIL
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
  if git -C "$ROOT_DIR" ls-files --error-unmatch "artifacts/m14-003/result.txt" >/dev/null 2>&1; then
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

result_exit_code() {
  case "${RESULT[M14_003_RESULT]}" in
    PASS) return 0 ;;
    FAIL) return 1 ;;
    OPT_IN_REQUIRED) return 2 ;;
    BLOCKED) return 3 ;;
    TIMEOUT) return 4 ;;
    *) return 1 ;;
  esac
}

mark_pre_start_skips() {
  RESULT[APP_INSTALLED]=skip
  RESULT[LAUNCH_AGENT_INSTALLED]=skip
  RESULT[INITIAL_XPC_CONNECTED]=skip
  RESULT[APP_EXIT_LEFT_SERVICE_RUNNING]=skip
  RESULT[APP_RELAUNCHED_BEFORE_SLEEP]=skip
  RESULT[PRE_SLEEP_RECONNECT_SUCCEEDED]=skip
  RESULT[REAL_SLEEP_DETECTED]=skip
  RESULT[REAL_WAKE_DETECTED]=skip
  RESULT[SERVICE_RUNNING_AFTER_WAKE]=skip
  RESULT[XPC_CONNECTED_AFTER_WAKE]=skip
  RESULT[APP_RECONNECTED_AFTER_WAKE]=skip
  RESULT[SERVICE_OWNS_RUNTIME_AFTER_WAKE]=skip
  RESULT[APP_OWNS_RUNTIME_AFTER_WAKE]=skip
  RESULT[DUPLICATE_SERVICE_INSTANCE_FOUND]=skip
  RESULT[FINAL_SERVICE_RESTARTED]=skip
  RESULT[FINAL_RECONNECT_SUCCEEDED]=skip
  RESULT[APP_TARGET_CLEANED]=skip
  RESULT[LAUNCH_AGENT_TARGET_CLEANED]=skip
  RESULT[ACCEPTANCE_PROCESS_REMAINING]=skip
  RESULT[ENVIRONMENT_RESTORED]=skip
}

finish_result() {
  if [[ "${RESULT[M14_003_RESULT]}" == "OPT_IN_REQUIRED" \
    || "${RESULT[M14_003_RESULT]}" == "BLOCKED" \
    || "${RESULT[M14_003_RESULT]}" == "TIMEOUT" ]]; then
    write_result
    return 0
  fi

  local pass="yes"
  for key in \
    EXPLICIT_OPT_IN_CONFIRMED USER_SCOPE_ONLY COLLISION_CHECK_PASSED RELEASE_APP_BUILT \
    APP_INSTALLED LAUNCH_AGENT_INSTALLED INITIAL_XPC_CONNECTED \
    APP_EXIT_LEFT_SERVICE_RUNNING APP_RELAUNCHED_BEFORE_SLEEP PRE_SLEEP_RECONNECT_SUCCEEDED \
    WAITING_FOR_MANUAL_SLEEP REAL_SLEEP_DETECTED REAL_WAKE_DETECTED \
    SERVICE_RUNNING_AFTER_WAKE XPC_CONNECTED_AFTER_WAKE APP_RECONNECTED_AFTER_WAKE \
    SERVICE_OWNS_RUNTIME_AFTER_WAKE FINAL_SERVICE_RESTARTED FINAL_RECONNECT_SUCCEEDED \
    APP_TARGET_CLEANED LAUNCH_AGENT_TARGET_CLEANED ENVIRONMENT_RESTORED; do
    [[ "${RESULT[$key]}" == "yes" ]] || pass="no"
  done
  [[ "${RESULT[PRE_SLEEP_RESTART_CYCLES_EXPECTED]}" == "5" ]] || pass="no"
  [[ "${RESULT[PRE_SLEEP_RESTART_CYCLES_PASSED]}" == "5" ]] || pass="no"
  for key in \
    APP_OWNS_RUNTIME_AFTER_WAKE DUPLICATE_SERVICE_INSTANCE_FOUND WAKE_TIMEOUT_OCCURRED \
    SUDO_USED BROAD_PROCESS_KILL_USED REAL_HERMES_HOME_MODIFIED \
    ACCEPTANCE_PROCESS_REMAINING GENERATED_ARTIFACT_TRACKED_BY_GIT; do
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
  RESULT[M14_003_RESULT]=$([[ "$pass" == "yes" ]] && print -r -- PASS || print -r -- FAIL)
  write_result
}

fail() {
  print -u2 "error: $*"
  RESULT[M14_003_RESULT]=FAIL
  exit 1
}

timeout_fail() {
  print -u2 "timeout: $*"
  RESULT[WAKE_TIMEOUT_OCCURRED]=yes
  RESULT[M14_003_RESULT]=TIMEOUT
  exit 4
}

write_real_home_integrity_snapshot() {
  local output="$1"
  /usr/bin/python3 - "$HOME" "$output" <<'PY'
import fnmatch
import os
import stat
import sys
from pathlib import Path

home = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2])
protected = [
    ("hermes-home", home / ".hermes", True),
    ("application-support", home / "Library" / "Application Support" / "HermesBridge", True),
    ("caches", home / "Library" / "Caches" / "HermesBridge", True),
    ("logs", home / "Library" / "Logs" / "HermesBridge", True),
    ("preferences", home / "Library" / "Preferences", False),
]

def mode_type(mode: int) -> str:
    if stat.S_ISDIR(mode): return "dir"
    if stat.S_ISREG(mode): return "file"
    if stat.S_ISLNK(mode): return "symlink"
    if stat.S_ISFIFO(mode): return "fifo"
    if stat.S_ISSOCK(mode): return "socket"
    if stat.S_ISCHR(mode): return "char"
    if stat.S_ISBLK(mode): return "block"
    return "other"

def row(category: str, root: Path, path: Path) -> str:
    st = os.lstat(path)
    rel = "." if path == root else path.relative_to(root).as_posix()
    return "\t".join([
        category, rel, mode_type(st.st_mode), str(st.st_size),
        str(int(st.st_mtime_ns)), oct(stat.S_IMODE(st.st_mode)),
        str(st.st_uid), str(st.st_gid),
    ])

rows = []
for category, root, recursive in protected:
    try:
        if category == "preferences":
            if root.exists() and not root.is_symlink():
                for child in sorted(root.iterdir(), key=lambda p: p.name):
                    if fnmatch.fnmatch(child.name, "com.hermes*.plist"):
                        rows.append(row(category, root, child))
            continue
        if not root.exists() and not root.is_symlink():
            rows.append("\t".join([category, ".", "absent", "0", "0", "0", "0", "0"]))
            continue
        rows.append(row(category, root, root))
        if recursive and not root.is_symlink() and root.is_dir():
            for current, dirs, files in os.walk(root, followlinks=False):
                current_path = Path(current)
                kept_dirs = []
                for name in sorted(dirs):
                    child = current_path / name
                    rows.append(row(category, root, child))
                    if not child.is_symlink():
                        kept_dirs.append(name)
                dirs[:] = kept_dirs
                for name in sorted(files):
                    rows.append(row(category, root, current_path / name))
    except (FileNotFoundError, PermissionError, OSError):
        rows.append("\t".join([category, ".", "unavailable", "0", "0", "0", "0", "0"]))

output.parent.mkdir(parents=True, exist_ok=True)
output.write_text("\n".join(rows) + "\n", encoding="utf-8")
PY
}

compare_real_home_integrity_snapshot() {
  write_real_home_integrity_snapshot "$INTEGRITY_AFTER"
  /usr/bin/python3 - "$INTEGRITY_BEFORE" "$INTEGRITY_AFTER" "$INTEGRITY_CHANGES" <<'PY'
import sys
from pathlib import Path

before_path, after_path, changes_path = map(Path, sys.argv[1:4])
before = before_path.read_text(encoding="utf-8").splitlines()
after = after_path.read_text(encoding="utf-8").splitlines()

def keyed(lines):
    result = {}
    for line in lines:
        parts = line.split("\t")
        if len(parts) >= 5:
            result[(parts[0], parts[1])] = {
                "type": parts[2], "size": parts[3], "mtime_ns": parts[4], "line": line,
            }
    return result

b = keyed(before)
a = keyed(after)
changes = []
for key in sorted(set(b) | set(a)):
    if b.get(key) != a.get(key):
        category, rel = key
        before_row = b.get(key, {"type": "absent", "size": "0", "mtime_ns": "0"})
        after_row = a.get(key, {"type": "absent", "size": "0", "mtime_ns": "0"})
        changes.append("\t".join([
            f"{category}/{rel}", before_row["type"], after_row["type"],
            before_row["size"], after_row["size"],
            before_row["mtime_ns"], after_row["mtime_ns"],
        ]))
changes_path.write_text("\n".join(changes) + ("\n" if changes else ""), encoding="utf-8")
sys.exit(1 if changes else 0)
PY
}

set_real_home_modified_result() {
  if compare_real_home_integrity_snapshot; then
    RESULT[REAL_HERMES_HOME_MODIFIED]=no
  else
    RESULT[REAL_HERMES_HOME_MODIFIED]=yes
  fi
}

isolated_env_prefix() {
  HOME="$ISOLATED_HOME" \
  CFFIXED_USER_HOME="$ISOLATED_HOME" \
  HERMES_HOME="$ISOLATED_HERMES_HOME" \
  XDG_CONFIG_HOME="$ISOLATED_XDG_CONFIG_HOME" \
  XDG_CACHE_HOME="$ISOLATED_XDG_CACHE_HOME" \
  XDG_DATA_HOME="$ISOLATED_XDG_DATA_HOME" \
  XDG_STATE_HOME="$ISOLATED_XDG_STATE_HOME" \
  XDG_RUNTIME_DIR="$ISOLATED_XDG_RUNTIME_DIR" \
  "$@"
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
  trap - EXIT INT TERM HUP
  terminate_pid "$APP_PID"
  APP_PID=""

  if [[ "$SERVICE_BOOTSTRAPPED_BY_RUN" == "yes" ]]; then
    /bin/launchctl bootout "$SERVICE_DOMAIN" "$LAUNCH_AGENT_TARGET" >/dev/null 2>&1 || true
    SERVICE_BOOTSTRAPPED_BY_RUN="no"
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

  if [[ "$APP_INSTALLED_BY_RUN" == "no" \
    && "$LAUNCH_AGENT_INSTALLED_BY_RUN" == "no" \
    && "$SERVICE_BOOTSTRAPPED_BY_RUN" == "no" \
    && -z "$SERVICE_PID" ]]; then
    mark_pre_start_skips
    RESULT[REAL_HERMES_HOME_MODIFIED]=no
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

  set_real_home_modified_result
  RESULT[ENVIRONMENT_RESTORED]=$([[ "$residual" == "no" ]] && print -r -- yes || print -r -- no)
  finish_result
  FINISHED="yes"
}

trap cleanup EXIT
trap 'RESULT[M14_003_RESULT]=FAIL; exit 130' INT TERM HUP

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
    BLOCKED_REASON="production app target exists"
    RESULT[M14_003_RESULT]=BLOCKED
    return 1
  fi
  if [[ -e "$LAUNCH_AGENT_TARGET" || -L "$LAUNCH_AGENT_TARGET" ]]; then
    BLOCKED_REASON="production LaunchAgent target exists"
    RESULT[M14_003_RESULT]=BLOCKED
    return 1
  fi
  if /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1; then
    BLOCKED_REASON="production launchd label already loaded"
    RESULT[M14_003_RESULT]=BLOCKED
    return 1
  fi
  if [[ -n "$(pid_for_exact_executable "$SERVICE_EXECUTABLE" || true)" ]]; then
    BLOCKED_REASON="production service process already running"
    RESULT[M14_003_RESULT]=BLOCKED
    return 1
  fi
  if [[ -n "$(pid_for_exact_executable "$APP_EXECUTABLE" || true)" ]]; then
    BLOCKED_REASON="production app process already running"
    RESULT[M14_003_RESULT]=BLOCKED
    return 1
  fi
  RESULT[COLLISION_CHECK_PASSED]=yes
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
    RESULT[M14_003_RESULT]=BLOCKED
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
  RESULT[M14_003_RESULT]=BLOCKED
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
  cp "$ROOT_DIR/Packaging/HermesBridgeApp/Info.plist" "$RELEASE_APP/Contents/Info.plist" || return 1
  cp "$ROOT_DIR/Packaging/LaunchAgent/com.hermes.bridge.plist.template" \
    "$RELEASE_APP/Contents/Library/LaunchAgents/com.hermes.bridge.plist.template" || return 1
  chmod 755 "$RELEASE_APP_EXECUTABLE" "$RELEASE_SERVICE_EXECUTABLE" "$CONTROL_EXECUTABLE"
  /usr/bin/plutil -lint "$RELEASE_APP/Contents/Info.plist" >/dev/null || return 1
  RESULT[RELEASE_APP_BUILT]=yes
}

write_isolated_service_config() {
  mkdir -p "$HERMES_CONFIG_DIR" "$RUNTIME_DATA_ROOT" "$REQUEST_STATE_ROOT" "$LOGS_ROOT" \
    "$ISOLATED_HOME" "$ISOLATED_HERMES_HOME" "$ISOLATED_XDG_CONFIG_HOME" \
    "$ISOLATED_XDG_CACHE_HOME" "$ISOLATED_XDG_DATA_HOME" "$ISOLATED_XDG_STATE_HOME" \
    "$ISOLATED_XDG_RUNTIME_DIR"
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
        "startup": 8, "gracefulShutdown": 2, "forcedShutdown": 2, "gatewayReady": 4,
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

  /usr/bin/python3 - "$LAUNCH_AGENT_TARGET" "$SERVICE_EXECUTABLE" "$HERMES_CONFIG_FILE" \
    "$LOGS_ROOT" "$ISOLATED_HOME" "$ISOLATED_HERMES_HOME" "$ISOLATED_XDG_CONFIG_HOME" \
    "$ISOLATED_XDG_CACHE_HOME" "$ISOLATED_XDG_DATA_HOME" "$ISOLATED_XDG_STATE_HOME" \
    "$ISOLATED_XDG_RUNTIME_DIR" <<'PY'
import plistlib
import sys
from pathlib import Path

target, service, config, logs, home, hermes_home, xdg_config, xdg_cache, xdg_data, xdg_state, xdg_runtime = sys.argv[1:]
plist = {
    "Label": "com.hermes.bridge",
    "MachServices": {"com.hermes.bridge.xpc": True},
    "ProgramArguments": [service],
    "RunAtLoad": True,
    "KeepAlive": False,
    "ProcessType": "Background",
    "ThrottleInterval": 30,
    "EnvironmentVariables": {
        "HOME": home,
        "CFFIXED_USER_HOME": home,
        "HERMES_HOME": hermes_home,
        "HERMES_BRIDGE_SERVICE_CONFIG": config,
        "XDG_CONFIG_HOME": xdg_config,
        "XDG_CACHE_HOME": xdg_cache,
        "XDG_DATA_HOME": xdg_data,
        "XDG_STATE_HOME": xdg_state,
        "XDG_RUNTIME_DIR": xdg_runtime,
    },
    "StandardOutPath": str(Path(logs) / "service.stdout.log"),
    "StandardErrorPath": str(Path(logs) / "service.stderr.log"),
}
Path(target).write_bytes(plistlib.dumps(plist, fmt=plistlib.FMT_XML, sort_keys=True))
PY
  chmod 600 "$LAUNCH_AGENT_TARGET" || return 1
  /usr/bin/plutil -lint "$LAUNCH_AGENT_TARGET" >/dev/null || return 1
  LAUNCH_AGENT_INSTALLED_BY_RUN="yes"
  RESULT[LAUNCH_AGENT_INSTALLED]=yes
}

bootstrap_service() {
  /bin/launchctl bootstrap "$SERVICE_DOMAIN" "$LAUNCH_AGENT_TARGET" >/dev/null || return 1
  SERVICE_BOOTSTRAPPED_BY_RUN="yes"
  SERVICE_PID="$(wait_for_service_pid)" || return 1
}

verify_xpc_protocol() {
  local protocol_version
  protocol_version="$(isolated_env_prefix "$CONTROL_EXECUTABLE" protocol-version --timeout 10 | tr -d '\r\n')" || return 1
  print -r -- "protocolVersion=$protocol_version" > "$ARTIFACT_DIR/xpc-protocol.txt"
  [[ "$protocol_version" == "1.8" ]] || return 1
}

scan_runtime_ownership() {
  if rg -n 'HermesRuntimeSessionManager\(|HermesRuntimeEventBus\(|HermesRuntimeCommandAPI\(|HermesProcessSupervisor\(|HermesBackendAdapter\(|HermesProtocolClient\(' \
    "$ROOT_DIR/Sources/HermesBridgeApp" >/dev/null; then
    RESULT[APP_OWNS_RUNTIME_AFTER_WAKE]=yes
  else
    RESULT[APP_OWNS_RUNTIME_AFTER_WAKE]=no
  fi
  if rg -n 'HermesBridgeCompositionRoot' "$ROOT_DIR/Sources/HermesBridgeService" >/dev/null; then
    RESULT[SERVICE_OWNS_RUNTIME_AFTER_WAKE]=yes
  fi
}

launch_app() {
  /usr/bin/open -n \
    --env "HOME=$ISOLATED_HOME" \
    --env "CFFIXED_USER_HOME=$ISOLATED_HOME" \
    --env "HERMES_HOME=$ISOLATED_HERMES_HOME" \
    --env "XDG_CONFIG_HOME=$ISOLATED_XDG_CONFIG_HOME" \
    --env "XDG_CACHE_HOME=$ISOLATED_XDG_CACHE_HOME" \
    --env "XDG_DATA_HOME=$ISOLATED_XDG_DATA_HOME" \
    --env "XDG_STATE_HOME=$ISOLATED_XDG_STATE_HOME" \
    --env "XDG_RUNTIME_DIR=$ISOLATED_XDG_RUNTIME_DIR" \
    "$APP_TARGET" || return 1
  APP_PID="$(wait_for_app_pid)" || return 1
}

reconnect_check() {
  isolated_env_prefix "$CONTROL_EXECUTABLE" capabilities --timeout 10 >/dev/null || return 1
  verify_xpc_protocol
}

controlled_service_restart() {
  local before_restart after_restart
  before_restart="$SERVICE_PID"
  /bin/launchctl bootout "$SERVICE_DOMAIN" "$LAUNCH_AGENT_TARGET" >/dev/null || return 1
  SERVICE_BOOTSTRAPPED_BY_RUN="no"
  /bin/launchctl bootstrap "$SERVICE_DOMAIN" "$LAUNCH_AGENT_TARGET" >/dev/null || return 1
  SERVICE_BOOTSTRAPPED_BY_RUN="yes"
  after_restart="$(wait_for_service_pid)" || return 1
  SERVICE_PID="$after_restart"
  [[ -n "$before_restart" ]] && [[ "$before_restart" != "$after_restart" ]] || return 1
}

perform_pre_sleep_restart_cycles() {
  local cycle
  for cycle in {1..5}; do
    controlled_service_restart || return 1
    [[ -n "$(service_pid_from_launchctl)" ]] || return 1
    verify_xpc_protocol || return 1
    scan_runtime_ownership
    [[ "${RESULT[SERVICE_OWNS_RUNTIME_AFTER_WAKE]}" == "yes" ]] || return 1
    [[ "${RESULT[APP_OWNS_RUNTIME_AFTER_WAKE]}" == "no" ]] || return 1
    reconnect_check || return 1
    RESULT[PRE_SLEEP_RESTART_CYCLES_PASSED]="$cycle"
  done
}

detect_duplicate_service_instance() {
  local pids
  pids=("${(@f)$(pid_for_exact_executable "$SERVICE_EXECUTABLE" || true)}")
  if (( ${#pids[@]} > 1 )); then
    RESULT[DUPLICATE_SERVICE_INSTANCE_FOUND]=yes
    return 1
  fi
  RESULT[DUPLICATE_SERVICE_INSTANCE_FOUND]=no
  return 0
}

write_sleep_wake_helper() {
  local helper="$ARTIFACT_DIR/SleepWakeProbe.swift"
  mkdir -p "$ARTIFACT_DIR"
  cat > "$helper" <<'SWIFT'
import AppKit
import Foundation

let timeout = TimeInterval(CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 900)
let startUptime = ProcessInfo.processInfo.systemUptime
let deadline = Date().addingTimeInterval(timeout)
var sawSleep = false
var sawWake = false
var sleepUptime: TimeInterval?
var wakeUptime: TimeInterval?

let center = NSWorkspace.shared.notificationCenter
let sleepObserver = center.addObserver(
  forName: NSWorkspace.willSleepNotification,
  object: nil,
  queue: .main
) { _ in
  sawSleep = true
  sleepUptime = ProcessInfo.processInfo.systemUptime
  FileHandle.standardOutput.write(Data("NSWorkspaceWillSleep=yes\n".utf8))
}
let wakeObserver = center.addObserver(
  forName: NSWorkspace.didWakeNotification,
  object: nil,
  queue: .main
) { _ in
  sawWake = true
  wakeUptime = ProcessInfo.processInfo.systemUptime
  FileHandle.standardOutput.write(Data("NSWorkspaceDidWake=yes\n".utf8))
  CFRunLoopStop(CFRunLoopGetMain())
}

Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
  if Date() >= deadline {
    CFRunLoopStop(CFRunLoopGetMain())
  }
}

CFRunLoopRun()
center.removeObserver(sleepObserver)
center.removeObserver(wakeObserver)

let endUptime = ProcessInfo.processInfo.systemUptime
let sleepToWakeUptime = (wakeUptime ?? endUptime) - (sleepUptime ?? startUptime)
print("START_UPTIME=\(startUptime)")
print("END_UPTIME=\(endUptime)")
print("SLEEP_TO_WAKE_UPTIME_DELTA=\(sleepToWakeUptime)")
print("REAL_SLEEP_DETECTED=\(sawSleep ? "yes" : "no")")
print("REAL_WAKE_DETECTED=\(sawWake ? "yes" : "no")")
exit((sawSleep && sawWake && sleepToWakeUptime >= 0) ? 0 : 4)
SWIFT
  print -r -- "$helper"
}

wait_for_real_sleep_wake() {
  local checkpoint="$ARTIFACT_DIR/pre-sleep-checkpoint.txt"
  local evidence="$ARTIFACT_DIR/sleep-wake-evidence.txt"
  local helper
  {
    print -r -- "CHECKPOINT_MONOTONIC_UPTIME=$(sysctl -n kern.boottime 2>/dev/null || print -r -- unavailable)"
    print -r -- "SERVICE_PID=$SERVICE_PID"
    print -r -- "APP_PID=$APP_PID"
    isolated_env_prefix "$CONTROL_EXECUTABLE" protocol-version --timeout 10 2>/dev/null | sed 's/^/XPC_PROTOCOL=/'
  } > "$checkpoint"

  write_real_home_integrity_snapshot "$ARTIFACT_DIR/pre-sleep-real-home.snapshot"
  RESULT[WAITING_FOR_MANUAL_SLEEP]=yes
  write_result
  print -r -- "WAITING_FOR_MANUAL_SLEEP=yes"
  print -r -- "Manual action required: put this Mac to sleep, then wake it before ${WAKE_TIMEOUT_SECONDS}s elapse."

  helper="$(write_sleep_wake_helper)"
  if /usr/bin/swift "$helper" "$WAKE_TIMEOUT_SECONDS" > "$evidence"; then
    if grep -q '^REAL_SLEEP_DETECTED=yes$' "$evidence" \
      && grep -q '^REAL_WAKE_DETECTED=yes$' "$evidence"; then
      RESULT[REAL_SLEEP_DETECTED]=yes
      RESULT[REAL_WAKE_DETECTED]=yes
      RESULT[WAKE_TIMEOUT_OCCURRED]=no
      return 0
    fi
  fi
  RESULT[REAL_SLEEP_DETECTED]=no
  RESULT[REAL_WAKE_DETECTED]=no
  timeout_fail "real sleep/wake transition was not observed"
}

discover_agent_status() {
  local agent_status
  agent_status="$(isolated_env_prefix swift run --configuration release HermesReleaseAgentPreflight 2>/dev/null | tail -n 1 | tr -d '\r\n' || print -r -- unknown)"
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

post_wake_validation() {
  if ! /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1; then
    /bin/launchctl bootstrap "$SERVICE_DOMAIN" "$LAUNCH_AGENT_TARGET" >/dev/null || return 1
    SERVICE_BOOTSTRAPPED_BY_RUN="yes"
  fi
  SERVICE_PID="$(wait_for_service_pid)" || return 1
  RESULT[SERVICE_RUNNING_AFTER_WAKE]=yes
  verify_xpc_protocol || return 1
  RESULT[XPC_CONNECTED_AFTER_WAKE]=yes
  reconnect_check || return 1
  RESULT[APP_RECONNECTED_AFTER_WAKE]=yes
  scan_runtime_ownership
  detect_duplicate_service_instance || return 1
  controlled_service_restart || return 1
  RESULT[FINAL_SERVICE_RESTARTED]=yes
  reconnect_check || return 1
  RESULT[FINAL_RECONNECT_SUCCEEDED]=yes
}

main() {
  set_default_results
  mkdir -p "$ARTIFACT_DIR"
  write_real_home_integrity_snapshot "$INTEGRITY_BEFORE"
  write_result
  assert_user_scope || fail "user-scope policy failed"
  local collision="no"
  detect_collision || collision="yes"

  if [[ "${HERMES_SLEEP_WAKE_ACCEPTANCE:-}" != "YES" ]]; then
    RESULT[M14_003_RESULT]=OPT_IN_REQUIRED
    mark_pre_start_skips
    print -u2 "opt-in required: set HERMES_SLEEP_WAKE_ACCEPTANCE=YES to run real sleep/wake endurance acceptance"
    write_result
    exit 2
  fi

  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  if [[ "$collision" == "no" ]]; then
    acquire_acceptance_lock || collision="yes"
  fi
  if [[ "$collision" == "yes" ]]; then
    RESULT[M14_003_RESULT]=BLOCKED
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
  verify_xpc_protocol || fail "initial XPC protocol 1.8 check failed"
  RESULT[INITIAL_XPC_CONNECTED]=yes
  scan_runtime_ownership
  discover_agent_status

  perform_pre_sleep_restart_cycles || fail "pre-sleep restart endurance failed"
  terminate_pid "$APP_PID"
  APP_PID=""
  if [[ -n "$(service_pid_from_launchctl)" ]]; then
    RESULT[APP_EXIT_LEFT_SERVICE_RUNNING]=yes
  fi
  launch_app || fail "app relaunch before sleep failed"
  RESULT[APP_RELAUNCHED_BEFORE_SLEEP]=yes
  reconnect_check && RESULT[PRE_SLEEP_RECONNECT_SUCCEEDED]=yes || fail "pre-sleep reconnect failed"

  wait_for_real_sleep_wake
  post_wake_validation || fail "post-wake validation failed"

  cleanup
  finish_result
  FINISHED="yes"
  result_exit_code
}

main "$@"
