#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT_NAME="$0"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m14-003"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
RELEASE_ROOT="$ARTIFACT_DIR/release"
RUNTIME_ROOT="$ARTIFACT_DIR/runtime"
CHECKPOINT_FILE="$RUNTIME_ROOT/checkpoint.json"
EVIDENCE_FILE="$RUNTIME_ROOT/wake-recorder-evidence.jsonl"
RECORDER_SOURCE="$RUNTIME_ROOT/SleepWakeRecorder.swift"
RECORDER_LABEL_PREFIX="com.hermes.bridge.m14-003.wake-recorder"
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
APP_TARGET_REL="Applications/$APP_NAME"
LAUNCH_AGENT_TARGET_REL="Library/LaunchAgents/com.hermes.bridge.plist"
APP_TARGET="$HOME/$APP_TARGET_REL"
LAUNCH_AGENT_TARGET="$HOME/$LAUNCH_AGENT_TARGET_REL"
APP_EXECUTABLE_REL="$APP_TARGET_REL/Contents/MacOS/HermesBridgeApp"
SERVICE_EXECUTABLE_REL="$APP_TARGET_REL/Contents/Library/HermesBridge/HermesBridgeService"
APP_EXECUTABLE="$HOME/$APP_EXECUTABLE_REL"
SERVICE_EXECUTABLE="$HOME/$SERVICE_EXECUTABLE_REL"
CONTROL_EXECUTABLE="$RELEASE_ROOT/bin/HermesBridgeControl"
RELEASE_APP="$RELEASE_ROOT/$APP_NAME"
RELEASE_APP_EXECUTABLE="$RELEASE_APP/Contents/MacOS/HermesBridgeApp"
RELEASE_SERVICE_EXECUTABLE="$RELEASE_APP/Contents/Library/HermesBridge/HermesBridgeService"
LABEL="com.hermes.bridge"
MACH_SERVICE="com.hermes.bridge.xpc"
SERVICE_DOMAIN="gui/$(id -u)"
REAL_HERMES_HOME="$HOME/.hermes"
RUN_ID="${HERMES_M14_003_RUN_ID:-m14-003-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
RECORDER_LABEL="$RECORDER_LABEL_PREFIX.$RUN_ID"
RECORDER_PLIST_REL="Library/LaunchAgents/$RECORDER_LABEL.plist"
RECORDER_PLIST="$HOME/$RECORDER_PLIST_REL"
ACCEPTANCE_LOCK_DIR="${TMPDIR:-/tmp}/com.hermes.bridge.m14-003.acceptance.lock"
ACCEPTANCE_LOCK_OWNED="no"
BLOCKED_REASON=""
WAKE_TIMEOUT_SECONDS="${HERMES_M14_003_WAKE_TIMEOUT_SECONDS:-900}"
RESTART_CYCLES_EXPECTED=5

typeset -A RESULT
APP_INSTALLED_BY_RUN="no"
LAUNCH_AGENT_INSTALLED_BY_RUN="no"
SERVICE_BOOTSTRAPPED_BY_RUN="no"
RECORDER_BOOTSTRAPPED_BY_RUN="no"
APP_PID=""
SERVICE_PID=""
RECORDER_PID=""
INTEGRITY_BEFORE="$RUNTIME_ROOT/real-home-before.snapshot"
INTEGRITY_AFTER="$RUNTIME_ROOT/real-home-after.snapshot"
INTEGRITY_CHANGES="$RUNTIME_ROOT/real-home-changes.txt"
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

usage() {
  print -u2 "usage: $SCRIPT_NAME prepare|resume|cleanup"
  print -u2 "prepare and resume require HERMES_SLEEP_WAKE_ACCEPTANCE=YES"
}

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
    APP_TARGET_CLEANED skip
    LAUNCH_AGENT_TARGET_CLEANED skip
    ACCEPTANCE_PROCESS_REMAINING skip
    ENVIRONMENT_RESTORED skip
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
    WAITING) return 5 ;;
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
    || "${RESULT[M14_003_RESULT]}" == "TIMEOUT" \
    || "${RESULT[M14_003_RESULT]}" == "WAITING" ]]; then
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

require_opt_in() {
  if [[ "${HERMES_SLEEP_WAKE_ACCEPTANCE:-}" != "YES" ]]; then
    RESULT[M14_003_RESULT]=OPT_IN_REQUIRED
    mark_pre_start_skips
    print -u2 "opt-in required: set HERMES_SLEEP_WAKE_ACCEPTANCE=YES to run real sleep/wake endurance acceptance"
    write_result
    exit 2
  fi
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
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
  if [[ -r "$INTEGRITY_BEFORE" ]] && compare_real_home_integrity_snapshot; then
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

pid_from_launchctl_label() {
  local label="$1"
  /bin/launchctl print "$SERVICE_DOMAIN/$label" 2>/dev/null \
    | awk -F= '/^[[:space:]]*pid = / { gsub(/[[:space:]]/, "", $2); print $2; exit }'
}

service_pid_from_launchctl() {
  pid_from_launchctl_label "$LABEL"
}

recorder_pid_from_launchctl() {
  pid_from_launchctl_label "$RECORDER_LABEL"
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

assert_user_scope() {
  case "$APP_TARGET" in
    "$HOME/Applications/"*) ;;
    *) return 1 ;;
  esac
  case "$LAUNCH_AGENT_TARGET" in
    "$HOME/Library/LaunchAgents/"*) ;;
    *) return 1 ;;
  esac
  case "$RECORDER_PLIST" in
    "$HOME/Library/LaunchAgents/"*) ;;
    *) return 1 ;;
  esac
  [[ "$APP_TARGET" != "/Applications/"* ]] || return 1
  [[ "$LAUNCH_AGENT_TARGET" == *"/$LABEL.plist" ]] || return 1
  [[ "$RECORDER_LABEL" == "$RECORDER_LABEL_PREFIX."* ]] || return 1
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
  if [[ -e "$RECORDER_PLIST" || -L "$RECORDER_PLIST" ]]; then
    BLOCKED_REASON="wake recorder LaunchAgent target exists"
    RESULT[M14_003_RESULT]=BLOCKED
    return 1
  fi
  if /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1; then
    BLOCKED_REASON="production launchd label already loaded"
    RESULT[M14_003_RESULT]=BLOCKED
    return 1
  fi
  if /bin/launchctl print "$SERVICE_DOMAIN/$RECORDER_LABEL" >/dev/null 2>&1; then
    BLOCKED_REASON="wake recorder launchd label already loaded"
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

write_checkpoint() {
  local phase="$1"
  local status="$2"
  mkdir -p "$RUNTIME_ROOT"
  /usr/bin/python3 - "$CHECKPOINT_FILE" "$RUN_ID" "$phase" "$status" \
    "$LABEL" "$RECORDER_LABEL" "$APP_TARGET_REL" "$LAUNCH_AGENT_TARGET_REL" "$RECORDER_PLIST_REL" \
    "$APP_EXECUTABLE_REL" "$SERVICE_EXECUTABLE_REL" "$APP_PID" "$SERVICE_PID" "$RECORDER_PID" \
    "$APP_INSTALLED_BY_RUN" "$LAUNCH_AGENT_INSTALLED_BY_RUN" "$SERVICE_BOOTSTRAPPED_BY_RUN" \
    "$RECORDER_BOOTSTRAPPED_BY_RUN" "$RESTART_CYCLES_EXPECTED" <<'PY'
import json
import sys
from pathlib import Path

(
    path, run_id, phase, status, service_label, recorder_label, app_target_rel,
    launch_agent_target_rel, recorder_plist_rel, app_executable_rel,
    service_executable_rel, app_pid, service_pid, recorder_pid, app_installed,
    launch_agent_installed, service_bootstrapped, recorder_bootstrapped,
    restart_cycles_expected,
) = sys.argv[1:]
checkpoint = {
    "schemaVersion": 1,
    "runIdentifier": run_id,
    "phase": phase,
    "status": status,
    "createdAtMonotonicUptime": None,
    "updatedAtEpochSeconds": None,
    "serviceDomain": "gui/current-user",
    "serviceLabel": service_label,
    "recorderLabel": recorder_label,
    "targets": {
        "app": app_target_rel,
        "launchAgent": launch_agent_target_rel,
        "recorderLaunchAgent": recorder_plist_rel,
        "appExecutable": app_executable_rel,
        "serviceExecutable": service_executable_rel,
    },
    "ownedPids": {
        "app": int(app_pid) if app_pid.isdigit() else None,
        "service": int(service_pid) if service_pid.isdigit() else None,
        "recorder": int(recorder_pid) if recorder_pid.isdigit() else None,
    },
    "ownership": {
        "appInstalledByRun": app_installed == "yes",
        "launchAgentInstalledByRun": launch_agent_installed == "yes",
        "serviceBootstrappedByRun": service_bootstrapped == "yes",
        "recorderBootstrappedByRun": recorder_bootstrapped == "yes",
    },
    "restartCyclesExpected": int(restart_cycles_expected),
    "resultFile": "artifacts/m14-003/result.txt",
    "runtimeRoot": "artifacts/m14-003/runtime",
    "wakeEvidence": "artifacts/m14-003/runtime/wake-recorder-evidence.jsonl",
    "realHomeSnapshotBefore": "artifacts/m14-003/runtime/real-home-before.snapshot",
}
Path(path).write_text(json.dumps(checkpoint, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
  /usr/bin/python3 - "$CHECKPOINT_FILE" <<'PY'
import json
import subprocess
import sys
import time
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
try:
    uptime = float(subprocess.check_output(["/usr/bin/python3", "-c", "import time; print(time.monotonic())"], text=True).strip())
except Exception:
    uptime = None
data["createdAtMonotonicUptime"] = data.get("createdAtMonotonicUptime") or uptime
data["updatedAtEpochSeconds"] = int(time.time())
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

load_checkpoint() {
  [[ -r "$CHECKPOINT_FILE" ]] || return 1
  local assignments
  assignments="$(/usr/bin/python3 - "$CHECKPOINT_FILE" <<'PY'
import json
import shlex
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
required = [
    ("runIdentifier", str),
    ("phase", str),
    ("status", str),
    ("serviceLabel", str),
    ("recorderLabel", str),
    ("targets", dict),
    ("ownedPids", dict),
    ("ownership", dict),
]
for key, expected in required:
    if key not in data or not isinstance(data[key], expected):
        raise SystemExit(f"invalid checkpoint: {key}")
targets = data["targets"]
for key in ["app", "launchAgent", "recorderLaunchAgent", "appExecutable", "serviceExecutable"]:
    value = targets.get(key)
    if not isinstance(value, str) or value.startswith("/") or ".." in value.split("/"):
        raise SystemExit(f"invalid relative target: {key}")
if data["serviceLabel"] != "com.hermes.bridge":
    raise SystemExit("invalid service label")
if not data["recorderLabel"].startswith("com.hermes.bridge.m14-003.wake-recorder."):
    raise SystemExit("invalid recorder label")
owned = data["ownedPids"]
ownership = data["ownership"]
def emit(name, value):
    print(f"{name}={shlex.quote(str(value))}")
emit("RUN_ID", data["runIdentifier"])
emit("RECORDER_LABEL", data["recorderLabel"])
emit("RECORDER_PLIST_REL", targets["recorderLaunchAgent"])
emit("APP_PID", "" if owned.get("app") is None else owned["app"])
emit("SERVICE_PID", "" if owned.get("service") is None else owned["service"])
emit("RECORDER_PID", "" if owned.get("recorder") is None else owned["recorder"])
emit("APP_INSTALLED_BY_RUN", "yes" if ownership.get("appInstalledByRun") else "no")
emit("LAUNCH_AGENT_INSTALLED_BY_RUN", "yes" if ownership.get("launchAgentInstalledByRun") else "no")
emit("SERVICE_BOOTSTRAPPED_BY_RUN", "yes" if ownership.get("serviceBootstrappedByRun") else "no")
emit("RECORDER_BOOTSTRAPPED_BY_RUN", "yes" if ownership.get("recorderBootstrappedByRun") else "no")
PY
)" || return 1
  eval "$assignments"
  RECORDER_PLIST="$HOME/$RECORDER_PLIST_REL"
  return 0
}

checkpoint_field() {
  local field="$1"
  /usr/bin/python3 - "$CHECKPOINT_FILE" "$field" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
value = data
for part in sys.argv[2].split("."):
    value = value[part]
print(value)
PY
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

write_sleep_wake_recorder() {
  mkdir -p "$RUNTIME_ROOT"
  cat > "$RECORDER_SOURCE" <<'SWIFT'
import AppKit
import Foundation

struct Event: Encodable {
  let schemaVersion: Int
  let runIdentifier: String
  let recorderLabel: String
  let event: String
  let pid: Int32
  let monotonicUptime: TimeInterval
  let wallClockEpochSeconds: TimeInterval
}

let args = CommandLine.arguments
guard args.count == 6 else {
  exit(64)
}
let runIdentifier = args[1]
let recorderLabel = args[2]
let evidencePath = args[3]
let pidPath = args[4]
let lifetime = TimeInterval(args[5]) ?? 900
let started = Date()
let deadline = started.addingTimeInterval(lifetime)
var sawSleep = false
var sawWake = false
var sleepUptime: TimeInterval?
var wakeUptime: TimeInterval?
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]

func append(_ event: String) {
  let payload = Event(
    schemaVersion: 1,
    runIdentifier: runIdentifier,
    recorderLabel: recorderLabel,
    event: event,
    pid: getpid(),
    monotonicUptime: ProcessInfo.processInfo.systemUptime,
    wallClockEpochSeconds: CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970
  )
  guard let data = try? encoder.encode(payload) else { return }
  let url = URL(fileURLWithPath: evidencePath)
  FileManager.default.createFile(atPath: evidencePath, contents: nil)
  if let handle = try? FileHandle(forWritingTo: url) {
    defer { try? handle.close() }
    try? handle.seekToEnd()
    try? handle.write(contentsOf: data)
    try? handle.write(contentsOf: Data("\n".utf8))
  }
}

try? "\(getpid())\n".write(toFile: pidPath, atomically: true, encoding: .utf8)
append("recorder-started")

let center = NSWorkspace.shared.notificationCenter
let sleepObserver = center.addObserver(
  forName: NSWorkspace.willSleepNotification,
  object: nil,
  queue: .main
) { _ in
  sawSleep = true
  sleepUptime = ProcessInfo.processInfo.systemUptime
  append("NSWorkspaceWillSleep")
}
let wakeObserver = center.addObserver(
  forName: NSWorkspace.didWakeNotification,
  object: nil,
  queue: .main
) { _ in
  sawWake = true
  wakeUptime = ProcessInfo.processInfo.systemUptime
  append("NSWorkspaceDidWake")
  CFRunLoopStop(CFRunLoopGetMain())
}

Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
  if Date() >= deadline {
    append("recorder-timeout")
    CFRunLoopStop(CFRunLoopGetMain())
  }
}

CFRunLoopRun()
center.removeObserver(sleepObserver)
center.removeObserver(wakeObserver)

let startUptime = sleepUptime ?? ProcessInfo.processInfo.systemUptime
let endUptime = wakeUptime ?? ProcessInfo.processInfo.systemUptime
append("recorder-finished")
exit((sawSleep && sawWake && endUptime >= startUptime) ? 0 : 4)
SWIFT
}

install_recorder_launch_agent() {
  write_sleep_wake_recorder
  rm -f "$EVIDENCE_FILE" "$RUNTIME_ROOT/wake-recorder.pid"
  /usr/bin/python3 - "$RECORDER_PLIST" "$RECORDER_LABEL" "$RECORDER_SOURCE" "$RUN_ID" \
    "$EVIDENCE_FILE" "$RUNTIME_ROOT/wake-recorder.pid" "$WAKE_TIMEOUT_SECONDS" "$LOGS_ROOT" <<'PY'
import plistlib
import sys
from pathlib import Path
target, label, source, run_id, evidence, pid_path, timeout, logs = sys.argv[1:]
Path(target).parent.mkdir(parents=True, exist_ok=True)
Path(logs).mkdir(parents=True, exist_ok=True)
plist = {
    "Label": label,
    "ProgramArguments": ["/usr/bin/swift", source, run_id, label, evidence, pid_path, timeout],
    "RunAtLoad": True,
    "KeepAlive": False,
    "ProcessType": "Background",
    "StandardOutPath": str(Path(logs) / "wake-recorder.stdout.log"),
    "StandardErrorPath": str(Path(logs) / "wake-recorder.stderr.log"),
}
Path(target).write_bytes(plistlib.dumps(plist, fmt=plistlib.FMT_XML, sort_keys=True))
PY
  chmod 600 "$RECORDER_PLIST" || return 1
  /usr/bin/plutil -lint "$RECORDER_PLIST" >/dev/null || return 1
  /bin/launchctl bootstrap "$SERVICE_DOMAIN" "$RECORDER_PLIST" >/dev/null || return 1
  RECORDER_BOOTSTRAPPED_BY_RUN="yes"
  local deadline=$(( $(date +%s) + 20 ))
  while [[ $(date +%s) -lt $deadline ]]; do
    RECORDER_PID="$(recorder_pid_from_launchctl)"
    if [[ -z "$RECORDER_PID" && -r "$RUNTIME_ROOT/wake-recorder.pid" ]]; then
      RECORDER_PID="$(head -n 1 "$RUNTIME_ROOT/wake-recorder.pid" 2>/dev/null | tr -cd '0-9')"
    fi
    if [[ -n "$RECORDER_PID" ]] && kill -0 "$RECORDER_PID" 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

verify_recorder_evidence() {
  /usr/bin/python3 - "$CHECKPOINT_FILE" "$EVIDENCE_FILE" <<'PY'
import json
import sys
from pathlib import Path
checkpoint = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
run_id = checkpoint["runIdentifier"]
label = checkpoint["recorderLabel"]
path = Path(sys.argv[2])
if not path.exists():
    raise SystemExit("missing wake evidence")
events = []
for line in path.read_text(encoding="utf-8").splitlines():
    if line.strip():
        event = json.loads(line)
        if event.get("runIdentifier") != run_id:
            raise SystemExit("wrong run identifier")
        if event.get("recorderLabel") != label:
            raise SystemExit("wrong recorder label")
        if not isinstance(event.get("pid"), int):
            raise SystemExit("missing exact recorder pid")
        if not isinstance(event.get("monotonicUptime"), (int, float)):
            raise SystemExit("missing monotonic evidence")
        events.append(event)
names = [event.get("event") for event in events]
if "NSWorkspaceWillSleep" not in names:
    raise SystemExit("will-sleep evidence required")
if "NSWorkspaceDidWake" not in names:
    raise SystemExit("did-wake evidence required")
sleep = next(event for event in events if event.get("event") == "NSWorkspaceWillSleep")
wake = next(event for event in events if event.get("event") == "NSWorkspaceDidWake")
if wake["monotonicUptime"] < sleep["monotonicUptime"]:
    raise SystemExit("wake uptime precedes sleep uptime")
if sleep.get("wallClockEpochSeconds") is not None and wake.get("wallClockEpochSeconds") is not None:
    pass
else:
    raise SystemExit("wall clock may be present but cannot be sole evidence")
PY
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

cleanup_owned_state() {
  trap - EXIT INT TERM HUP
  [[ -r "$CHECKPOINT_FILE" ]] && load_checkpoint || true

  terminate_pid "$APP_PID"
  APP_PID=""

  if [[ -n "$RECORDER_LABEL" ]]; then
    /bin/launchctl bootout "$SERVICE_DOMAIN" "$RECORDER_PLIST" >/dev/null 2>&1 || true
    RECORDER_BOOTSTRAPPED_BY_RUN="no"
  fi
  if [[ -n "$RECORDER_PID" ]]; then
    terminate_pid "$RECORDER_PID"
    RECORDER_PID=""
  fi
  if [[ -n "$RECORDER_PLIST" && -e "$RECORDER_PLIST" ]]; then
    rm -f "$RECORDER_PLIST"
  fi

  if [[ "$SERVICE_BOOTSTRAPPED_BY_RUN" == "yes" || -e "$LAUNCH_AGENT_TARGET" ]]; then
    /bin/launchctl bootout "$SERVICE_DOMAIN" "$LAUNCH_AGENT_TARGET" >/dev/null 2>&1 || true
    SERVICE_BOOTSTRAPPED_BY_RUN="no"
  fi
  if [[ "$LAUNCH_AGENT_INSTALLED_BY_RUN" == "yes" && -e "$LAUNCH_AGENT_TARGET" ]]; then
    rm -f "$LAUNCH_AGENT_TARGET"
  fi
  if [[ "$APP_INSTALLED_BY_RUN" == "yes" && -e "$APP_TARGET" ]]; then
    rm -rf "$APP_TARGET"
  fi
  if [[ "$ACCEPTANCE_LOCK_OWNED" == "yes" || -d "$ACCEPTANCE_LOCK_DIR" ]]; then
    rm -rf "$ACCEPTANCE_LOCK_DIR"
    ACCEPTANCE_LOCK_OWNED="no"
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
  if [[ -n "$RECORDER_LABEL" ]] && /bin/launchctl print "$SERVICE_DOMAIN/$RECORDER_LABEL" >/dev/null 2>&1; then
    residual="yes"
  fi
  RESULT[ACCEPTANCE_PROCESS_REMAINING]="$residual"

  set_real_home_modified_result
  RESULT[ENVIRONMENT_RESTORED]=$([[ "$residual" == "no" ]] && print -r -- yes || print -r -- no)
  write_checkpoint "cleanup" "cleaned" 2>/dev/null || true
}

cleanup() {
  cleanup_owned_state
  finish_result
  FINISHED="yes"
}

trap cleanup EXIT
trap 'RESULT[M14_003_RESULT]=FAIL; exit 130' INT TERM HUP

prepare() {
  set_default_results
  mkdir -p "$ARTIFACT_DIR" "$RUNTIME_ROOT"
  write_real_home_integrity_snapshot "$INTEGRITY_BEFORE"
  write_result
  assert_user_scope || fail "user-scope policy failed"
  require_opt_in
  acquire_acceptance_lock || {
    RESULT[M14_003_RESULT]=BLOCKED
    mark_pre_start_skips
    print -u2 "blocked: $BLOCKED_REASON"
    write_result
    exit 3
  }
  detect_collision || {
    RESULT[M14_003_RESULT]=BLOCKED
    mark_pre_start_skips
    print -u2 "blocked: $BLOCKED_REASON"
    write_result
    exit 3
  }

  write_checkpoint "prepare" "started"
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

  install_recorder_launch_agent || fail "wake recorder launch failed"
  write_checkpoint "prepare" "waiting-for-manual-sleep"
  RESULT[WAITING_FOR_MANUAL_SLEEP]=yes
  RESULT[M14_003_RESULT]=WAITING
  finish_result
  print -r -- "WAITING_FOR_MANUAL_SLEEP=yes"
  print -r -- "M14_003_RESULT=WAITING"
  print -r -- "Manual action required: put this Mac to sleep, wake/login, then run resume."
  trap - EXIT INT TERM HUP
  FINISHED="yes"
  exit 5
}

resume() {
  set_default_results
  mkdir -p "$ARTIFACT_DIR" "$RUNTIME_ROOT"
  require_opt_in
  load_checkpoint || fail "missing or invalid durable checkpoint"
  local checkpoint_run_id checkpoint_status
  checkpoint_run_id="$(checkpoint_field runIdentifier)"
  checkpoint_status="$(checkpoint_field status)"
  [[ "$checkpoint_run_id" == "$RUN_ID" ]] || fail "checkpoint run identifier mismatch"
  [[ "$checkpoint_status" == "waiting-for-manual-sleep" ]] || fail "stale or duplicate resume checkpoint"
  write_checkpoint "resume" "resuming"

  RESULT[USER_SCOPE_ONLY]=yes
  RESULT[COLLISION_CHECK_PASSED]=yes
  RESULT[RELEASE_APP_BUILT]=yes
  RESULT[APP_INSTALLED]=$APP_INSTALLED_BY_RUN
  RESULT[LAUNCH_AGENT_INSTALLED]=$LAUNCH_AGENT_INSTALLED_BY_RUN
  RESULT[INITIAL_XPC_CONNECTED]=yes
  RESULT[PRE_SLEEP_RESTART_CYCLES_PASSED]=5
  RESULT[APP_EXIT_LEFT_SERVICE_RUNNING]=yes
  RESULT[APP_RELAUNCHED_BEFORE_SLEEP]=yes
  RESULT[PRE_SLEEP_RECONNECT_SUCCEEDED]=yes
  RESULT[WAITING_FOR_MANUAL_SLEEP]=yes

  verify_recorder_evidence || timeout_fail "genuine sleep/wake evidence was not recorded"
  RESULT[REAL_SLEEP_DETECTED]=yes
  RESULT[REAL_WAKE_DETECTED]=yes
  RESULT[WAKE_TIMEOUT_OCCURRED]=no

  if [[ -z "$(pid_for_exact_executable "$APP_EXECUTABLE" || true)" ]]; then
    launch_app || fail "app relaunch after wake failed"
  fi
  post_wake_validation || fail "post-wake validation failed"
  discover_agent_status
  cleanup
  finish_result
  FINISHED="yes"
  result_exit_code
  exit $?
}

cleanup_command() {
  set_default_results
  mkdir -p "$ARTIFACT_DIR" "$RUNTIME_ROOT"
  RESULT[USER_SCOPE_ONLY]=yes
  [[ -r "$CHECKPOINT_FILE" ]] && load_checkpoint || true
  cleanup_owned_state
  RESULT[M14_003_RESULT]=$([[ "${RESULT[ENVIRONMENT_RESTORED]}" == "yes" ]] && print -r -- PASS || print -r -- FAIL)
  write_result
  result_exit_code
  exit $?
}

main() {
  local command="${1:-}"
  case "$command" in
    prepare)
      prepare
      ;;
    resume)
      resume
      ;;
    cleanup)
      cleanup_command
      ;;
    "")
      set_default_results
      mkdir -p "$ARTIFACT_DIR"
      RESULT[M14_003_RESULT]=OPT_IN_REQUIRED
      mark_pre_start_skips
      write_result
      usage
      exit 2
      ;;
    *)
      set_default_results
      mkdir -p "$ARTIFACT_DIR"
      RESULT[M14_003_RESULT]=FAIL
      mark_pre_start_skips
      write_result
      usage
      exit 1
      ;;
  esac
}

main "$@"
