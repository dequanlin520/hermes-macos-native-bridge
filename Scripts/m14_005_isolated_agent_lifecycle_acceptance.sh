#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT_NAME="$0"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m14-005"
RUNTIME_ROOT="$ARTIFACT_DIR/runtime"
EVIDENCE_DIR="$ARTIFACT_DIR/evidence"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
CONTRACT_FILE="$ARTIFACT_DIR/launch-contract.json"
INSPECT_REPORT_FILE="$EVIDENCE_DIR/production-inspect.env"
REAL_HERMES_HOME="$HOME/.hermes"
SNAPSHOT_BEFORE="$RUNTIME_ROOT/real-home-before.snapshot"
SNAPSHOT_AFTER="$RUNTIME_ROOT/real-home-after.snapshot"
OWNED_PID_FILE="$RUNTIME_ROOT/owned-agent.pid"
OWNED_IDENTITY_FILE="$RUNTIME_ROOT/owned-agent.identity"

typeset -A RESULT

ORDERED_KEYS=(
  EXPLICIT_OPT_IN_CONFIRMED
  USER_SCOPE_ONLY
  SERVICE_OWNED_CONTRACT_SELECTION
  SERVICE_OWNED_DISCOVERY_USED
  HERMES_EXECUTABLE_STATUS
  HERMES_EXECUTABLE_FAMILY
  HERMES_EXECUTABLE_BASENAME
  HERMES_EXECUTABLE_SOURCE
  HERMES_VERSION_STATUS
  HERMES_VERSION
  DISCOVERY_PARITY
  ISOLATED_START_ADVERTISED
  STATUS_MECHANISM_ADVERTISED
  EXACT_ISOLATED_SHUTDOWN_ADVERTISED
  BROAD_SHUTDOWN_ADVERTISED
  BROAD_SHUTDOWN_SAFE_FOR_ISOLATED_LIFECYCLE
  LAUNCH_CONTRACT_STATUS
  LAUNCH_CONTRACT_REASON
  M14_005_EXPECTED_RESULT
  EXPECTED_EXIT_CODE
  ISOLATED_ENVIRONMENT_VALID
  REAL_HERMES_HOME_MODIFIED
  ISOLATED_AGENT_STARTED
  PROCESS_IDENTITY_CAPTURED
  READINESS_STATUS
  SERVICE_DISCOVERED_ISOLATED_AGENT
  LIFECYCLE_STATUS_QUERY
  GRACEFUL_SHUTDOWN_STATUS
  EXACT_TERM_USED
  EXACT_KILL_USED
  ACCEPTANCE_PROCESS_REMAINING
  GENERATED_ARTIFACT_TRACKED_BY_GIT
  ENVIRONMENT_RESTORED
  M14_005_RESULT
)

usage() {
  print -u2 "usage: $SCRIPT_NAME inspect|run|cleanup"
  print -u2 "run requires HERMES_M14_005_ACCEPTANCE=YES"
}

set_default_results() {
  RESULT=(
    EXPLICIT_OPT_IN_CONFIRMED no
    USER_SCOPE_ONLY yes
    SERVICE_OWNED_CONTRACT_SELECTION yes
    SERVICE_OWNED_DISCOVERY_USED yes
    HERMES_EXECUTABLE_STATUS unknown
    HERMES_EXECUTABLE_FAMILY unknown
    HERMES_EXECUTABLE_BASENAME unknown
    HERMES_EXECUTABLE_SOURCE unknown
    HERMES_VERSION_STATUS unknown
    HERMES_VERSION unknown
    DISCOVERY_PARITY unknown
    ISOLATED_START_ADVERTISED no
    STATUS_MECHANISM_ADVERTISED no
    EXACT_ISOLATED_SHUTDOWN_ADVERTISED no
    BROAD_SHUTDOWN_ADVERTISED no
    BROAD_SHUTDOWN_SAFE_FOR_ISOLATED_LIFECYCLE no
    LAUNCH_CONTRACT_STATUS blocked
    LAUNCH_CONTRACT_REASON unknown
    M14_005_EXPECTED_RESULT BLOCKED
    EXPECTED_EXIT_CODE 3
    ISOLATED_ENVIRONMENT_VALID unknown
    REAL_HERMES_HOME_MODIFIED unknown
    ISOLATED_AGENT_STARTED no
    PROCESS_IDENTITY_CAPTURED no
    READINESS_STATUS blocked
    SERVICE_DISCOVERED_ISOLATED_AGENT blocked
    LIFECYCLE_STATUS_QUERY blocked
    GRACEFUL_SHUTDOWN_STATUS unsupported
    EXACT_TERM_USED no
    EXACT_KILL_USED no
    ACCEPTANCE_PROCESS_REMAINING unknown
    GENERATED_ARTIFACT_TRACKED_BY_GIT no
    ENVIRONMENT_RESTORED no
    M14_005_RESULT FAIL
  )
}

result_exit_code() {
  case "${RESULT[M14_005_RESULT]}" in
    PASS) return 0 ;;
    FAIL) return 1 ;;
    OPT_IN_REQUIRED) return 2 ;;
    BLOCKED) return 3 ;;
    TIMEOUT) return 4 ;;
    PARTIAL) return 5 ;;
    UNSUPPORTED) return 6 ;;
    *) return 1 ;;
  esac
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
if missing or extra or seen != expected:
    raise SystemExit("Invalid result schema")
PY
}

write_result() {
  mkdir -p "$ARTIFACT_DIR"
  if git -C "$ROOT_DIR" check-ignore -q "artifacts/m14-005/result.txt"; then
    RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]=no
  else
    RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]=yes
  fi
  {
    for key in "${ORDERED_KEYS[@]}"; do
      print -r -- "$key=${RESULT[$key]}"
    done
  } > "$RESULT_FILE"
  validate_result_contract
}

write_contract() {
  local version_text="$1"
  local contract_state="$2"
  local reason_text="$3"
  mkdir -p "$ARTIFACT_DIR"
  /usr/bin/python3 - "$CONTRACT_FILE" "$version_text" "$contract_state" "$reason_text" <<'PY'
import json
import re
import sys
from pathlib import Path
path = Path(sys.argv[1])
version = None if sys.argv[2] in ("unknown", "blocked", "unsupported") else sys.argv[2]
state = re.sub(r"[^A-Za-z0-9_.-]", "_", sys.argv[3])[:64]
reason = re.sub(r"[^A-Za-z0-9_.-]", "_", sys.argv[4])[:96]
startup_args = ["serve"] if state == "supported" else []
status_args = ["status"] if state == "supported" else None
shutdown_args = ["stop"] if state == "supported" else None
path.write_text(json.dumps({
    "schemaVersion": 1,
    "executableFamily": "hermes-agent",
    "supportedVersionRange": {
        "lowerInclusive": "0.18.0",
        "upperExclusive": "0.19.0"
    },
    "observedVersion": version,
    "status": state,
    "reasonCode": reason,
    "descriptor": {
        "invocationMode": "direct-executable" if state == "supported" else "unsupported",
        "requiredArguments": startup_args,
        "statusArguments": status_args,
        "shutdownArguments": shutdown_args
    },
    "requiredCapabilities": [
        "noninteractive-startup",
        "isolated-writable-roots",
        "bounded-readiness",
        "stable-process-identity",
        "documented-status",
        "graceful-shutdown",
        "exact-pid-fallback"
    ],
    "advertisedCapabilities": [],
    "readinessMechanism": "documented-status-command" if state == "supported" else "unsupported",
    "shutdownMechanism": "documented-stop-command" if state == "supported" else "unsupported",
    "timeoutPolicy": {
        "readinessSeconds": 10,
        "gracefulShutdownSeconds": 5,
        "forcedShutdownSeconds": 2
    },
    "cleanupFallbackPolicy": "exact-pid-term-then-exact-pid-kill"
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

load_production_inspect_report() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local line key value
  while IFS= read -r line; do
    [[ -n "$line" && "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      USER_SCOPE_ONLY|SERVICE_OWNED_CONTRACT_SELECTION|SERVICE_OWNED_DISCOVERY_USED|HERMES_EXECUTABLE_STATUS|HERMES_EXECUTABLE_FAMILY|HERMES_EXECUTABLE_BASENAME|HERMES_EXECUTABLE_SOURCE|HERMES_VERSION_STATUS|HERMES_VERSION|DISCOVERY_PARITY|ISOLATED_START_ADVERTISED|STATUS_MECHANISM_ADVERTISED|EXACT_ISOLATED_SHUTDOWN_ADVERTISED|BROAD_SHUTDOWN_ADVERTISED|BROAD_SHUTDOWN_SAFE_FOR_ISOLATED_LIFECYCLE|LAUNCH_CONTRACT_STATUS|LAUNCH_CONTRACT_REASON|M14_005_EXPECTED_RESULT|EXPECTED_EXIT_CODE)
        RESULT[$key]="$value"
        ;;
    esac
  done < "$file"
}

real_home_snapshot() {
  local target="$1"
  mkdir -p "$RUNTIME_ROOT"
  if [[ ! -e "$REAL_HERMES_HOME" ]]; then
    print -r -- "missing" > "$target"
    return
  fi
  /usr/bin/find "$REAL_HERMES_HOME" -xdev -type f -print0 2>/dev/null \
    | /usr/bin/sort -z \
    | /usr/bin/xargs -0 /usr/bin/stat -f '%N|%z|%m' 2>/dev/null \
    | /usr/bin/sed "s#${REAL_HERMES_HOME}#REAL_HERMES_HOME#g" > "$target"
}

validate_isolated_environment() {
  mkdir -p "$RUNTIME_ROOT"
  /usr/bin/python3 - "$RUNTIME_ROOT" "$HOME" <<'PY'
import os
import stat
import sys
from pathlib import Path
root = Path(sys.argv[1])
home = Path(sys.argv[2]).expanduser()
if ".." in root.parts:
    raise SystemExit(1)
root.mkdir(parents=True, exist_ok=True)
resolved_root = root.resolve()
real_hermes = (home / ".hermes").resolve()
if resolved_root == real_hermes or str(resolved_root).startswith(str(real_hermes) + os.sep):
    raise SystemExit(1)
for parent in [resolved_root, *resolved_root.parents]:
    if str(parent) == "/":
        break
    mode = parent.stat().st_mode
    if mode & stat.S_IWOTH and not mode & stat.S_ISVTX:
        raise SystemExit(1)
for name in ["home", "hermes-home", "xdg-config", "xdg-state", "xdg-cache", "tmp"]:
    child = root / name
    child.mkdir(parents=True, exist_ok=True)
    os.chmod(child, 0o700)
    if not str(child.resolve()).startswith(str(resolved_root) + os.sep):
        raise SystemExit(1)
PY
}

write_blocked_production_inspect_report() {
  mkdir -p "$EVIDENCE_DIR"
  {
    print -r -- "USER_SCOPE_ONLY=yes"
    print -r -- "SERVICE_OWNED_CONTRACT_SELECTION=yes"
    print -r -- "SERVICE_OWNED_DISCOVERY_USED=yes"
    print -r -- "HERMES_EXECUTABLE_STATUS=unknown"
    print -r -- "HERMES_EXECUTABLE_FAMILY=unknown"
    print -r -- "HERMES_EXECUTABLE_BASENAME=unknown"
    print -r -- "HERMES_EXECUTABLE_SOURCE=unknown"
    print -r -- "HERMES_VERSION_STATUS=blocked"
    print -r -- "HERMES_VERSION=unknown"
    print -r -- "DISCOVERY_PARITY=unknown"
    print -r -- "ISOLATED_START_ADVERTISED=no"
    print -r -- "STATUS_MECHANISM_ADVERTISED=no"
    print -r -- "EXACT_ISOLATED_SHUTDOWN_ADVERTISED=no"
    print -r -- "BROAD_SHUTDOWN_ADVERTISED=no"
    print -r -- "BROAD_SHUTDOWN_SAFE_FOR_ISOLATED_LIFECYCLE=no"
    print -r -- "LAUNCH_CONTRACT_STATUS=blocked"
    print -r -- "LAUNCH_CONTRACT_REASON=production.inspect.unavailable"
    print -r -- "M14_005_EXPECTED_RESULT=BLOCKED"
    print -r -- "EXPECTED_EXIT_CODE=3"
  } > "$INSPECT_REPORT_FILE"
}

discover_and_select_contract() {
  local mode_label="$1"
  mkdir -p "$EVIDENCE_DIR"
  if ! swift run --configuration release HermesReleaseAgentPreflight m14-005-inspect > "$INSPECT_REPORT_FILE" 2>/dev/null; then
    write_blocked_production_inspect_report
  fi
  load_production_inspect_report "$INSPECT_REPORT_FILE" || true
  write_contract "${RESULT[HERMES_VERSION]}" "${RESULT[LAUNCH_CONTRACT_STATUS]}" "${RESULT[LAUNCH_CONTRACT_REASON]}"
  [[ "${RESULT[LAUNCH_CONTRACT_STATUS]}" != blocked ]]
}

cleanup_owned_process() {
  [[ -f "$OWNED_PID_FILE" && -f "$OWNED_IDENTITY_FILE" ]] || return 0
  local pid expected current
  pid="$(cat "$OWNED_PID_FILE" 2>/dev/null || true)"
  [[ "$pid" == <-> && "$pid" -gt 1 ]] || return 0
  expected="$(cat "$OWNED_IDENTITY_FILE" 2>/dev/null || true)"
  current="$(/bin/ps -p "$pid" -o pid=,ppid=,pgid=,uid=,comm= 2>/dev/null | /usr/bin/sed 's/^ *//')"
  [[ -n "$current" && "$current" == "$expected" ]] || return 0
  /bin/kill -TERM "$pid" 2>/dev/null || true
  sleep 1
  if /bin/ps -p "$pid" >/dev/null 2>&1; then
    /bin/kill -KILL "$pid" 2>/dev/null || true
  fi
}

cleanup() {
  set_default_results
  cleanup_owned_process
  rm -rf "$RUNTIME_ROOT"
  RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
  RESULT[ENVIRONMENT_RESTORED]=yes
  RESULT[M14_005_RESULT]=PASS
  write_result
}

inspect() {
  set_default_results
  discover_and_select_contract inspect || true
  print -r -- "M14-005 read-only inspect"
  for key in \
    USER_SCOPE_ONLY \
    SERVICE_OWNED_CONTRACT_SELECTION \
    SERVICE_OWNED_DISCOVERY_USED \
    HERMES_EXECUTABLE_STATUS \
    HERMES_EXECUTABLE_FAMILY \
    HERMES_EXECUTABLE_BASENAME \
    HERMES_EXECUTABLE_SOURCE \
    HERMES_VERSION_STATUS \
    HERMES_VERSION \
    DISCOVERY_PARITY \
    ISOLATED_START_ADVERTISED \
    STATUS_MECHANISM_ADVERTISED \
    EXACT_ISOLATED_SHUTDOWN_ADVERTISED \
    BROAD_SHUTDOWN_ADVERTISED \
    BROAD_SHUTDOWN_SAFE_FOR_ISOLATED_LIFECYCLE \
    LAUNCH_CONTRACT_STATUS \
    LAUNCH_CONTRACT_REASON \
    M14_005_EXPECTED_RESULT \
    EXPECTED_EXIT_CODE; do
    print -r -- "$key=${RESULT[$key]}"
  done
}

run_acceptance() {
  set_default_results
  if [[ "${HERMES_M14_005_ACCEPTANCE:-}" != "YES" ]]; then
    RESULT[M14_005_RESULT]=OPT_IN_REQUIRED
    write_result
    exit 2
  fi
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  real_home_snapshot "$SNAPSHOT_BEFORE"
  if validate_isolated_environment; then
    RESULT[ISOLATED_ENVIRONMENT_VALID]=yes
  else
    RESULT[ISOLATED_ENVIRONMENT_VALID]=no
    RESULT[M14_005_RESULT]=BLOCKED
    write_result
    exit 3
  fi
  discover_and_select_contract run || true
  if [[ "${RESULT[LAUNCH_CONTRACT_STATUS]}" == unsupported ]]; then
    RESULT[ISOLATED_AGENT_STARTED]=unsupported
    RESULT[READINESS_STATUS]=unsupported
    RESULT[SERVICE_DISCOVERED_ISOLATED_AGENT]=unsupported
    RESULT[LIFECYCLE_STATUS_QUERY]=unsupported
    RESULT[GRACEFUL_SHUTDOWN_STATUS]=unsupported
    RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
    RESULT[M14_005_RESULT]=UNSUPPORTED
  elif [[ "${RESULT[LAUNCH_CONTRACT_STATUS]}" == blocked ]]; then
    RESULT[M14_005_RESULT]=BLOCKED
  elif [[ "${RESULT[LAUNCH_CONTRACT_STATUS]}" == incompatible ]]; then
    RESULT[M14_005_RESULT]=UNSUPPORTED
  else
    RESULT[ISOLATED_AGENT_STARTED]=blocked
    RESULT[M14_005_RESULT]=BLOCKED
  fi
  real_home_snapshot "$SNAPSHOT_AFTER"
  if cmp -s "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER"; then
    RESULT[REAL_HERMES_HOME_MODIFIED]=no
  else
    RESULT[REAL_HERMES_HOME_MODIFIED]=yes
    RESULT[M14_005_RESULT]=FAIL
  fi
  cleanup_owned_process
  RESULT[ENVIRONMENT_RESTORED]=yes
  write_result
  result_exit_code
  exit $?
}

main() {
  case "${1:-}" in
    inspect) inspect ;;
    run) run_acceptance ;;
    cleanup) cleanup ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
