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
POWER_LOG_EVIDENCE_FILE="$RUNTIME_ROOT/system-power-log-evidence.json"
POWER_LOG_COMMAND="/usr/bin/pmset"
PHASE_MARKERS_FILE="$RUNTIME_ROOT/phase-markers.jsonl"
RECORDER_READY_FILE="$RUNTIME_ROOT/wake-recorder-ready.json"
RECORDER_PID_FILE="$RUNTIME_ROOT/wake-recorder.pid"
RECORDER_SOURCE="$RUNTIME_ROOT/SleepWakeRecorder.swift"
RECORDER_LABEL_PREFIX="com.hermes.bridge.m14-003.wake-recorder"
RECORDER_EXECUTABLE="/usr/bin/swift"
RECORDER_FAILURE_REASON=""
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
REAL_HERMES_QUIESCE_OPT_IN="${HERMES_QUIESCE_REAL_AGENT:-}"
REAL_HERMES_ROOT_PIDS="${HERMES_REAL_AGENT_ROOT_PIDS:-}"
REAL_HERMES_RECORDS_FILE="$RUNTIME_ROOT/real-hermes-quiescence.json"
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
typeset -a REAL_HERMES_RECORDED_PIDS
ROOT_PIDS_EXPECTED=0
ROOT_PIDS_VALIDATED=0
ROOT_PIDS_REPRESENTED=0
QUIESCED_MEMBER_COUNT=0
QUIESCENCE_COMPLETE=no
INTEGRITY_BEFORE="$RUNTIME_ROOT/real-home-before.snapshot"
INTEGRITY_AFTER="$RUNTIME_ROOT/real-home-after.snapshot"
INTEGRITY_CHANGES="$RUNTIME_ROOT/real-home-changes.txt"
FINISHED="no"
CHECKPOINT_FAILURE_FATAL="yes"
REAL_HOME_INTEGRITY_FINALIZED="no"
POWER_LOG_PREPARE_UTC=""
POWER_LOG_PREPARE_EPOCH=""
POWER_LOG_PREPARE_LOCAL_OFFSET=""
POWER_LOG_PREPARE_UPTIME=""
POWER_LOG_PREPARE_MONOTONIC=""

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
  print -u2 "usage: $SCRIPT_NAME prepare|resume|cleanup|diagnose-power-evidence"
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
    trap - EXIT INT TERM HUP
    write_result
    FINISHED="yes"
    exit 2
  fi
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
}

process_info_system_uptime() {
  /usr/bin/swift -e 'import Foundation; print(ProcessInfo.processInfo.systemUptime)' 2>/dev/null
}

record_phase_marker() {
  local marker="$1"
  /usr/bin/python3 - "$PHASE_MARKERS_FILE" "$RUN_ID" "$marker" <<'PY'
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
path, run_id, marker = sys.argv[1:]
payload = {
    "schemaVersion": 1,
    "runIdentifier": run_id,
    "marker": marker,
    "utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "epochSeconds": time.time(),
    "monotonicUptime": time.monotonic(),
}
target = Path(path)
target.parent.mkdir(parents=True, exist_ok=True)
with target.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(payload, sort_keys=True) + "\n")
    handle.flush()
    os.fsync(handle.fileno())
PY
}

capture_pmset_log() {
  "$POWER_LOG_COMMAND" -g log
}

record_power_log_prepare_checkpoint() {
  POWER_LOG_PREPARE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  POWER_LOG_PREPARE_EPOCH="$(date -u +%s)"
  POWER_LOG_PREPARE_LOCAL_OFFSET="$(date +%z)"
  POWER_LOG_PREPARE_UPTIME="$(process_info_system_uptime)"
  POWER_LOG_PREPARE_MONOTONIC="$(/usr/bin/python3 -c 'import time; print(time.monotonic())' 2>/dev/null)"
  [[ "$POWER_LOG_PREPARE_EPOCH" == <-> ]] || return 1
  [[ -n "$POWER_LOG_PREPARE_UPTIME" && -n "$POWER_LOG_PREPARE_MONOTONIC" ]] || return 1
}

verify_system_power_log_evidence() {
  local resume_utc resume_epoch resume_uptime
  resume_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  resume_epoch="$(date -u +%s)"
  resume_uptime="$(process_info_system_uptime)"
  [[ -n "$resume_uptime" ]] || {
    print -u2 "invalid-uptime-evidence"
    return 1
  }
  capture_pmset_log | /usr/bin/python3 Scripts/m14_003_power_log_evidence.py verify \
    --checkpoint "$CHECKPOINT_FILE" \
    --evidence "$POWER_LOG_EVIDENCE_FILE" \
    --run-id "$RUN_ID" \
    --resume-utc "$resume_utc" \
    --resume-epoch "$resume_epoch" \
    --resume-uptime "$resume_uptime"
}

diagnose_power_evidence() {
  if [[ -n "${HERMES_M14_003_POWER_LOG_FIXTURE:-}" ]]; then
    /usr/bin/python3 Scripts/m14_003_power_log_evidence.py diagnose \
      --checkpoint "${HERMES_M14_003_CHECKPOINT_FIXTURE:-$CHECKPOINT_FILE}" \
      --run-id "${HERMES_M14_003_RUN_ID:-}" \
      --fixture-log "$HERMES_M14_003_POWER_LOG_FIXTURE" \
      --fixture-prepare-epoch "${HERMES_M14_003_FIXTURE_PREPARE_EPOCH:-0}" \
      --fixture-resume-epoch "${HERMES_M14_003_FIXTURE_RESUME_EPOCH:-$(date -u +%s)}"
  else
    capture_pmset_log | /usr/bin/python3 Scripts/m14_003_power_log_evidence.py diagnose \
      --checkpoint "$CHECKPOINT_FILE" \
      --run-id "${HERMES_M14_003_RUN_ID:-}" \
      --fixture-resume-epoch "$(date -u +%s)"
  fi
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
  [[ "$REAL_HOME_INTEGRITY_FINALIZED" == "yes" ]] && return 0
  if [[ -r "$INTEGRITY_BEFORE" ]] && compare_real_home_integrity_snapshot; then
    RESULT[REAL_HERMES_HOME_MODIFIED]=no
  else
    RESULT[REAL_HERMES_HOME_MODIFIED]=yes
  fi
  REAL_HOME_INTEGRITY_FINALIZED="yes"
  record_phase_marker "REAL_HOME_COMPARED_BEFORE_AGENT_RESUME" 2>/dev/null || true
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

typeset PARSED_PID=""
typeset PARSED_PPID=""
typeset PARSED_PGID=""
typeset PARSED_UID=""
typeset PARSED_PROC_STATE=""
typeset PARSED_START_TIME=""
typeset PARSED_COMM=""

parse_process_identity_row() {
  local line="$1"
  local fields
  fields=("${(@z)line}")
  (( ${#fields[@]} >= 11 )) || return 1
  PARSED_PID="${fields[1]}"
  PARSED_PPID="${fields[2]}"
  PARSED_PGID="${fields[3]}"
  PARSED_UID="${fields[4]}"
  PARSED_PROC_STATE="${fields[5]}"
  PARSED_START_TIME="${(j: :)fields[6,10]}"
  PARSED_COMM="${(j: :)fields[11,-1]}"
}

process_identity_row_for_pid() {
  local pid="$1"
  /bin/ps -o pid= -o ppid= -o pgid= -o uid= -o stat= -o lstart= -o comm= -p "$pid" 2>/dev/null \
    | sed '/^[[:space:]]*$/d' | head -n 1
}

enumerate_current_user_process_group() {
  local pgid="$1"
  /bin/ps -axo pid=,ppid=,pgid=,uid=,stat=,lstart=,comm= 2>/dev/null | while IFS= read -r line; do
    parse_process_identity_row "$line" || continue
    [[ "$PARSED_PGID" == "$pgid" ]] || continue
    print -r -- "$PARSED_PID	$PARSED_PPID	$PARSED_PGID	$PARSED_UID	$PARSED_PROC_STATE	$PARSED_START_TIME	${PARSED_COMM:t}"
  done
}

write_empty_real_hermes_records() {
  mkdir -p "$RUNTIME_ROOT"
  print -r -- "[]" > "$REAL_HERMES_RECORDS_FILE"
}

print_quiescence_diagnostics() {
  print -r -- "ROOT_PIDS_EXPECTED=$ROOT_PIDS_EXPECTED"
  print -r -- "ROOT_PIDS_VALIDATED=$ROOT_PIDS_VALIDATED"
  print -r -- "ROOT_PIDS_REPRESENTED=$ROOT_PIDS_REPRESENTED"
  print -r -- "QUIESCED_MEMBER_COUNT=$QUIESCED_MEMBER_COUNT"
  print -r -- "QUIESCENCE_COMPLETE=$QUIESCENCE_COMPLETE"
}

record_real_hermes_quiescence() {
  mkdir -p "$RUNTIME_ROOT"
  local roots
  roots=("${(@z)REAL_HERMES_ROOT_PIDS}")
  ROOT_PIDS_EXPECTED=${#roots[@]}
  ROOT_PIDS_VALIDATED=0
  ROOT_PIDS_REPRESENTED=0
  QUIESCED_MEMBER_COUNT=0
  QUIESCENCE_COMPLETE=no
  if (( ${#roots[@]} == 0 )); then
    REAL_HERMES_RECORDED_PIDS=()
    write_empty_real_hermes_records
    QUIESCENCE_COMPLETE=yes
    return 0
  fi
  [[ "$REAL_HERMES_QUIESCE_OPT_IN" == "YES" ]] || fail "set HERMES_QUIESCE_REAL_AGENT=YES before quiescing real Hermes Agent PIDs"

  local current_uid
  current_uid="$(id -u)"
  local records_tsv="$RUNTIME_ROOT/real-hermes-quiescence.tsv"
  : > "$records_tsv"
  REAL_HERMES_RECORDED_PIDS=()
  typeset -A seen_pids
  typeset -A seen_roots

  local root_pid root_line root_pgid member_lines member_line saw_root
  for root_pid in "${roots[@]}"; do
    [[ "$root_pid" == <-> ]] || fail "HERMES_REAL_AGENT_ROOT_PIDS must contain numeric PIDs only"
    [[ -z "${seen_roots[$root_pid]:-}" ]] || fail "duplicate real Hermes root PID $root_pid"
    seen_roots[$root_pid]=yes
    root_line="$(process_identity_row_for_pid "$root_pid")"
    [[ -n "$root_line" ]] || fail "real Hermes root PID $root_pid is not alive"
    parse_process_identity_row "$root_line" || fail "could not parse real Hermes root PID $root_pid"
    [[ "$PARSED_PID" == "$root_pid" ]] || fail "real Hermes root PID identity mismatch"
    [[ "$PARSED_UID" == "$current_uid" ]] || fail "real Hermes root PID $root_pid is not owned by the current UID"
    root_pgid="$PARSED_PGID"
    ROOT_PIDS_VALIDATED=$(( ROOT_PIDS_VALIDATED + 1 ))
    member_lines=("${(@f)$(enumerate_current_user_process_group "$root_pgid")}")
    (( ${#member_lines[@]} > 0 )) || fail "no process-group members found for real Hermes root PID $root_pid"
    saw_root="no"
    for member_line in "${member_lines[@]}"; do
      local member_pid member_ppid member_pgid member_uid member_proc_state member_start_time member_basename
      IFS=$'\t' read -r member_pid member_ppid member_pgid member_uid member_proc_state member_start_time member_basename <<< "$member_line"
      [[ -n "$member_basename" ]] || fail "could not parse real Hermes process-group member"
      [[ "$member_pgid" == "$root_pgid" ]] || fail "process-group enumeration escaped exact PGID"
      [[ "$member_uid" == "$current_uid" ]] || fail "process-group member $member_pid is not owned by the current UID"
      [[ "$member_pid" == "$root_pid" ]] && saw_root="yes"
      if [[ -z "${seen_pids[$member_pid]:-}" ]]; then
        seen_pids[$member_pid]=yes
        REAL_HERMES_RECORDED_PIDS+=("$member_pid")
        print -r -- "$member_pid	$member_ppid	$member_pgid	$member_uid	$member_proc_state	$member_start_time	$member_basename	$root_pid	$([[ "$member_pid" == "$root_pid" ]] && print -r -- true || print -r -- false)" >> "$records_tsv"
      fi
    done
    [[ "$saw_root" == "yes" ]] || fail "real Hermes root PID $root_pid exited before suspension"
  done
  QUIESCED_MEMBER_COUNT=${#REAL_HERMES_RECORDED_PIDS[@]}

  /usr/bin/python3 - "$records_tsv" "$REAL_HERMES_RECORDS_FILE" "${roots[@]}" <<'PY'
import json
import os
import sys
from pathlib import Path
supplied_roots = [int(value) for value in sys.argv[3:]]
supplied_root_set = set(supplied_roots)
records = []
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    pid, ppid, pgid, uid, proc_state, start_time, basename, root_pid, is_root = line.split("\t")
    if "/" in basename:
        raise SystemExit("executable basename must not be a path")
    pid_int = int(pid)
    records.append({
        "pid": pid_int,
        "ppid": int(ppid),
        "pgid": int(pgid),
        "uid": int(uid),
        "stateBeforeStop": proc_state,
        "processStartTime": start_time,
        "executableBasename": basename,
        "rootPid": int(root_pid),
        "isRoot": pid_int in supplied_root_set,
        "operatorSuppliedRootPids": [pid_int] if pid_int in supplied_root_set else [],
        "suspendedByM14003": False,
    })
represented = {record["pid"] for record in records if record["pid"] in supplied_root_set}
if represented != supplied_root_set:
    missing = sorted(supplied_root_set - represented)
    raise SystemExit("missing represented root PID(s): " + ",".join(str(pid) for pid in missing))
payload = json.dumps(records, indent=2, sort_keys=True) + "\n"
path = Path(sys.argv[2])
with path.open("w", encoding="utf-8") as handle:
    handle.write(payload)
    handle.flush()
    os.fsync(handle.fileno())
directory_fd = os.open(str(path.parent), os.O_RDONLY)
try:
    os.fsync(directory_fd)
finally:
    os.close(directory_fd)
PY
  ROOT_PIDS_REPRESENTED=$(/usr/bin/python3 - "$REAL_HERMES_RECORDS_FILE" "${roots[@]}" <<'PY'
import json
import sys
from pathlib import Path
roots = {int(value) for value in sys.argv[2:]}
records = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(len({record["pid"] for record in records if record.get("pid") in roots}))
PY
)
  if [[ "$ROOT_PIDS_EXPECTED" == "$ROOT_PIDS_VALIDATED" \
    && "$ROOT_PIDS_EXPECTED" == "$ROOT_PIDS_REPRESENTED" \
    && "$QUIESCED_MEMBER_COUNT" -ge "$ROOT_PIDS_EXPECTED" ]]; then
    QUIESCENCE_COMPLETE=yes
  fi
  [[ "$QUIESCENCE_COMPLETE" == "yes" ]] || fail "real Hermes root PID quiescence incomplete"
}

update_real_hermes_suspended_checkpoint() {
  /usr/bin/python3 - "$REAL_HERMES_RECORDS_FILE" <<'PY'
import json
import os
import sys
from pathlib import Path
path = Path(sys.argv[1])
records = json.loads(path.read_text(encoding="utf-8"))
for record in records:
    record["suspendedByM14003"] = True
payload = json.dumps(records, indent=2, sort_keys=True) + "\n"
with path.open("w", encoding="utf-8") as handle:
    handle.write(payload)
    handle.flush()
    os.fsync(handle.fileno())
PY
}

update_real_hermes_pid_suspended_checkpoint() {
  local suspended_pid="$1"
  /usr/bin/python3 - "$REAL_HERMES_RECORDS_FILE" "$suspended_pid" <<'PY'
import json
import os
import sys
from pathlib import Path
path = Path(sys.argv[1])
pid = int(sys.argv[2])
records = json.loads(path.read_text(encoding="utf-8"))
found = False
for record in records:
    if record["pid"] == pid:
        record["suspendedByM14003"] = True
        found = True
if not found:
    raise SystemExit("recorded PID not found")
payload = json.dumps(records, indent=2, sort_keys=True) + "\n"
with path.open("w", encoding="utf-8") as handle:
    handle.write(payload)
    handle.flush()
    os.fsync(handle.fileno())
PY
}

process_identity_matches_record() {
  local pid="$1"
  local expected_uid="$2"
  local expected_pgid="$3"
  local expected_basename="$4"
  local expected_start_time="$5"
  local line
  line="$(process_identity_row_for_pid "$pid")" || return 1
  [[ -n "$line" ]] || return 1
  parse_process_identity_row "$line" || return 1
  [[ "$PARSED_PID" == "$pid" ]] || return 1
  [[ "$PARSED_UID" == "$expected_uid" ]] || return 1
  [[ "$PARSED_PGID" == "$expected_pgid" ]] || return 1
  [[ "${PARSED_COMM:t}" == "$expected_basename" ]] || return 1
  [[ "$PARSED_START_TIME" == "$expected_start_time" ]] || return 1
}

verify_real_hermes_suspended() {
  local pid line
  for pid in "${REAL_HERMES_RECORDED_PIDS[@]}"; do
    line="$(process_identity_row_for_pid "$pid")" || return 1
    parse_process_identity_row "$line" || return 1
    [[ "$PARSED_PROC_STATE" == *T* ]] || return 1
  done
}

verify_real_hermes_quiescence_complete() {
  /usr/bin/python3 - "$REAL_HERMES_RECORDS_FILE" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
if not path.exists():
    raise SystemExit("real-hermes-quiescence-missing")
records = json.loads(path.read_text(encoding="utf-8"))
if not isinstance(records, list):
    raise SystemExit("real-hermes-quiescence-invalid")
roots = {record["pid"] for record in records if record.get("isRoot") is True}
if len(records) < len(roots):
    raise SystemExit("real-hermes-quiescence-incomplete")
for record in records:
    if "/" in str(record.get("executableBasename", "")):
        raise SystemExit("real-hermes-quiescence-invalid")
    if record.get("suspendedByM14003") is not True:
        raise SystemExit("real-hermes-quiescence-incomplete")
if roots and not roots.issubset({record["pid"] for record in records}):
    raise SystemExit("real-hermes-quiescence-incomplete")
PY
}

stop_real_hermes_recorded_pids() {
  record_real_hermes_quiescence
  local pid
  for pid in "${REAL_HERMES_RECORDED_PIDS[@]}"; do
    /bin/kill -STOP "$pid" || fail "failed to suspend recorded real Hermes PID $pid"
    update_real_hermes_pid_suspended_checkpoint "$pid" || fail "failed to checkpoint suspended real Hermes PID $pid"
  done
  verify_real_hermes_suspended || fail "not every recorded real Hermes PID is suspended"
  update_real_hermes_suspended_checkpoint
}

resume_real_hermes_recorded_pids() {
  [[ -r "$REAL_HERMES_RECORDS_FILE" ]] || return 0
  record_phase_marker "AGENT_RESUME_STARTED" 2>/dev/null || true
  /usr/bin/python3 - "$REAL_HERMES_RECORDS_FILE" <<'PY' | while IFS=$'\t' read -r pid uid pgid basename start_time; do
import json
import sys
from pathlib import Path
for record in json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")):
    if record.get("suspendedByM14003") is True:
        print("\t".join([
            str(record["pid"]),
            str(record["uid"]),
            str(record["pgid"]),
            str(record["executableBasename"]),
            str(record["processStartTime"]),
        ]))
PY
    if kill -0 "$pid" 2>/dev/null && process_identity_matches_record "$pid" "$uid" "$pgid" "$basename" "$start_time"; then
      /bin/kill -CONT "$pid" >/dev/null 2>&1 || true
    fi
  done
  record_phase_marker "AGENT_RESUME_COMPLETED" 2>/dev/null || true
}

service_pid_from_launchctl() {
  pid_from_launchctl_label "$LABEL"
}

recorder_pid_from_launchctl() {
  pid_from_launchctl_label "$RECORDER_LABEL"
}

validate_recorder_plist_contract() {
  /usr/bin/python3 - "$RECORDER_PLIST" "$RECORDER_LABEL" "$RECORDER_EXECUTABLE" "$RECORDER_SOURCE" \
    "$RUN_ID" "$EVIDENCE_FILE" "$RECORDER_READY_FILE" "$RECORDER_PID_FILE" "$WAKE_TIMEOUT_SECONDS" <<'PY'
import plistlib
import sys
from pathlib import Path
plist_path, label, executable, source, run_id, evidence, ready_path, pid_path, timeout = sys.argv[1:]
try:
    plist = plistlib.loads(Path(plist_path).read_bytes())
except Exception:
    raise SystemExit("recorder-identity-invalid")
if plist.get("Label") != label:
    raise SystemExit("recorder-identity-invalid")
arguments = plist.get("ProgramArguments")
if not isinstance(arguments, list) or len(arguments) != 8:
    raise SystemExit("recorder-identity-invalid")
expected = [executable, source, run_id, label, evidence, ready_path, pid_path, timeout]
if arguments != expected:
    raise SystemExit("recorder-identity-invalid")
PY
}

validate_recorder_process_identity() {
  local pid="$1"
  local current_uid line expected_executable_path expected_executable_basename
  current_uid="$(id -u)"
  [[ "$pid" == <-> ]] || {
    RECORDER_FAILURE_REASON="recorder-identity-invalid"
    return 1
  }
  line="$(process_identity_row_for_pid "$pid")" || {
    RECORDER_FAILURE_REASON="recorder-identity-invalid"
    return 1
  }
  [[ -n "$line" ]] || {
    RECORDER_FAILURE_REASON="recorder-identity-invalid"
    return 1
  }
  parse_process_identity_row "$line" || {
    RECORDER_FAILURE_REASON="recorder-identity-invalid"
    return 1
  }
  [[ "$PARSED_PID" == "$pid" ]] || {
    RECORDER_FAILURE_REASON="recorder-identity-invalid"
    return 1
  }
  [[ "$PARSED_UID" == "$current_uid" ]] || {
    RECORDER_FAILURE_REASON="recorder-identity-invalid"
    return 1
  }
  expected_executable_path="$(/usr/bin/python3 - "$RECORDER_READY_FILE" "$RUN_ID" "$RECORDER_LABEL" "$pid" <<'PY'
import json
import sys
from pathlib import Path
ready_path, run_id, label, pid = sys.argv[1:]
ready = json.loads(Path(ready_path).read_text(encoding="utf-8"))
if ready.get("runIdentifier") != run_id or ready.get("recorderLabel") != label:
    raise SystemExit("recorder-identity-invalid")
if ready.get("pid") != int(pid):
    raise SystemExit("recorder-identity-invalid")
path = ready.get("currentExecutablePath")
if not isinstance(path, str) or not path.startswith("/"):
    raise SystemExit("recorder-identity-invalid")
print(path)
PY
)" || {
    RECORDER_FAILURE_REASON="recorder-identity-invalid"
    return 1
  }
  expected_executable_basename="${expected_executable_path:t}"
  [[ "$PARSED_COMM" == "$expected_executable_path" && "${PARSED_COMM:t}" == "$expected_executable_basename" ]] || {
    RECORDER_FAILURE_REASON="recorder-identity-invalid"
    return 1
  }
  validate_recorder_plist_contract || {
    RECORDER_FAILURE_REASON="recorder-identity-invalid"
    return 1
  }
}

validate_resume_recorder_identity() {
  /bin/launchctl print "$SERVICE_DOMAIN/$RECORDER_LABEL" >/dev/null 2>&1 || {
    RECORDER_FAILURE_REASON="recorder-identity-invalid"
    return 1
  }
  validate_recorder_plist_contract || {
    RECORDER_FAILURE_REASON="recorder-identity-invalid"
    return 1
  }
  local launchd_pid
  launchd_pid="$(recorder_pid_from_launchctl)"
  [[ -n "$launchd_pid" ]] || return 0
  if [[ -n "$RECORDER_PID" && "$launchd_pid" == "$RECORDER_PID" ]]; then
    validate_recorder_process_identity "$RECORDER_PID"
    return $?
  fi
  validate_recorder_process_identity "$launchd_pid" || return 1
  RECORDER_PID="$launchd_pid"
  write_checkpoint "resume" "recorder-restarted"
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

checkpoint_write_failed() {
  local checkpoint_tmp="$1"
  rm -f "$checkpoint_tmp"
  RESULT[M14_003_RESULT]=FAIL
  cleanup_owned_state
  write_result
  restore_real_hermes_after_final_decision
  trap - EXIT INT TERM HUP
  FINISHED="yes"
  exit 1
}

write_checkpoint() {
  local phase="$1"
  local checkpoint_state="$2"
  local checkpoint_tmp="$RUNTIME_ROOT/.checkpoint.$RUN_ID.$$.$RANDOM.tmp"
  mkdir -p "$RUNTIME_ROOT"
  if ! /usr/bin/python3 - "$CHECKPOINT_FILE" "$checkpoint_tmp" "$RUN_ID" "$phase" "$checkpoint_state" \
    "$LABEL" "$RECORDER_LABEL" "$APP_TARGET_REL" "$LAUNCH_AGENT_TARGET_REL" "$RECORDER_PLIST_REL" \
    "$APP_EXECUTABLE_REL" "$SERVICE_EXECUTABLE_REL" "$APP_PID" "$SERVICE_PID" "$RECORDER_PID" \
    "$APP_INSTALLED_BY_RUN" "$LAUNCH_AGENT_INSTALLED_BY_RUN" "$SERVICE_BOOTSTRAPPED_BY_RUN" \
    "$RECORDER_BOOTSTRAPPED_BY_RUN" "$RESTART_CYCLES_EXPECTED" "$REAL_HERMES_RECORDS_FILE" \
    "$POWER_LOG_PREPARE_UTC" "$POWER_LOG_PREPARE_EPOCH" "$POWER_LOG_PREPARE_LOCAL_OFFSET" \
    "$POWER_LOG_PREPARE_UPTIME" "$POWER_LOG_PREPARE_MONOTONIC" <<'PY'
import json
import os
import sys
import time
from pathlib import Path

(
    final_path, tmp_path, run_id, phase, checkpoint_state, service_label, recorder_label, app_target_rel,
    launch_agent_target_rel, recorder_plist_rel, app_executable_rel,
    service_executable_rel, app_pid, service_pid, recorder_pid, app_installed,
    launch_agent_installed, service_bootstrapped, recorder_bootstrapped,
    restart_cycles_expected, real_hermes_records_path,
    power_log_prepare_utc, power_log_prepare_epoch, power_log_prepare_local_offset,
    power_log_prepare_uptime, power_log_prepare_monotonic,
) = sys.argv[1:]
real_hermes_records = []
records_path = Path(real_hermes_records_path)
if records_path.exists():
    loaded_records = json.loads(records_path.read_text(encoding="utf-8"))
    if not isinstance(loaded_records, list):
        raise SystemExit("invalid real Hermes quiescence records")
    real_hermes_records = loaded_records
checkpoint = {
    "schemaVersion": 1,
    "runIdentifier": run_id,
    "phase": phase,
    "status": checkpoint_state,
    "createdAtMonotonicUptime": time.monotonic(),
    "updatedAtEpochSeconds": int(time.time()),
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
    "systemPowerLogEvidence": "artifacts/m14-003/runtime/system-power-log-evidence.json",
    "wakeRecorderReady": "artifacts/m14-003/runtime/wake-recorder-ready.json",
    "realHomeSnapshotBefore": "artifacts/m14-003/runtime/real-home-before.snapshot",
    "realHermesQuiescence": {
        "operatorProvidedRootPids": [record["pid"] for record in real_hermes_records if record.get("isRoot")],
        "records": real_hermes_records,
    },
}
if power_log_prepare_utc:
    try:
        power_log_epoch_value = int(power_log_prepare_epoch)
        power_log_uptime_value = float(power_log_prepare_uptime)
        power_log_monotonic_value = float(power_log_prepare_monotonic)
    except ValueError:
        raise SystemExit("invalid power log checkpoint")
    checkpoint["powerLogCheckpoint"] = {
        "runIdentifier": run_id,
        "epochSeconds": power_log_epoch_value,
        "utcISO8601": power_log_prepare_utc,
        "localTimezoneOffset": power_log_prepare_local_offset,
        "systemUptime": power_log_uptime_value,
        "createdAtMonotonic": power_log_monotonic_value,
    }
required = [
    ("schemaVersion", int),
    ("runIdentifier", str),
    ("phase", str),
    ("status", str),
    ("createdAtMonotonicUptime", float),
    ("updatedAtEpochSeconds", int),
    ("serviceDomain", str),
    ("serviceLabel", str),
    ("recorderLabel", str),
    ("targets", dict),
    ("ownedPids", dict),
    ("ownership", dict),
    ("restartCyclesExpected", int),
    ("resultFile", str),
    ("runtimeRoot", str),
    ("wakeEvidence", str),
    ("systemPowerLogEvidence", str),
    ("wakeRecorderReady", str),
    ("realHomeSnapshotBefore", str),
    ("realHermesQuiescence", dict),
]
for key, expected in required:
    if key not in checkpoint or not isinstance(checkpoint[key], expected):
        raise SystemExit(f"invalid checkpoint payload: {key}")
target_keys = ["app", "launchAgent", "recorderLaunchAgent", "appExecutable", "serviceExecutable"]
for key in target_keys:
    value = checkpoint["targets"].get(key)
    if not isinstance(value, str) or value.startswith("/") or ".." in value.split("/"):
        raise SystemExit(f"invalid checkpoint target: {key}")
for record in checkpoint["realHermesQuiescence"]["records"]:
    for key in ["pid", "uid", "pgid", "executableBasename", "processStartTime"]:
        if key not in record:
            raise SystemExit(f"invalid real Hermes record: {key}")
    if "/" in str(record["executableBasename"]):
        raise SystemExit("real Hermes executable basename must not be a path")
if os.environ.get("HERMES_M14_003_CHECKPOINT_TEST_FAIL_AFTER_TEMP") == "YES":
    Path(tmp_path).write_text("partial\n", encoding="utf-8")
    raise SystemExit("injected checkpoint failure")
payload = json.dumps(checkpoint, indent=2, sort_keys=True) + "\n"
tmp = Path(tmp_path)
final = Path(final_path)
if tmp.parent != final.parent:
    raise SystemExit("temporary checkpoint must share final directory")
with tmp.open("w", encoding="utf-8") as handle:
    handle.write(payload)
    handle.flush()
    os.fsync(handle.fileno())
with tmp.open("r", encoding="utf-8") as handle:
    written = json.load(handle)
for key, expected in required:
    if key not in written or not isinstance(written[key], expected):
        raise SystemExit(f"invalid written checkpoint: {key}")
os.replace(tmp, final)
directory_fd = os.open(str(final.parent), os.O_RDONLY)
try:
    os.fsync(directory_fd)
finally:
    os.close(directory_fd)
PY
  then
    rm -f "$checkpoint_tmp"
    if [[ "$CHECKPOINT_FAILURE_FATAL" == "yes" ]]; then
      checkpoint_write_failed "$checkpoint_tmp"
    fi
    return 1
  fi
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
records = data.get("realHermesQuiescence", {}).get("records", [])
emit("REAL_HERMES_RECORDED_PIDS", " ".join(str(record.get("pid")) for record in records if isinstance(record.get("pid"), int)))
PY
)" || return 1
  eval "$assignments"
  REAL_HERMES_RECORDED_PIDS=("${(@z)REAL_HERMES_RECORDED_PIDS}")
  RECORDER_PLIST="$HOME/$RECORDER_PLIST_REL"
  restore_real_hermes_records_from_checkpoint 2>/dev/null || true
  return 0
}

restore_real_hermes_records_from_checkpoint() {
  [[ -r "$CHECKPOINT_FILE" ]] || return 1
  /usr/bin/python3 - "$CHECKPOINT_FILE" "$REAL_HERMES_RECORDS_FILE" <<'PY'
import json
import os
import sys
from pathlib import Path
checkpoint = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
records = checkpoint.get("realHermesQuiescence", {}).get("records", [])
if not isinstance(records, list):
    raise SystemExit("invalid real Hermes checkpoint records")
path = Path(sys.argv[2])
path.parent.mkdir(parents=True, exist_ok=True)
payload = json.dumps(records, indent=2, sort_keys=True) + "\n"
with path.open("w", encoding="utf-8") as handle:
    handle.write(payload)
    handle.flush()
    os.fsync(handle.fileno())
PY
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
import Darwin
import Foundation
import IOKit.pwr_mgt

struct Event: Encodable {
  let schemaVersion: Int
  let runIdentifier: String
  let recorderLabel: String
  let recorderInstanceIdentifier: String
  let eventSequenceNumber: Int
  let currentExecutablePath: String
  let event: String
  let pid: Int32
  let monotonicUptime: TimeInterval
  let wallClockEpochSeconds: TimeInterval
  let iokitRegistered: Bool
  let eventLoopActive: Bool
  let evidenceWritable: Bool
  let detail: String?
}

let args = CommandLine.arguments
guard args.count == 7 else {
  exit(64)
}
let runIdentifier = args[1]
let recorderLabel = args[2]
let evidencePath = args[3]
let readyPath = args[4]
let pidPath = args[5]
let lifetime = TimeInterval(args[6]) ?? 900
let started = Date()
let deadline = started.addingTimeInterval(lifetime)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let recorderInstanceIdentifier = UUID().uuidString
var eventSequenceNumber = 0
var rootPort: io_connect_t = 0
var notifier: io_object_t = 0
var notifyPort: IONotificationPortRef?
var iokitRegistered = false
var evidenceWritable = false
let iokitSystemWillSleepMessage = UInt32(0xE0000280) // kIOMessageSystemWillSleep
let iokitSystemHasPoweredOnMessage = UInt32(0xE0000300) // kIOMessageSystemHasPoweredOn

@Sendable
func currentExecutablePath() -> String {
  var size = UInt32(0)
  _NSGetExecutablePath(nil, &size)
  let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(size))
  defer { buffer.deallocate() }
  if _NSGetExecutablePath(buffer, &size) == 0 {
    return FileManager.default.string(withFileSystemRepresentation: buffer, length: Int(strlen(buffer)))
  }
  return CommandLine.arguments[0]
}

@Sendable
func fsyncDirectory(containing path: String) {
  let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
  let fd = open(directory, O_RDONLY)
  if fd >= 0 {
    fsync(fd)
    close(fd)
  }
}

@discardableResult
func append(_ event: String, detail: String? = nil) -> Bool {
  eventSequenceNumber += 1
  let payload = Event(
    schemaVersion: 1,
    runIdentifier: runIdentifier,
    recorderLabel: recorderLabel,
    recorderInstanceIdentifier: recorderInstanceIdentifier,
    eventSequenceNumber: eventSequenceNumber,
    currentExecutablePath: currentExecutablePath(),
    event: event,
    pid: getpid(),
    monotonicUptime: ProcessInfo.processInfo.systemUptime,
    wallClockEpochSeconds: CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970,
    iokitRegistered: iokitRegistered,
    eventLoopActive: CFRunLoopGetCurrent() == CFRunLoopGetMain(),
    evidenceWritable: evidenceWritable,
    detail: detail
  )
  guard let data = try? encoder.encode(payload) else { return false }
  let url = URL(fileURLWithPath: evidencePath)
  FileManager.default.createFile(atPath: evidencePath, contents: nil)
  guard let handle = try? FileHandle(forWritingTo: url) else { return false }
  do {
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
    try handle.write(contentsOf: Data("\n".utf8))
    try handle.synchronize()
    fsync(handle.fileDescriptor)
    try handle.close()
    fsyncDirectory(containing: evidencePath)
    return true
  } catch {
    try? handle.close()
    return false
  }
}

func writeReadyFile() -> Bool {
  let payload: [String: Any] = [
    "schemaVersion": 1,
    "runIdentifier": runIdentifier,
    "recorderLabel": recorderLabel,
    "recorderInstanceIdentifier": recorderInstanceIdentifier,
    "currentExecutablePath": currentExecutablePath(),
    "pid": Int(getpid()),
    "iokitRegistered": iokitRegistered,
    "eventLoopActive": true,
    "evidenceWritable": evidenceWritable,
    "monotonicUptime": ProcessInfo.processInfo.systemUptime,
    "wallClockEpochSeconds": CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970,
  ]
  guard JSONSerialization.isValidJSONObject(payload),
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
    return false
  }
  let url = URL(fileURLWithPath: readyPath)
  FileManager.default.createFile(atPath: readyPath, contents: nil)
  guard let handle = try? FileHandle(forWritingTo: url) else { return false }
  do {
    try handle.truncate(atOffset: 0)
    try handle.write(contentsOf: data)
    try handle.write(contentsOf: Data("\n".utf8))
    try handle.synchronize()
    fsync(handle.fileDescriptor)
    try handle.close()
    fsyncDirectory(containing: readyPath)
    return true
  } catch {
    try? handle.close()
    return false
  }
}

try? "\(getpid())\n".write(toFile: pidPath, atomically: true, encoding: .utf8)
evidenceWritable = append("recorder-started")

if ProcessInfo.processInfo.environment["HERMES_M14_003_FORCE_IOKIT_REGISTRATION_FAILURE"] == "YES" {
  append("iokit-registration-failed", detail: "forced")
  exit(70)
}

let callback: IOServiceInterestCallback = { _, _, messageType, messageArgument in
  switch messageType {
  case iokitSystemWillSleepMessage:
    append("IOKitSystemWillSleep")
    IOAllowPowerChange(rootPort, Int(bitPattern: messageArgument))
  case iokitSystemHasPoweredOnMessage:
    append("IOKitSystemHasPoweredOn")
    CFRunLoopStop(CFRunLoopGetMain())
  default:
    break
  }
}

rootPort = IORegisterForSystemPower(nil, &notifyPort, callback, &notifier)
guard rootPort != 0, let notifyPort else {
  append("iokit-registration-failed")
  exit(70)
}
iokitRegistered = true
append("iokit-registration-succeeded")

if let source = IONotificationPortGetRunLoopSource(notifyPort)?.takeUnretainedValue() {
  CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
} else {
  append("iokit-registration-failed", detail: "missing-runloop-source")
  exit(70)
}

let center = NSWorkspace.shared.notificationCenter
let sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
  append("NSWorkspaceWillSleep")
}
let wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
  append("NSWorkspaceDidWake")
}

let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, deadline.timeIntervalSinceReferenceDate, 0, 0, 0) { _ in
  append("recorder-timeout")
  CFRunLoopStop(CFRunLoopGetMain())
}
CFRunLoopAddTimer(CFRunLoopGetMain(), timer, .defaultMode)

CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
  append("recorder-ready")
  if !writeReadyFile() {
    append("recorder-ready-write-failed")
    CFRunLoopStop(CFRunLoopGetMain())
  }
}
CFRunLoopWakeUp(CFRunLoopGetMain())

CFRunLoopRun()
center.removeObserver(sleepObserver)
center.removeObserver(wakeObserver)
if notifier != 0 {
  IOObjectRelease(notifier)
}
if rootPort != 0 {
  IOServiceClose(rootPort)
}
IONotificationPortDestroy(notifyPort)

append("recorder-finished")
exit(0)
SWIFT
}

install_recorder_launch_agent() {
  write_sleep_wake_recorder
  rm -f "$EVIDENCE_FILE" "$RECORDER_READY_FILE" "$RECORDER_PID_FILE"
  /usr/bin/python3 - "$RECORDER_PLIST" "$RECORDER_LABEL" "$RECORDER_SOURCE" "$RUN_ID" \
    "$EVIDENCE_FILE" "$RECORDER_READY_FILE" "$RECORDER_PID_FILE" "$WAKE_TIMEOUT_SECONDS" "$LOGS_ROOT" <<'PY'
import plistlib
import os
import sys
from pathlib import Path
target, label, source, run_id, evidence, ready_path, pid_path, timeout, logs = sys.argv[1:]
Path(target).parent.mkdir(parents=True, exist_ok=True)
Path(logs).mkdir(parents=True, exist_ok=True)
environment = {}
if os.environ.get("HERMES_M14_003_FORCE_IOKIT_REGISTRATION_FAILURE") == "YES":
    environment["HERMES_M14_003_FORCE_IOKIT_REGISTRATION_FAILURE"] = "YES"
plist = {
    "Label": label,
    "ProgramArguments": ["/usr/bin/swift", source, run_id, label, evidence, ready_path, pid_path, timeout],
    "RunAtLoad": True,
    "KeepAlive": True,
    "ProcessType": "Background",
    "EnvironmentVariables": environment,
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
    if [[ -z "$RECORDER_PID" && -r "$RECORDER_PID_FILE" ]]; then
      RECORDER_PID="$(head -n 1 "$RECORDER_PID_FILE" 2>/dev/null | tr -cd '0-9')"
    fi
    if [[ -n "$RECORDER_PID" ]] && kill -0 "$RECORDER_PID" 2>/dev/null && verify_recorder_ready; then
      return 0
    fi
    sleep 0.5
  done
  RECORDER_FAILURE_REASON="recorder-not-ready"
  return 1
}

verify_recorder_ready() {
  /bin/launchctl print "$SERVICE_DOMAIN/$RECORDER_LABEL" >/dev/null 2>&1 || {
    RECORDER_FAILURE_REASON="recorder-not-ready"
    return 1
  }
  local launchd_pid file_pid
  launchd_pid="$(recorder_pid_from_launchctl)"
  [[ -n "$launchd_pid" ]] || {
    RECORDER_FAILURE_REASON="recorder-not-ready"
    return 1
  }
  [[ -n "$RECORDER_PID" && "$launchd_pid" == "$RECORDER_PID" ]] || {
    RECORDER_FAILURE_REASON="recorder-not-ready"
    return 1
  }
  kill -0 "$RECORDER_PID" 2>/dev/null || {
    RECORDER_FAILURE_REASON="recorder-not-ready"
    return 1
  }
  [[ -r "$RECORDER_PID_FILE" ]] || {
    RECORDER_FAILURE_REASON="recorder-not-ready"
    return 1
  }
  file_pid="$(head -n 1 "$RECORDER_PID_FILE" 2>/dev/null | tr -cd '0-9')"
  [[ "$file_pid" == "$RECORDER_PID" ]] || {
    RECORDER_FAILURE_REASON="recorder-not-ready"
    return 1
  }
  /usr/bin/python3 - "$RECORDER_READY_FILE" "$RUN_ID" "$RECORDER_LABEL" "$RECORDER_PID" "$EVIDENCE_FILE" <<'PY'
import json
import os
import sys
from pathlib import Path
ready_path, run_id, label, pid, evidence = sys.argv[1:]
try:
    ready = json.loads(Path(ready_path).read_text(encoding="utf-8"))
except Exception:
    raise SystemExit("recorder-not-ready")
if ready.get("runIdentifier") != run_id or ready.get("recorderLabel") != label:
    raise SystemExit("run-id-mismatch")
if ready.get("pid") != int(pid):
    raise SystemExit("recorder-not-ready")
if ready.get("iokitRegistered") is not True:
    raise SystemExit("recorder-not-ready")
if ready.get("eventLoopActive") is not True:
    raise SystemExit("recorder-not-ready")
if ready.get("evidenceWritable") is not True:
    raise SystemExit("recorder-not-ready")
if not isinstance(ready.get("currentExecutablePath"), str) or not ready.get("currentExecutablePath").startswith("/"):
    raise SystemExit("recorder-not-ready")
path = Path(evidence)
path.parent.mkdir(parents=True, exist_ok=True)
with path.open("a", encoding="utf-8") as handle:
    handle.flush()
    os.fsync(handle.fileno())
PY
  local rc=$?
  if (( rc != 0 )); then
    RECORDER_FAILURE_REASON="recorder-not-ready"
    return 1
  fi
  return 0
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
    raise SystemExit("recorder-never-ready")
events = []
for line in path.read_text(encoding="utf-8").splitlines():
    if line.strip():
        event = json.loads(line)
        if event.get("schemaVersion") != 1:
            raise SystemExit("evidence-invalid")
        if event.get("runIdentifier") != run_id:
            raise SystemExit("run-id-mismatch")
        if event.get("recorderLabel") != label:
            raise SystemExit("run-id-mismatch")
        if not isinstance(event.get("recorderInstanceIdentifier"), str) or not event.get("recorderInstanceIdentifier"):
            raise SystemExit("evidence-invalid")
        if not isinstance(event.get("eventSequenceNumber"), int) or event.get("eventSequenceNumber") < 1:
            raise SystemExit("evidence-invalid")
        if not isinstance(event.get("currentExecutablePath"), str) or not event.get("currentExecutablePath").startswith("/"):
            raise SystemExit("evidence-invalid")
        if not isinstance(event.get("pid"), int):
            raise SystemExit("evidence-invalid")
        if not isinstance(event.get("monotonicUptime"), (int, float)):
            raise SystemExit("invalid-uptime-evidence")
        if not isinstance(event.get("wallClockEpochSeconds"), (int, float)):
            raise SystemExit("invalid-uptime-evidence")
        events.append(event)
names = [event.get("event") for event in events]
if "recorder-ready" not in names:
    raise SystemExit("recorder-never-ready")
if "IOKitSystemWillSleep" not in names:
    raise SystemExit("will-sleep-missing")
if "IOKitSystemHasPoweredOn" not in names:
    raise SystemExit("wake-missing")
ready_index = names.index("recorder-ready")
sleep_index = names.index("IOKitSystemWillSleep")
wake_index = names.index("IOKitSystemHasPoweredOn")
if not (ready_index < sleep_index < wake_index):
    raise SystemExit("invalid-event-order")
ready = events[ready_index]
sleep = events[sleep_index]
wake = events[wake_index]
if ready.get("iokitRegistered") is not True or ready.get("eventLoopActive") is not True:
    raise SystemExit("recorder-never-ready")
if ready.get("evidenceWritable") is not True:
    raise SystemExit("recorder-never-ready")
if sleep["monotonicUptime"] < ready["monotonicUptime"] or wake["monotonicUptime"] < sleep["monotonicUptime"]:
    raise SystemExit("invalid-uptime-evidence")
if wake["wallClockEpochSeconds"] <= sleep["wallClockEpochSeconds"]:
    raise SystemExit("invalid-uptime-evidence")
if wake["monotonicUptime"] - sleep["monotonicUptime"] < 0:
    raise SystemExit("invalid-uptime-evidence")
for instance in {event["recorderInstanceIdentifier"] for event in events}:
    sequence_numbers = [
        event["eventSequenceNumber"]
        for event in events
        if event["recorderInstanceIdentifier"] == instance
    ]
    if sequence_numbers != sorted(sequence_numbers) or len(sequence_numbers) != len(set(sequence_numbers)):
        raise SystemExit("evidence-invalid")
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

has_live_owned_state() {
  [[ "$APP_INSTALLED_BY_RUN" == "yes" \
    || "$LAUNCH_AGENT_INSTALLED_BY_RUN" == "yes" \
    || "$SERVICE_BOOTSTRAPPED_BY_RUN" == "yes" \
    || "$RECORDER_BOOTSTRAPPED_BY_RUN" == "yes" \
    || -n "$APP_PID" \
    || -n "$SERVICE_PID" \
    || -n "$RECORDER_PID" ]]
}

cleanup_owned_state() {
  trap - EXIT INT TERM HUP
  if ! has_live_owned_state; then
    [[ -r "$CHECKPOINT_FILE" ]] && load_checkpoint 2>/dev/null || true
  fi

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
  CHECKPOINT_FAILURE_FATAL="no"
  write_checkpoint "cleanup" "cleaned" 2>/dev/null || true
  CHECKPOINT_FAILURE_FATAL="yes"
}

restore_real_hermes_after_final_decision() {
  resume_real_hermes_recorded_pids
}

cleanup() {
  [[ "$FINISHED" == "yes" ]] && return 0
  cleanup_owned_state
  finish_result
  restore_real_hermes_after_final_decision
  FINISHED="yes"
}

trap cleanup EXIT
trap 'RESULT[M14_003_RESULT]=FAIL; exit 130' INT TERM HUP

prepare() {
  set_default_results
  mkdir -p "$ARTIFACT_DIR" "$RUNTIME_ROOT"
  write_real_home_integrity_snapshot "$INTEGRITY_BEFORE"
  record_phase_marker "REAL_HOME_BASELINE_CAPTURED" 2>/dev/null || true
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

  stop_real_hermes_recorded_pids
  print_quiescence_diagnostics
  write_checkpoint "prepare" "real-hermes-quiesced"

  install_recorder_launch_agent || fail "${RECORDER_FAILURE_REASON:-recorder-not-ready}"
  verify_recorder_ready || fail "${RECORDER_FAILURE_REASON:-recorder-not-ready}"
  record_power_log_prepare_checkpoint || fail "power-log-boundary-invalid"
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
  if ! load_checkpoint 2>/dev/null; then
    print -u2 "error: missing or invalid durable checkpoint"
    RESULT[M14_003_RESULT]=FAIL
    trap - EXIT INT TERM HUP
    write_result
    FINISHED="yes"
    exit 1
  fi
  local checkpoint_run_id checkpoint_status
  checkpoint_run_id="$(checkpoint_field runIdentifier)"
  checkpoint_status="$(checkpoint_field status)"
  [[ "$checkpoint_run_id" == "$RUN_ID" ]] || fail "run-id-mismatch"
  [[ "$checkpoint_status" == "waiting-for-manual-sleep" ]] || fail "stale or duplicate resume checkpoint"
  write_checkpoint "resume" "resuming"
  validate_resume_recorder_identity || timeout_fail "${RECORDER_FAILURE_REASON:-recorder-identity-invalid}"

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

  local system_power_verify_error
  system_power_verify_error="$(verify_system_power_log_evidence 2>&1)" || {
    case "$system_power_verify_error" in
      system-sleep-missing|system-wake-missing|invalid-system-event-order|power-log-boundary-invalid|invalid-uptime-evidence)
        timeout_fail "$system_power_verify_error"
        ;;
      *)
        timeout_fail "power-log-boundary-invalid"
        ;;
    esac
  }
  verify_recorder_evidence >/dev/null 2>&1 || true
  RESULT[REAL_SLEEP_DETECTED]=yes
  RESULT[REAL_WAKE_DETECTED]=yes
  RESULT[WAKE_TIMEOUT_OCCURRED]=no
  verify_real_hermes_quiescence_complete || fail "real Hermes quiescence checkpoint incomplete"

  if [[ -z "$(pid_for_exact_executable "$APP_EXECUTABLE" || true)" ]]; then
    launch_app || fail "app relaunch after wake failed"
  fi
  post_wake_validation || fail "post-wake validation failed"
  discover_agent_status
  cleanup
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
  restore_real_hermes_after_final_decision
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
    diagnose-power-evidence)
      trap - EXIT INT TERM HUP
      diagnose_power_evidence
      FINISHED="yes"
      exit $?
      ;;
    "")
      set_default_results
      mkdir -p "$ARTIFACT_DIR"
      RESULT[M14_003_RESULT]=OPT_IN_REQUIRED
      mark_pre_start_skips
      trap - EXIT INT TERM HUP
      write_result
      FINISHED="yes"
      usage
      exit 2
      ;;
    *)
      set_default_results
      mkdir -p "$ARTIFACT_DIR"
      RESULT[M14_003_RESULT]=FAIL
      mark_pre_start_skips
      trap - EXIT INT TERM HUP
      write_result
      FINISHED="yes"
      usage
      exit 1
      ;;
  esac
}

main "$@"
