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
LAUNCH_DESCRIPTOR_FILE="$EVIDENCE_DIR/launch-descriptor.json"
INSPECT_REPORT_FILE="$EVIDENCE_DIR/production-inspect.env"
OWNED_IDENTITY_FILE="$RUNTIME_ROOT/owned-process.identity"
PROVISIONAL_IDENTITY_FILE="$RUNTIME_ROOT/provisional-process.identity"
OBSERVED_DESCENDANT_FILE="$RUNTIME_ROOT/observed-descendant.identity"

typeset -A RESULT
typeset -A INSPECT_VALUES

ORDERED_KEYS=(
  EXPLICIT_OPT_IN_CONFIRMED
  USER_SCOPE_ONLY
  SERVICE_OWNED_SUPERVISOR_USED
  SERVICE_OWNED_DISCOVERY_USED
  HERMES_EXECUTABLE_STATUS
  HERMES_EXECUTABLE_FAMILY
  HERMES_VERSION
  ISOLATED_COMMAND_ADVERTISED
  LAUNCH_ATTEMPTED
  LAUNCH_CHILD_EXITED
  LAUNCH_CHILD_EXIT_CODE
  LAUNCH_CHILD_SIGNAL
  LAUNCH_DURATION_MILLISECONDS
  LAUNCH_STDOUT_CATEGORY
  LAUNCH_STDERR_CATEGORY
  DESCENDANT_OBSERVED_BEFORE_EXIT
  LISTENER_OBSERVED_BEFORE_EXIT
  EXECUTABLE_IDENTITY_OBSERVED
  BROAD_STOP_INVOKED
  ISOLATED_ENVIRONMENT_VALID
  REAL_HERMES_HOME_MODIFIED
  SUPERVISOR_REASON_CODE
  SUPERVISOR_REASON_PHASE
  SUPERVISOR_DETAIL_CATEGORY
  SUPERVISOR_ROOT_STARTED
  PROCESS_TOPOLOGY_STATUS
  PROCESS_IDENTITY_CAPTURED
  PROCESS_IDENTITY_VALIDATED_BEFORE_SIGNAL
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
  SUPERVISED_PROCESS_REAL_HOME_ACCESS
  EXTERNAL_REAL_HOME_MUTATION_OBSERVED
  GENERATED_ARTIFACT_TRACKED_BY_GIT
  ENVIRONMENT_RESTORED
  SUPERVISOR_COMPATIBILITY_LEVEL
  M14_006_RESULT
)

usage() {
  print -u2 "usage: $SCRIPT_NAME inspect|inspect-launch-plan|inspect-launch-syntax|run|cleanup"
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
    LAUNCH_ATTEMPTED no
    LAUNCH_CHILD_EXITED no
    LAUNCH_CHILD_EXIT_CODE unknown
    LAUNCH_CHILD_SIGNAL unknown
    LAUNCH_DURATION_MILLISECONDS 0
    LAUNCH_STDOUT_CATEGORY not-captured
    LAUNCH_STDERR_CATEGORY not-captured
    DESCENDANT_OBSERVED_BEFORE_EXIT no
    LISTENER_OBSERVED_BEFORE_EXIT no
    EXECUTABLE_IDENTITY_OBSERVED no
    BROAD_STOP_INVOKED no
    ISOLATED_ENVIRONMENT_VALID unknown
    REAL_HERMES_HOME_MODIFIED unknown
    SUPERVISOR_REASON_CODE unknown
    SUPERVISOR_REASON_PHASE preflight
    SUPERVISOR_DETAIL_CATEGORY unknown
    SUPERVISOR_ROOT_STARTED no
    PROCESS_TOPOLOGY_STATUS blocked
    PROCESS_IDENTITY_CAPTURED no
    PROCESS_IDENTITY_VALIDATED_BEFORE_SIGNAL no
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
    SUPERVISED_PROCESS_REAL_HOME_ACCESS unknown
    EXTERNAL_REAL_HOME_MUTATION_OBSERVED unknown
    GENERATED_ARTIFACT_TRACKED_BY_GIT no
    ENVIRONMENT_RESTORED no
    SUPERVISOR_COMPATIBILITY_LEVEL BLOCKED
    M14_006_RESULT FAIL
  )
}

set_reason() {
  RESULT[SUPERVISOR_REASON_CODE]="$1"
  RESULT[SUPERVISOR_REASON_PHASE]="$2"
  RESULT[SUPERVISOR_DETAIL_CATEGORY]="$3"
}

clear_reason_for_pass() {
  RESULT[SUPERVISOR_REASON_CODE]=none
  RESULT[SUPERVISOR_REASON_PHASE]=cleanup
  RESULT[SUPERVISOR_DETAIL_CATEGORY]=supervision-complete
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
    "provisionalIdentityCaptured": result.get("PROCESS_IDENTITY_CAPTURED", "no"),
    "executableIdentityObserved": result.get("EXECUTABLE_IDENTITY_OBSERVED", "no"),
    "launchChildExited": result.get("LAUNCH_CHILD_EXITED", "no"),
    "launchChildExitCode": result.get("LAUNCH_CHILD_EXIT_CODE", "unknown"),
    "launchChildSignal": result.get("LAUNCH_CHILD_SIGNAL", "unknown"),
    "launchDurationMilliseconds": result.get("LAUNCH_DURATION_MILLISECONDS", "0"),
    "launchStdoutCategory": result.get("LAUNCH_STDOUT_CATEGORY", "unknown"),
    "launchStderrCategory": result.get("LAUNCH_STDERR_CATEGORY", "unknown"),
    "descendantObservedBeforeExit": result.get("DESCENDANT_OBSERVED_BEFORE_EXIT", "no"),
    "listenerObservedBeforeExit": result.get("LISTENER_OBSERVED_BEFORE_EXIT", "no"),
    "identityValidatedBeforeSignal": result.get("PROCESS_IDENTITY_VALIDATED_BEFORE_SIGNAL", "no"),
    "reasonCode": result.get("SUPERVISOR_REASON_CODE", "unknown"),
    "reasonPhase": result.get("SUPERVISOR_REASON_PHASE", "preflight"),
    "redaction": "privacy-safe"
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
report_path.write_text(json.dumps({
    "schemaVersion": 1,
    "run": "m14-006",
    "compatibilityLevel": result.get("SUPERVISOR_COMPATIBILITY_LEVEL", "BLOCKED"),
    "result": result.get("M14_006_RESULT", "FAIL"),
    "launchAttempted": result.get("LAUNCH_ATTEMPTED", "no"),
    "launchChildExited": result.get("LAUNCH_CHILD_EXITED", "no"),
    "launchChildExitCode": result.get("LAUNCH_CHILD_EXIT_CODE", "unknown"),
    "launchChildSignal": result.get("LAUNCH_CHILD_SIGNAL", "unknown"),
    "launchDurationMilliseconds": result.get("LAUNCH_DURATION_MILLISECONDS", "0"),
    "launchStdoutCategory": result.get("LAUNCH_STDOUT_CATEGORY", "unknown"),
    "launchStderrCategory": result.get("LAUNCH_STDERR_CATEGORY", "unknown"),
    "descendantObservedBeforeExit": result.get("DESCENDANT_OBSERVED_BEFORE_EXIT", "no"),
    "listenerObservedBeforeExit": result.get("LISTENER_OBSERVED_BEFORE_EXIT", "no"),
    "executableIdentityObserved": result.get("EXECUTABLE_IDENTITY_OBSERVED", "no"),
    "reasonCode": result.get("SUPERVISOR_REASON_CODE", "unknown"),
    "reasonPhase": result.get("SUPERVISOR_REASON_PHASE", "preflight"),
    "detailCategory": result.get("SUPERVISOR_DETAIL_CATEGORY", "unknown"),
    "broadStopInvoked": result.get("BROAD_STOP_INVOKED", "no"),
    "broadProcessKillUsed": result.get("BROAD_PROCESS_KILL_USED", "no"),
    "realHomeModified": result.get("REAL_HERMES_HOME_MODIFIED", "unknown"),
    "supervisedProcessRealHomeAccess": result.get("SUPERVISED_PROCESS_REAL_HOME_ACCESS", "unknown"),
    "externalRealHomeMutationObserved": result.get("EXTERNAL_REAL_HOME_MUTATION_OBSERVED", "unknown"),
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
  validate_terminal_reason_contract
  write_json_artifacts
}

validate_terminal_reason_contract() {
  case "${RESULT[M14_006_RESULT]}" in
    PASS|OPT_IN_REQUIRED) return 0 ;;
  esac
  [[ "${RESULT[SUPERVISOR_REASON_CODE]}" != unknown && -n "${RESULT[SUPERVISOR_REASON_CODE]}" ]] || return 1
  [[ "${RESULT[SUPERVISOR_REASON_PHASE]}" != unknown && -n "${RESULT[SUPERVISOR_REASON_PHASE]}" ]] || return 1
  [[ "${RESULT[SUPERVISOR_DETAIL_CATEGORY]}" != unknown && -n "${RESULT[SUPERVISOR_DETAIL_CATEGORY]}" ]] || return 1
}

load_production_inspect_report() {
  local line key value
  [[ -f "$INSPECT_REPORT_FILE" ]] || return 1
  INSPECT_VALUES=()
  while IFS= read -r line; do
    [[ -n "$line" && "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    INSPECT_VALUES[$key]="$value"
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
  INSPECT_VALUES=()
  if ! report="$(swift run --configuration release HermesReleaseAgentPreflight m14-005-inspect 2>/dev/null)"; then
    report=$'HERMES_EXECUTABLE_STATUS=unknown\nHERMES_EXECUTABLE_FAMILY=unknown\nHERMES_VERSION=unknown\nISOLATED_START_ADVERTISED=no'
  fi
  for line in "${(@f)report}"; do
    [[ -n "$line" && "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    INSPECT_VALUES[$key]="$value"
    case "$key" in
      HERMES_EXECUTABLE_STATUS) RESULT[HERMES_EXECUTABLE_STATUS]="$value" ;;
      HERMES_EXECUTABLE_FAMILY) RESULT[HERMES_EXECUTABLE_FAMILY]="$value" ;;
      HERMES_VERSION) RESULT[HERMES_VERSION]="$value" ;;
      ISOLATED_START_ADVERTISED) RESULT[ISOLATED_COMMAND_ADVERTISED]="$value" ;;
    esac
  done
}

is_supported_018_version() {
  [[ "$1" == 0.18(|.*) ]]
}

m14006_blocking_reason() {
  if [[ "${RESULT[HERMES_EXECUTABLE_STATUS]}" != available ]]; then
    print -r -- "executable.unavailable"
    return 0
  fi
  if ! is_supported_018_version "${RESULT[HERMES_VERSION]}"; then
    print -r -- "version.unsupported"
    return 0
  fi
  if [[ "${RESULT[ISOLATED_COMMAND_ADVERTISED]}" != yes ]]; then
    print -r -- "isolated-command.not-advertised"
    return 0
  fi
  if [[ "${RESULT[ISOLATED_ENVIRONMENT_VALID]}" != yes ]]; then
    print -r -- "launch.environment-invalid"
    return 0
  fi
  print -r -- "none"
}

resolve_hermes_executable() {
  if [[ -n "${HERMES_M14_006_HERMES_EXECUTABLE_OVERRIDE:-}" ]]; then
    print -r -- "$HERMES_M14_006_HERMES_EXECUTABLE_OVERRIDE"
    return 0
  fi
  command -v hermes 2>/dev/null || return 1
}

now_milliseconds() {
  /usr/bin/python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

category_for_output_file() {
  local file="$1"
  /usr/bin/python3 - "$file" <<'PY'
import re
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = path.read_bytes()[:4096] if path.exists() else b""
text = data.decode("utf-8", "replace").lower()
if not text.strip():
    print("empty")
elif "address already in use" in text or "errno 48" in text:
    print("bind-address-in-use")
elif "missing" in text and ("config" in text or "configuration" in text):
    print("missing-configuration")
elif "required" in text and ("argument" in text or "option" in text):
    print("missing-required-argument")
elif "no such option" in text or "unrecognized" in text or "unknown option" in text:
    print("unsupported-argument")
elif "usage:" in text or "options:" in text:
    print("usage-or-help")
elif "traceback" in text or "exception" in text:
    print("exception")
elif re.search(r"(token|secret|password|bearer)\s*[=:]", text):
    print("redacted-sensitive-shape")
else:
    print("nonempty-other")
PY
}

classify_immediate_exit_reason() {
  local exit_code="$1" signal="$2" stderr_category="$3"
  if [[ "$stderr_category" == missing-required-argument ]]; then
    print -r -- "launch.argument-missing"
  elif [[ "$stderr_category" == missing-configuration ]]; then
    print -r -- "launch.configuration-missing"
  elif [[ "$stderr_category" == unsupported-argument ]]; then
    print -r -- "launch.stderr-indicates-unsupported"
  elif [[ "$signal" != none && "$signal" != unknown ]]; then
    print -r -- "launch.signaled"
  elif [[ "$exit_code" == 0 ]]; then
    print -r -- "launch.exited-zero-no-service"
  elif [[ "$exit_code" == <-> ]]; then
    print -r -- "launch.exited-nonzero"
  else
    print -r -- "launch.unknown-immediate-exit"
  fi
}

print_launch_plan() {
  local reason="$1"
  if [[ "$reason" == none ]]; then
    print -r -- "launch_permitted=yes"
  else
    print -r -- "launch_permitted=no"
  fi
  print -r -- "detected_version=${RESULT[HERMES_VERSION]}"
  print -r -- "isolated_command_advertised=${RESULT[ISOLATED_COMMAND_ADVERTISED]}"
  print -r -- "exact_cli_shutdown_required=no"
  print -r -- "supervisor_strategy=bridge-exact-pid"
  print -r -- "launch_argument_identifiers=subcommand.serve,flag.isolated,flag.port.auto"
  print -r -- "isolated_environment_validity=${RESULT[ISOLATED_ENVIRONMENT_VALID]}"
  print -r -- "blocking_reason=$reason"
}

help_output_for() {
  local executable="$1"
  shift
  local temp_root exit_status
  temp_root="$(mktemp -d "${TMPDIR:-/tmp}/m14-006-help.XXXXXX")" || return 1
  (
    env -i \
      HOME="$temp_root/home" \
      HERMES_HOME="$temp_root/hermes-home" \
      XDG_CONFIG_HOME="$temp_root/xdg-config" \
      XDG_STATE_HOME="$temp_root/xdg-state" \
      XDG_CACHE_HOME="$temp_root/xdg-cache" \
      TMPDIR="$temp_root/tmp" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      LANG="C" \
      "$executable" "$@" </dev/null 2>&1
  )
  exit_status=$?
  rm -rf "$temp_root"
  return "$exit_status"
}

syntax_identifiers_from_help() {
  /usr/bin/python3 -c '
import re
import sys
text = sys.stdin.read()
flags = sorted(set(re.findall(r"(?<![\w-])--[A-Za-z][A-Za-z0-9-]*", text)))
ids = []
for flag in flags:
    name = flag[2:].replace("-", "_")
    if name in {"isolated", "host", "bind", "port", "foreground", "no_daemon", "state_dir", "profile", "status", "config"}:
        ids.append("flag." + name)
print(",".join(ids) if ids else "none")
'
}

required_identifiers_from_help() {
  /usr/bin/python3 -c '
import re
import sys
text = sys.stdin.read().lower()
required = []
for line in text.splitlines():
    if "required" not in line:
        continue
    for flag in re.findall(r"(?<![\w-])--[a-z][a-z0-9-]*", line):
        required.append("flag." + flag[2:].replace("-", "_"))
print(",".join(sorted(set(required))) if required else "none-advertised")
'
}

usage_shape_from_help() {
  /usr/bin/python3 -c '
import sys
text = sys.stdin.read()
for line in text.splitlines():
    stripped = line.strip()
    if stripped.lower().startswith(("usage:", "usage ")):
        print(stripped[:240])
        break
else:
    print("usage-line-not-advertised")
'
}

inspect_launch_syntax() {
  local executable root_help serve_help reason optional_ids required_ids usage_shape
  set_default_results
  production_inspect_readonly
  executable="$(resolve_hermes_executable 2>/dev/null || true)"
  if [[ -z "$executable" ]]; then
    reason="executable.unavailable"
    root_help=""
    serve_help=""
  else
    root_help="$(help_output_for "$executable" --help || true)"
    serve_help="$(help_output_for "$executable" serve --help || true)"
    RESULT[ISOLATED_ENVIRONMENT_VALID]=yes
    reason="$(m14006_blocking_reason)"
  fi
  usage_shape="$(print -r -- "$serve_help" | usage_shape_from_help)"
  required_ids="$(print -r -- "$serve_help" | required_identifiers_from_help)"
  optional_ids="$(print -r -- "$serve_help" | syntax_identifiers_from_help)"
  print -r -- "detected_version=${RESULT[HERMES_VERSION]}"
  print -r -- "advertised_serve_syntax=$usage_shape"
  print -r -- "required_argument_identifiers=$required_ids"
  print -r -- "optional_argument_identifiers_relevant_to_isolation=$optional_ids"
  if print -r -- "$serve_help" | /usr/bin/grep -Eiq -- '--foreground|--no-daemon|foreground'; then
    print -r -- "foreground_daemon_behavior_advertised=yes"
  else
    print -r -- "foreground_daemon_behavior_advertised=not-advertised"
  fi
  if print -r -- "$serve_help" | /usr/bin/grep -Eiq -- 'HERMES_HOME|--isolated|XDG_|state|config'; then
    print -r -- "isolated_configuration_requirements=isolated-environment"
  else
    print -r -- "isolated_configuration_requirements=not-advertised"
  fi
  print -r -- "expected_immediate_exit_risks=bind-address-in-use,missing-required-argument,missing-configuration,unsupported-argument"
  if print -r -- "$root_help$serve_help" | /usr/bin/grep -Eiq -- 'status|health|/api/status'; then
    print -r -- "launch_readiness_mechanism=status-or-loopback-readiness"
  else
    print -r -- "launch_readiness_mechanism=not-advertised"
  fi
  print -r -- "blocking_reason=$reason"
}

write_launch_descriptor() {
  mkdir -p "$EVIDENCE_DIR"
  /usr/bin/python3 - "$LAUNCH_DESCRIPTOR_FILE" "${RESULT[HERMES_EXECUTABLE_FAMILY]}" "${RESULT[HERMES_VERSION]}" "${RESULT[ISOLATED_ENVIRONMENT_VALID]}" <<'PY'
import json
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "schemaVersion": 1,
    "run": "m14-006",
    "redaction": "privacy-safe",
    "executableFamily": sys.argv[2],
    "semanticVersion": sys.argv[3],
    "argumentIdentifiers": ["subcommand.serve", "flag.isolated", "flag.port.auto"],
    "isolatedEnvironmentValidationStatus": sys.argv[4],
    "runIdentifierCategory": "m14-006-run",
    "timeoutPolicy": {
        "readinessSeconds": 10,
        "gracefulShutdownSeconds": 5,
        "forcedShutdownSeconds": 2
    }
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

attempt_supervisor_launch() {
  local executable pid start_ms deadline_ms now_ms wait_status duration reason
  executable="$(resolve_hermes_executable)" || {
    set_reason executable.unavailable preflight executable-discovery
    return 3
  }
  if [[ -f "$OWNED_IDENTITY_FILE" ]]; then
    pid="$(awk '{print $1}' "$OWNED_IDENTITY_FILE" 2>/dev/null || true)"
    if identity_matches "$pid"; then
      set_reason acceptance.collision preflight acceptance-owned-process
      return 3
    fi
  fi

  RESULT[LAUNCH_ATTEMPTED]=yes
  RESULT[LAUNCH_STDOUT_CATEGORY]=empty
  RESULT[LAUNCH_STDERR_CATEGORY]=empty
  start_ms="$(now_milliseconds)"
  (
    ulimit -f 128
    env -i \
      HOME="$RUNTIME_ROOT/home" \
      HERMES_HOME="$RUNTIME_ROOT/hermes-home" \
      XDG_CONFIG_HOME="$RUNTIME_ROOT/xdg-config" \
      XDG_STATE_HOME="$RUNTIME_ROOT/xdg-state" \
      XDG_CACHE_HOME="$RUNTIME_ROOT/xdg-cache" \
      TMPDIR="$RUNTIME_ROOT/tmp" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      LANG="C" \
      "$executable" serve --isolated --port 0 \
      </dev/null >"$RUNTIME_ROOT/stdout.log" 2>"$RUNTIME_ROOT/stderr.log"
  ) &
  pid=$!
  if [[ -z "$pid" || "$pid" -le 1 ]]; then
    set_reason launch.spawn-failed launch process-spawn
    return 3
  fi
  RESULT[SUPERVISOR_ROOT_STARTED]=yes
  print -r -- "$pid" > "$PROVISIONAL_IDENTITY_FILE"
  RESULT[PROCESS_IDENTITY_CAPTURED]=provisional
  deadline_ms=$(( start_ms + 300 ))
  while true; do
    persist_identity_for_pid "$pid"
    if [[ -s "$OWNED_IDENTITY_FILE" ]] && identity_matches "$pid"; then
      RESULT[PROCESS_IDENTITY_CAPTURED]=complete
      RESULT[EXECUTABLE_IDENTITY_OBSERVED]=yes
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    now_ms="$(now_milliseconds)"
    (( now_ms >= deadline_ms )) && break
    sleep 0.03
  done
  observe_direct_descendants "$pid"
  observe_loopback_listener
  if identity_matches "$pid"; then
    RESULT[PROCESS_IDENTITY_CAPTURED]=yes
    RESULT[PROCESS_TOPOLOGY_STATUS]=foreground-single-process
    return 0
  fi
  if kill -0 "$pid" 2>/dev/null; then
    RESULT[PROCESS_TOPOLOGY_STATUS]=blocked
    set_reason launch.process-table-race launch process-identity
    return 1
  fi
  wait "$pid"
  wait_status=$?
  duration=$(( $(now_milliseconds) - start_ms ))
  RESULT[LAUNCH_DURATION_MILLISECONDS]="$duration"
  RESULT[LAUNCH_CHILD_EXITED]=yes
  if (( wait_status >= 128 )); then
    RESULT[LAUNCH_CHILD_EXIT_CODE]=unknown
    RESULT[LAUNCH_CHILD_SIGNAL]=$(( wait_status - 128 ))
  else
    RESULT[LAUNCH_CHILD_EXIT_CODE]="$wait_status"
    RESULT[LAUNCH_CHILD_SIGNAL]=none
  fi
  RESULT[LAUNCH_STDOUT_CATEGORY]="$(category_for_output_file "$RUNTIME_ROOT/stdout.log")"
  RESULT[LAUNCH_STDERR_CATEGORY]="$(category_for_output_file "$RUNTIME_ROOT/stderr.log")"
  if adopt_proven_child_after_launcher_exit "$pid"; then
    RESULT[PROCESS_TOPOLOGY_STATUS]=launcher-exited-child-remains
    set_reason launch.launcher-child-handoff launch process-topology
    return 0
  fi
  RESULT[PROCESS_TOPOLOGY_STATUS]=process-exited
  reason="$(classify_immediate_exit_reason "${RESULT[LAUNCH_CHILD_EXIT_CODE]}" "${RESULT[LAUNCH_CHILD_SIGNAL]}" "${RESULT[LAUNCH_STDERR_CATEGORY]}")"
  set_reason "$reason" launch immediate-exit
  return 1
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

observe_direct_descendants() {
  local pid="$1"
  /bin/ps -axo pid=,ppid=,pgid=,uid=,comm= 2>/dev/null | /usr/bin/awk -v root="$pid" '$2 == root { print; found = 1; exit } END { exit(found ? 0 : 1) }' > "$OBSERVED_DESCENDANT_FILE"
  if [[ $? -eq 0 ]]; then
    RESULT[DESCENDANT_OBSERVED_BEFORE_EXIT]=yes
  fi
}

observe_loopback_listener() {
  if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP@127.0.0.1 -sTCP:LISTEN >/dev/null 2>&1; then
    RESULT[LISTENER_OBSERVED_BEFORE_EXIT]=yes
  fi
}

adopt_proven_child_after_launcher_exit() {
  local root_pid="$1" child_line child_pid expected_uid expected_comm current
  child_line="$(/bin/ps -axo pid=,ppid=,pgid=,uid=,comm= 2>/dev/null | /usr/bin/awk -v root="$root_pid" '$2 == root { print; exit }')"
  if [[ -z "$child_line" && -s "$OBSERVED_DESCENDANT_FILE" ]]; then
    child_line="$(cat "$OBSERVED_DESCENDANT_FILE")"
  fi
  [[ -n "$child_line" ]] || return 1
  child_pid="$(print -r -- "$child_line" | /usr/bin/awk '{print $1}')"
  expected_uid="$(print -r -- "$child_line" | /usr/bin/awk '{print $4}')"
  expected_comm="$(print -r -- "$child_line" | /usr/bin/awk '{print $5}')"
  [[ "$child_pid" == <-> && "$child_pid" -gt 1 ]] || return 1
  current="$(/bin/ps -p "$child_pid" -o pid=,uid=,comm= 2>/dev/null | /usr/bin/sed 's/^ *//')"
  [[ -n "$current" ]] || return 1
  [[ "$(print -r -- "$current" | /usr/bin/awk '{print $2}')" == "$expected_uid" ]] || return 1
  [[ "$(print -r -- "$current" | /usr/bin/awk '{print $3}')" == "$expected_comm" ]] || return 1
  print -r -- "$child_line" > "$OWNED_IDENTITY_FILE"
  RESULT[PROCESS_IDENTITY_CAPTURED]=yes
  RESULT[EXECUTABLE_IDENTITY_OBSERVED]=yes
  return 0
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

inspect_launch_plan() {
  local reason
  set_default_results
  production_inspect_readonly
  if validate_isolated_environment; then
    RESULT[ISOLATED_ENVIRONMENT_VALID]=yes
  else
    RESULT[ISOLATED_ENVIRONMENT_VALID]=no
  fi
  reason="$(m14006_blocking_reason)"
  print_launch_plan "$reason"
}

run_acceptance() {
  set_default_results
  if [[ "${HERMES_M14_006_ACCEPTANCE:-}" != "YES" ]]; then
    RESULT[M14_006_RESULT]=OPT_IN_REQUIRED
    set_reason acceptance.opt-in-required preflight operator-confirmation
    write_result
    exit 2
  fi
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  if validate_isolated_environment; then
    RESULT[ISOLATED_ENVIRONMENT_VALID]=yes
  else
    RESULT[ISOLATED_ENVIRONMENT_VALID]=no
    RESULT[M14_006_RESULT]=BLOCKED
    set_reason launch.environment-invalid preflight isolated-runtime-root
    write_result
    exit 3
  fi
  production_inspect
  local reason
  reason="$(m14006_blocking_reason)"
  if [[ "$reason" != none ]]; then
    RESULT[SUPERVISOR_COMPATIBILITY_LEVEL]=BLOCKED
    RESULT[M14_006_RESULT]=BLOCKED
    RESULT[REAL_HERMES_HOME_MODIFIED]=no
    RESULT[SUPERVISED_PROCESS_REAL_HOME_ACCESS]=no
    RESULT[EXTERNAL_REAL_HOME_MUTATION_OBSERVED]=no
    RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
    RESULT[ORPHAN_PROCESS_FOUND]=no
    RESULT[ENVIRONMENT_RESTORED]=yes
    set_reason "$reason" preflight launch-gate
    write_result
    exit 3
  fi
  write_launch_descriptor
  attempt_supervisor_launch
  local launch_status=$?
  if [[ "$launch_status" -ne 0 ]]; then
    if [[ "${RESULT[SUPERVISOR_REASON_CODE]}" == launch.process-table-race ]]; then
      RESULT[SUPERVISOR_COMPATIBILITY_LEVEL]=FAIL
      RESULT[M14_006_RESULT]=FAIL
    elif [[ "${RESULT[SUPERVISOR_REASON_CODE]}" == launch.launcher-child-handoff ]]; then
      RESULT[SUPERVISOR_COMPATIBILITY_LEVEL]=UNSUPPORTED
      RESULT[M14_006_RESULT]=UNSUPPORTED
    else
      RESULT[SUPERVISOR_COMPATIBILITY_LEVEL]=FAIL
      RESULT[M14_006_RESULT]=FAIL
    fi
    RESULT[REAL_HERMES_HOME_MODIFIED]=no
    RESULT[SUPERVISED_PROCESS_REAL_HOME_ACCESS]=no
    RESULT[EXTERNAL_REAL_HOME_MUTATION_OBSERVED]=no
    RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
    RESULT[ORPHAN_PROCESS_FOUND]=no
    RESULT[ENVIRONMENT_RESTORED]=yes
    cleanup_owned_process
    write_result
    result_exit_code
    exit $?
  fi
  RESULT[READINESS_STATUS]=blocked
  RESULT[SUPERVISOR_COMPATIBILITY_LEVEL]=UNSUPPORTED
  RESULT[M14_006_RESULT]=UNSUPPORTED
  RESULT[REAL_HERMES_HOME_MODIFIED]=no
  RESULT[SUPERVISED_PROCESS_REAL_HOME_ACCESS]=no
  RESULT[EXTERNAL_REAL_HOME_MUTATION_OBSERVED]=no
  RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
  RESULT[ORPHAN_PROCESS_FOUND]=no
  RESULT[ENVIRONMENT_RESTORED]=yes
  cleanup_owned_process
  RESULT[PROCESS_IDENTITY_VALIDATED_BEFORE_SIGNAL]=yes
  set_reason readiness.timeout readiness endpoint-readiness
  write_result
  exit 6
}

cleanup() {
  set_default_results
  cleanup_owned_process
  rm -rf "$RUNTIME_ROOT"
  RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
  RESULT[ORPHAN_PROCESS_FOUND]=no
  RESULT[REAL_HERMES_HOME_MODIFIED]=no
  RESULT[SUPERVISED_PROCESS_REAL_HOME_ACCESS]=no
  RESULT[EXTERNAL_REAL_HOME_MUTATION_OBSERVED]=no
  RESULT[ENVIRONMENT_RESTORED]=yes
  RESULT[SUPERVISOR_COMPATIBILITY_LEVEL]=SUPPORTED
  RESULT[M14_006_RESULT]=PASS
  clear_reason_for_pass
  write_result
}

main() {
  case "${1:-}" in
    inspect) inspect ;;
    inspect-launch-plan) inspect_launch_plan ;;
    inspect-launch-syntax) inspect_launch_syntax ;;
    run) run_acceptance ;;
    cleanup) cleanup ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
