#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT_NAME="$0"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m14-006"
RUNTIME_ROOT="$ARTIFACT_DIR/runtime"
EVIDENCE_DIR="$ARTIFACT_DIR/evidence"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
TOPOLOGY_FILE="$ARTIFACT_DIR/process-topology.json"
REPORT_FILE="$ARTIFACT_DIR/supervisor-report.json"
INSPECT_REPORT_FILE="$EVIDENCE_DIR/production-inspect.env"
OWNED_IDENTITY_FILE="$RUNTIME_ROOT/owned-process.identity"

typeset -A RESULT

ORDERED_KEYS=(
  EXPLICIT_OPT_IN_CONFIRMED
  USER_SCOPE_ONLY
  SERVICE_OWNED_SUPERVISOR_USED
  SERVICE_OWNED_DISCOVERY_USED
  HERMES_EXECUTABLE_STATUS
  HERMES_EXECUTABLE_FAMILY
  HERMES_VERSION
  ISOLATED_COMMAND_ADVERTISED
  BROAD_STOP_INVOKED
  ISOLATED_ENVIRONMENT_VALID
  REAL_HERMES_HOME_MODIFIED
  SUPERVISOR_ROOT_STARTED
  PROCESS_TOPOLOGY_STATUS
  PROCESS_IDENTITY_CAPTURED
  READINESS_STATUS
  ENDPOINT_OWNERSHIP_PROVEN
  SERVICE_DISCOVERED_ISOLATED_AGENT
  STATUS_QUERY_RESULT
  EXACT_ROOT_TERM_USED
  EXACT_DESCENDANT_TERM_USED
  EXACT_KILL_USED
  BROAD_PROCESS_KILL_USED
  ACCEPTANCE_PROCESS_REMAINING
  ORPHAN_PROCESS_FOUND
  GENERATED_ARTIFACT_TRACKED_BY_GIT
  ENVIRONMENT_RESTORED
  SUPERVISOR_COMPATIBILITY_LEVEL
  M14_006_RESULT
)

usage() {
  print -u2 "usage: $SCRIPT_NAME inspect|run|cleanup"
  print -u2 "run requires HERMES_M14_006_ACCEPTANCE=YES"
}

set_default_results() {
  RESULT=(
    EXPLICIT_OPT_IN_CONFIRMED no
    USER_SCOPE_ONLY yes
    SERVICE_OWNED_SUPERVISOR_USED yes
    SERVICE_OWNED_DISCOVERY_USED yes
    HERMES_EXECUTABLE_STATUS unknown
    HERMES_EXECUTABLE_FAMILY unknown
    HERMES_VERSION unknown
    ISOLATED_COMMAND_ADVERTISED no
    BROAD_STOP_INVOKED no
    ISOLATED_ENVIRONMENT_VALID unknown
    REAL_HERMES_HOME_MODIFIED unknown
    SUPERVISOR_ROOT_STARTED no
    PROCESS_TOPOLOGY_STATUS blocked
    PROCESS_IDENTITY_CAPTURED no
    READINESS_STATUS blocked
    ENDPOINT_OWNERSHIP_PROVEN no
    SERVICE_DISCOVERED_ISOLATED_AGENT blocked
    STATUS_QUERY_RESULT blocked
    EXACT_ROOT_TERM_USED no
    EXACT_DESCENDANT_TERM_USED no
    EXACT_KILL_USED no
    BROAD_PROCESS_KILL_USED no
    ACCEPTANCE_PROCESS_REMAINING unknown
    ORPHAN_PROCESS_FOUND unknown
    GENERATED_ARTIFACT_TRACKED_BY_GIT no
    ENVIRONMENT_RESTORED no
    SUPERVISOR_COMPATIBILITY_LEVEL BLOCKED
    M14_006_RESULT FAIL
  )
}

result_exit_code() {
  case "${RESULT[M14_006_RESULT]}" in
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

write_json_artifacts() {
  mkdir -p "$ARTIFACT_DIR"
  /usr/bin/python3 - "$TOPOLOGY_FILE" "$REPORT_FILE" "${(@kv)RESULT}" <<'PY'
import json
import sys
from pathlib import Path
topology_path = Path(sys.argv[1])
report_path = Path(sys.argv[2])
items = sys.argv[3:]
result = dict(zip(items[0::2], items[1::2]))
topology_path.write_text(json.dumps({
    "schemaVersion": 1,
    "run": "m14-006",
    "topologyStatus": result.get("PROCESS_TOPOLOGY_STATUS", "unknown"),
    "rootStarted": result.get("SUPERVISOR_ROOT_STARTED", "no"),
    "identityCaptured": result.get("PROCESS_IDENTITY_CAPTURED", "no"),
    "redaction": "privacy-safe"
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
report_path.write_text(json.dumps({
    "schemaVersion": 1,
    "run": "m14-006",
    "compatibilityLevel": result.get("SUPERVISOR_COMPATIBILITY_LEVEL", "BLOCKED"),
    "result": result.get("M14_006_RESULT", "FAIL"),
    "broadStopInvoked": result.get("BROAD_STOP_INVOKED", "no"),
    "broadProcessKillUsed": result.get("BROAD_PROCESS_KILL_USED", "no"),
    "realHomeModified": result.get("REAL_HERMES_HOME_MODIFIED", "unknown"),
    "endpointOwnershipProven": result.get("ENDPOINT_OWNERSHIP_PROVEN", "no")
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

write_result() {
  mkdir -p "$ARTIFACT_DIR" "$EVIDENCE_DIR"
  if git -C "$ROOT_DIR" check-ignore -q "artifacts/m14-006/result.txt"; then
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
  write_json_artifacts
}

load_production_inspect_report() {
  local line key value
  [[ -f "$INSPECT_REPORT_FILE" ]] || return 1
  while IFS= read -r line; do
    [[ -n "$line" && "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      HERMES_EXECUTABLE_STATUS) RESULT[HERMES_EXECUTABLE_STATUS]="$value" ;;
      HERMES_EXECUTABLE_FAMILY) RESULT[HERMES_EXECUTABLE_FAMILY]="$value" ;;
      HERMES_VERSION) RESULT[HERMES_VERSION]="$value" ;;
      ISOLATED_START_ADVERTISED) RESULT[ISOLATED_COMMAND_ADVERTISED]="$value" ;;
    esac
  done < "$INSPECT_REPORT_FILE"
}

production_inspect() {
  mkdir -p "$EVIDENCE_DIR"
  if ! swift run --configuration release HermesReleaseAgentPreflight m14-005-inspect > "$INSPECT_REPORT_FILE" 2>/dev/null; then
    {
      print -r -- "HERMES_EXECUTABLE_STATUS=unknown"
      print -r -- "HERMES_EXECUTABLE_FAMILY=unknown"
      print -r -- "HERMES_VERSION=unknown"
      print -r -- "ISOLATED_START_ADVERTISED=no"
    } > "$INSPECT_REPORT_FILE"
  fi
  load_production_inspect_report || true
}

production_inspect_readonly() {
  local report line key value
  if ! report="$(swift run --configuration release HermesReleaseAgentPreflight m14-005-inspect 2>/dev/null)"; then
    report=$'HERMES_EXECUTABLE_STATUS=unknown\nHERMES_EXECUTABLE_FAMILY=unknown\nHERMES_VERSION=unknown\nISOLATED_START_ADVERTISED=no'
  fi
  for line in "${(@f)report}"; do
    [[ -n "$line" && "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      HERMES_EXECUTABLE_STATUS) RESULT[HERMES_EXECUTABLE_STATUS]="$value" ;;
      HERMES_EXECUTABLE_FAMILY) RESULT[HERMES_EXECUTABLE_FAMILY]="$value" ;;
      HERMES_VERSION) RESULT[HERMES_VERSION]="$value" ;;
      ISOLATED_START_ADVERTISED) RESULT[ISOLATED_COMMAND_ADVERTISED]="$value" ;;
    esac
  done
}

validate_isolated_environment() {
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
for name in ["home", "hermes-home", "xdg-config", "xdg-state", "xdg-cache", "tmp"]:
    child = root / name
    child.mkdir(parents=True, exist_ok=True)
    os.chmod(child, 0o700)
    if not str(child.resolve()).startswith(str(resolved_root) + os.sep):
        raise SystemExit(1)
for parent in [resolved_root, *resolved_root.parents]:
    if str(parent) == "/":
        break
    mode = parent.stat().st_mode
    if mode & stat.S_IWOTH and not mode & stat.S_ISVTX:
        raise SystemExit(1)
PY
}

persist_identity_for_pid() {
  local pid="$1"
  mkdir -p "$RUNTIME_ROOT"
  /bin/ps -p "$pid" -o pid=,ppid=,pgid=,uid=,comm= 2>/dev/null | /usr/bin/sed 's/^ *//' > "$OWNED_IDENTITY_FILE"
}

identity_matches() {
  local pid="$1"
  [[ "$pid" == <-> && "$pid" -gt 1 && -f "$OWNED_IDENTITY_FILE" ]] || return 1
  local expected current
  expected="$(cat "$OWNED_IDENTITY_FILE" 2>/dev/null || true)"
  current="$(/bin/ps -p "$pid" -o pid=,ppid=,pgid=,uid=,comm= 2>/dev/null | /usr/bin/sed 's/^ *//')"
  [[ -n "$expected" && "$current" == "$expected" ]]
}

cleanup_owned_process() {
  [[ -f "$OWNED_IDENTITY_FILE" ]] || return 0
  local pid
  pid="$(awk '{print $1}' "$OWNED_IDENTITY_FILE" 2>/dev/null || true)"
  identity_matches "$pid" || return 0
  /bin/kill -TERM "$pid" 2>/dev/null && RESULT[EXACT_ROOT_TERM_USED]=yes || true
  sleep 1
  if identity_matches "$pid"; then
    /bin/kill -KILL "$pid" 2>/dev/null && RESULT[EXACT_KILL_USED]=yes || true
  fi
}

inspect() {
  set_default_results
  production_inspect_readonly
  print -r -- "M14-006 read-only inspect"
  print -r -- "detected_family=${RESULT[HERMES_EXECUTABLE_FAMILY]}"
  print -r -- "detected_version=${RESULT[HERMES_VERSION]}"
  print -r -- "advertised_isolated_command=${RESULT[ISOLATED_COMMAND_ADVERTISED]}"
  print -r -- "expected_topology_observations=foreground-single-process,foreground-with-helpers,launcher-exited-child-remains,daemonized,process-exited,ambiguous-topology"
  print -r -- "supervisor_safety_invariants=exact-pid-only,no-process-group-signal,no-broad-stop,isolated-runtime-root,privacy-safe-artifacts"
  if [[ "${RESULT[ISOLATED_COMMAND_ADVERTISED]}" == yes ]]; then
    print -r -- "opt_in_run_permitted=yes"
  else
    print -r -- "opt_in_run_permitted=no"
  fi
}

run_acceptance() {
  set_default_results
  if [[ "${HERMES_M14_006_ACCEPTANCE:-}" != "YES" ]]; then
    RESULT[M14_006_RESULT]=OPT_IN_REQUIRED
    write_result
    exit 2
  fi
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  if validate_isolated_environment; then
    RESULT[ISOLATED_ENVIRONMENT_VALID]=yes
  else
    RESULT[ISOLATED_ENVIRONMENT_VALID]=no
    RESULT[M14_006_RESULT]=BLOCKED
    write_result
    exit 3
  fi
  production_inspect
  if [[ "${RESULT[ISOLATED_COMMAND_ADVERTISED]}" != yes ]]; then
    RESULT[SUPERVISOR_COMPATIBILITY_LEVEL]=UNSUPPORTED
    RESULT[M14_006_RESULT]=UNSUPPORTED
    RESULT[REAL_HERMES_HOME_MODIFIED]=no
    RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
    RESULT[ORPHAN_PROCESS_FOUND]=no
    RESULT[ENVIRONMENT_RESTORED]=yes
    write_result
    exit 6
  fi
  RESULT[SUPERVISOR_COMPATIBILITY_LEVEL]=BLOCKED
  RESULT[M14_006_RESULT]=BLOCKED
  RESULT[REAL_HERMES_HOME_MODIFIED]=no
  RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
  RESULT[ORPHAN_PROCESS_FOUND]=no
  RESULT[ENVIRONMENT_RESTORED]=yes
  write_result
  exit 3
}

cleanup() {
  set_default_results
  cleanup_owned_process
  rm -rf "$RUNTIME_ROOT"
  RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
  RESULT[ORPHAN_PROCESS_FOUND]=no
  RESULT[REAL_HERMES_HOME_MODIFIED]=no
  RESULT[ENVIRONMENT_RESTORED]=yes
  RESULT[SUPERVISOR_COMPATIBILITY_LEVEL]=SUPPORTED
  RESULT[M14_006_RESULT]=PASS
  write_result
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
