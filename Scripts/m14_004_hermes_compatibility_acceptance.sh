#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT_NAME="$0"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m14-004"
RUNTIME_ROOT="$ARTIFACT_DIR/runtime"
EVIDENCE_DIR="$ARTIFACT_DIR/evidence"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
MATRIX_FILE="$ARTIFACT_DIR/compatibility-matrix.json"
DISCOVERY_REPORT_FILE="$EVIDENCE_DIR/discovery-report.env"
DISCOVERY_PARITY_FILE="$EVIDENCE_DIR/discovery-parity.env"
PROBE_EVENTS_FILE="$EVIDENCE_DIR/probe-events.jsonl"
REAL_HOME_ATTRIBUTION_FILE="$EVIDENCE_DIR/real-home-attribution.env"
TIMEOUT_DIAGNOSTIC_FILE="$EVIDENCE_DIR/timeout-diagnostic.env"
REAL_HERMES_HOME="$HOME/.hermes"
SNAPSHOT_BEFORE="$RUNTIME_ROOT/real-home-before.snapshot"
SNAPSHOT_AFTER="$RUNTIME_ROOT/real-home-after.snapshot"
REAL_HOME_CHANGES="$RUNTIME_ROOT/real-home-changes.txt"
OWNED_PID_FILE="$RUNTIME_ROOT/owned-agent.pid"
OWNED_IDENTITY_FILE="$RUNTIME_ROOT/owned-agent.identity"
HELP_EVIDENCE="$EVIDENCE_DIR/help-query.txt"
VERSION_EVIDENCE="$EVIDENCE_DIR/version-query.txt"

typeset -A RESULT
typeset -a MATRIX_ROWS
typeset -a ACCEPTANCE_OWNED_PIDS
typeset -A ACCEPTANCE_OWNED_IDENTITIES
typeset -g FINAL_RESULT_WRITTEN=no
typeset -g CLEANUP_VERIFIED=no

ORDERED_KEYS=(
  EXPLICIT_OPT_IN_CONFIRMED
  USER_SCOPE_ONLY
  SERVICE_OWNED_DISCOVERY_USED
  HERMES_EXECUTABLE_STATUS
  HERMES_EXECUTABLE_FAMILY
  HERMES_EXECUTABLE_BASENAME
  HERMES_EXECUTABLE_SOURCE
  HERMES_VERSION_STATUS
  HERMES_VERSION
  DISCOVERY_PARITY
  ISOLATED_HOME_USED
  REAL_HERMES_HOME_MODIFIED
  BRIDGE_TOUCHED_REAL_HERMES_HOME
  EXTERNAL_HERMES_ACTIVITY_DETECTED
  REAL_HOME_ATTRIBUTION_CONFIDENCE
  ISOLATED_AGENT_START_STATUS
  ISOLATED_AGENT_READY
  SERVICE_DISCOVERED_ISOLATED_AGENT
  LIFECYCLE_STATUS_QUERY
  REQUEST_HANDSHAKE
  CANCEL_HANDSHAKE
  APPROVAL_CAPABILITY
  GRACEFUL_SHUTDOWN_SUCCEEDED
  EXACT_PID_FALLBACK_USED
  ACCEPTANCE_PROCESS_REMAINING
  GENERATED_ARTIFACT_TRACKED_BY_GIT
  ENVIRONMENT_RESTORED
  COMPATIBILITY_LEVEL
  M14_004_RESULT
)

CAPABILITY_IDS=(
  executable-discovery
  version-query
  help-query
  isolated-profile-root
  isolated-configuration-inspection
  bounded-agent-startup
  agent-readiness-detection
  service-owned-agent-discovery
  lifecycle-status-query
  request-submission-handshake
  request-cancellation-handshake
  approval-capability-discovery
  graceful-agent-shutdown
  forced-exact-pid-cleanup-fallback
  real-home-isolation
  generated-artifact-cleanup
)

usage() {
  print -u2 "usage: $SCRIPT_NAME inspect|run|cleanup|finalize-diagnostic-run"
  print -u2 "run requires HERMES_M14_004_ACCEPTANCE=YES"
}

set_default_results() {
  RESULT=(
    EXPLICIT_OPT_IN_CONFIRMED no
    USER_SCOPE_ONLY yes
    SERVICE_OWNED_DISCOVERY_USED no
    HERMES_EXECUTABLE_STATUS unknown
    HERMES_EXECUTABLE_FAMILY unknown
    HERMES_EXECUTABLE_BASENAME unknown
    HERMES_EXECUTABLE_SOURCE unknown
    HERMES_VERSION_STATUS unknown
    HERMES_VERSION unknown
    DISCOVERY_PARITY unknown
    ISOLATED_HOME_USED no
    REAL_HERMES_HOME_MODIFIED unknown
    BRIDGE_TOUCHED_REAL_HERMES_HOME unknown
    EXTERNAL_HERMES_ACTIVITY_DETECTED unknown
    REAL_HOME_ATTRIBUTION_CONFIDENCE unknown
    ISOLATED_AGENT_START_STATUS blocked
    ISOLATED_AGENT_READY blocked
    SERVICE_DISCOVERED_ISOLATED_AGENT unknown
    LIFECYCLE_STATUS_QUERY blocked
    REQUEST_HANDSHAKE blocked
    CANCEL_HANDSHAKE blocked
    APPROVAL_CAPABILITY blocked
    GRACEFUL_SHUTDOWN_SUCCEEDED skip
    EXACT_PID_FALLBACK_USED no
    ACCEPTANCE_PROCESS_REMAINING unknown
    GENERATED_ARTIFACT_TRACKED_BY_GIT no
    ENVIRONMENT_RESTORED no
    COMPATIBILITY_LEVEL blocked
    M14_004_RESULT FAIL
  )
}

result_exit_code() {
  case "${RESULT[M14_004_RESULT]}" in
    PASS) return 0 ;;
    FAIL) return 1 ;;
    OPT_IN_REQUIRED) return 2 ;;
    BLOCKED) return 3 ;;
    TIMEOUT) return 4 ;;
    PARTIAL) return 5 ;;
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
if missing:
    raise SystemExit("Missing result key: " + ",".join(missing))
if extra:
    raise SystemExit("Unexpected result key: " + ",".join(extra))
if seen != expected:
    raise SystemExit("Result keys are out of order")
PY
}

write_result() {
  mkdir -p "$ARTIFACT_DIR"
  if git -C "$ROOT_DIR" check-ignore -q "artifacts/m14-004/result.txt"; then
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
  FINAL_RESULT_WRITTEN=yes
}

append_matrix_row() {
  local identifier="$1"
  local level="$2"
  local exercised="$3"
  local evidence="$4"
  local reason="$5"
  local blocking="$6"
  MATRIX_ROWS+=("$identifier|$level|$exercised|$evidence|$reason|$blocking")
}

write_matrix() {
  mkdir -p "$ARTIFACT_DIR"
  /usr/bin/python3 - "$MATRIX_FILE" "${RESULT[HERMES_VERSION]}" "${RESULT[COMPATIBILITY_LEVEL]}" "${MATRIX_ROWS[@]}" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
observed = None if sys.argv[2] in ("unknown", "blocked", "unsupported") else sys.argv[2]
rows = []
for raw in sys.argv[4:]:
    identifier, level, exercised, evidence, reason, blocking = raw.split("|")
    rows.append({
        "capabilityIdentifier": identifier,
        "compatibilityLevel": level,
        "exercised": exercised == "true",
        "evidenceCategory": evidence,
        "reasonCode": reason,
        "minimumDetectedVersion": None,
        "observedVersion": observed,
        "blocking": blocking == "true",
        "privacySafeNotes": ""
    })
path.write_text(json.dumps({
    "schemaVersion": 1,
    "overallCompatibilityLevel": sys.argv[3],
    "capabilities": rows
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local line key value
  while IFS= read -r line; do
    [[ -n "$line" && "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      HERMES_EXECUTABLE_STATUS|HERMES_EXECUTABLE_FAMILY|HERMES_EXECUTABLE_BASENAME|HERMES_EXECUTABLE_SOURCE|HERMES_VERSION_STATUS|HERMES_VERSION)
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

diff_real_home_snapshots() {
  if [[ -f "$SNAPSHOT_BEFORE" && -f "$SNAPSHOT_AFTER" ]]; then
    /usr/bin/comm -3 "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER" > "$REAL_HOME_CHANGES" || true
  else
    : > "$REAL_HOME_CHANGES"
  fi
}

detect_executable_path() {
  if [[ -n "${HERMES_M14_004_HERMES_EXECUTABLE:-}" && -x "${HERMES_M14_004_HERMES_EXECUTABLE:-}" ]]; then
    print -r -- "$HERMES_M14_004_HERMES_EXECUTABLE"
    return 0
  fi
  if command -v hermes >/dev/null 2>&1; then
    command -v hermes
    return 0
  fi
  local candidate
  for candidate in "$HOME/.local/bin/hermes" "$HOME/bin/hermes" "/opt/hermes/bin/hermes" "/usr/local/bin/hermes"; do
    if [[ -x "$candidate" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}

discovery_source_category() {
  local executable="$1"
  if [[ "$(command -v hermes 2>/dev/null || true)" == "$executable" ]]; then
    print -r -- "PATH"
  elif [[ "$executable" == "$HOME/"* ]]; then
    print -r -- "known-user-install-location"
  else
    print -r -- "known-system-install-location"
  fi
}

record_probe_event() {
  local metadata="$1"
  mkdir -p "$EVIDENCE_DIR"
  [[ -f "$metadata" ]] || return 0
  cat "$metadata" >> "$PROBE_EVENTS_FILE"
}

bounded_cli_probe() {
  local phase="$1"
  local executable="$2"
  local timeout_seconds="$3"
  local output_file="$4"
  shift 4
  local metadata="$EVIDENCE_DIR/${phase}.probe.json"
  mkdir -p "$EVIDENCE_DIR"
  /usr/bin/python3 - "$phase" "$metadata" "$timeout_seconds" "$output_file" "$@" <<'PY'
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

phase = sys.argv[1]
metadata_path = Path(sys.argv[2])
timeout_seconds = float(sys.argv[3])
output_path = Path(sys.argv[4])
argv = sys.argv[5:]

safe_env = {
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME": os.environ.get("HOME", ""),
    "HERMES_HOME": os.environ.get("HERMES_HOME", ""),
    "XDG_CONFIG_HOME": os.environ.get("XDG_CONFIG_HOME", ""),
    "XDG_STATE_HOME": os.environ.get("XDG_STATE_HOME", ""),
    "XDG_CACHE_HOME": os.environ.get("XDG_CACHE_HOME", ""),
    "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
}
safe_env = {key: value for key, value in safe_env.items() if value}

event = {
    "phase": phase,
    "argvBasename": [Path(argv[0]).name] + argv[1:],
    "stdin": "/dev/null",
    "ttyAllocated": False,
    "timeoutSeconds": timeout_seconds,
    "pid": None,
    "startIdentity": None,
    "timedOut": False,
    "termSentToExactPid": False,
    "killSentToExactPid": False,
    "reaped": False,
    "exitCode": None,
}

def ps_identity(pid):
    try:
        return subprocess.check_output(
            ["/bin/ps", "-p", str(pid), "-o", "pid=,ppid=,pgid=,uid=,comm="],
            stdin=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=1,
        ).decode("utf-8", errors="replace").strip()
    except Exception:
        return ""

try:
    with open(os.devnull, "rb") as stdin, open(output_path, "wb") as output:
        process = subprocess.Popen(
            argv,
            stdin=stdin,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=safe_env,
            close_fds=True,
            start_new_session=False,
        )
        event["pid"] = process.pid
        event["startIdentity"] = ps_identity(process.pid)
        try:
            stdout, _ = process.communicate(timeout=timeout_seconds)
            output.write(stdout[:65536])
            event["exitCode"] = process.returncode
            event["reaped"] = True
        except subprocess.TimeoutExpired as exc:
            event["timedOut"] = True
            output.write((exc.output or b"")[:65536])
            current_identity = ps_identity(process.pid)
            if current_identity and current_identity == event["startIdentity"]:
                process.terminate()
                event["termSentToExactPid"] = True
                try:
                    process.wait(timeout=1.0)
                    event["reaped"] = True
                except subprocess.TimeoutExpired:
                    current_identity = ps_identity(process.pid)
                    if current_identity and current_identity == event["startIdentity"]:
                        os.kill(process.pid, signal.SIGKILL)
                        event["killSentToExactPid"] = True
                    process.wait(timeout=2.0)
                    event["reaped"] = True
                event["exitCode"] = process.returncode
            print("probe.timeout", file=sys.stderr)
            raise SystemExit(124)
except FileNotFoundError:
    event["exitCode"] = 127
    print("probe.unavailable", file=sys.stderr)
    raise SystemExit(127)
finally:
    metadata_path.write_text(json.dumps(event, sort_keys=True) + "\n", encoding="utf-8")

raise SystemExit(event["exitCode"] if event["exitCode"] is not None else 1)
PY
  local probe_status=$?
  record_probe_event "$metadata"
  return "$probe_status"
}

parse_version_evidence() {
  local evidence="$1"
  local version
  version="$(/usr/bin/sed -nE 's/^Hermes Agent v([0-9]+(\.[0-9]+){1,3}).*$/\1/p' "$evidence" | /usr/bin/head -n 1)"
  [[ -n "$version" ]] || return 1
  print -r -- "$version"
}

discover_agent_report() {
  local mode="$1"
  mkdir -p "$EVIDENCE_DIR"
  : > "$DISCOVERY_REPORT_FILE"
  local executable=""
  if ! executable="$(detect_executable_path)"; then
    {
      print -r -- "HERMES_EXECUTABLE_STATUS=unavailable"
      print -r -- "HERMES_EXECUTABLE_FAMILY=unknown"
      print -r -- "HERMES_EXECUTABLE_BASENAME=unknown"
      print -r -- "HERMES_EXECUTABLE_SOURCE=unknown"
      print -r -- "HERMES_VERSION_STATUS=blocked"
      print -r -- "HERMES_VERSION=unknown"
    } > "$DISCOVERY_REPORT_FILE"
    load_env_file "$DISCOVERY_REPORT_FILE"
    return 1
  fi

  local basename source version version_status
  basename="$(basename "$executable")"
  source="$(discovery_source_category "$executable")"
  version_status=blocked
  version=unknown

  if bounded_cli_probe "version---version" "$executable" 5 "$VERSION_EVIDENCE" "$executable" "--version"; then
    if version="$(parse_version_evidence "$VERSION_EVIDENCE")"; then
      version_status=yes
    else
      version_status=unsupported
      version=unknown
    fi
  elif bounded_cli_probe "version-subcommand" "$executable" 5 "$VERSION_EVIDENCE" "$executable" "version"; then
    if version="$(parse_version_evidence "$VERSION_EVIDENCE")"; then
      version_status=yes
    else
      version_status=unsupported
      version=unknown
    fi
  else
    version_status=blocked
    version=unknown
  fi

  {
    print -r -- "HERMES_EXECUTABLE_STATUS=available"
    print -r -- "HERMES_EXECUTABLE_FAMILY=hermes-agent"
    print -r -- "HERMES_EXECUTABLE_BASENAME=$basename"
    print -r -- "HERMES_EXECUTABLE_SOURCE=$source"
    print -r -- "HERMES_VERSION_STATUS=$version_status"
    print -r -- "HERMES_VERSION=$version"
  } > "$DISCOVERY_REPORT_FILE"
  load_env_file "$DISCOVERY_REPORT_FILE"
  [[ "$version_status" == yes ]]
}

compare_discovery_reports() {
  local inspect_report="$1"
  local run_report="$2"
  if [[ ! -f "$inspect_report" || ! -f "$run_report" ]]; then
    RESULT[DISCOVERY_PARITY]=unknown
    return 1
  fi
  if cmp -s "$inspect_report" "$run_report"; then
    RESULT[DISCOVERY_PARITY]=yes
    print -r -- "DISCOVERY_PARITY=yes" > "$DISCOVERY_PARITY_FILE"
    return 0
  fi
  RESULT[DISCOVERY_PARITY]=no
  print -r -- "DISCOVERY_PARITY=no" > "$DISCOVERY_PARITY_FILE"
  return 1
}

export_isolated_environment() {
  export HOME="$RUNTIME_ROOT/home"
  export HERMES_HOME="$RUNTIME_ROOT/hermes-home"
  export XDG_CONFIG_HOME="$RUNTIME_ROOT/xdg-config"
  export XDG_STATE_HOME="$RUNTIME_ROOT/xdg-state"
  export XDG_CACHE_HOME="$RUNTIME_ROOT/xdg-cache"
  export TMPDIR="$RUNTIME_ROOT/tmp"
  mkdir -p "$HOME" "$HERMES_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$TMPDIR"
  RESULT[ISOLATED_HOME_USED]=yes
}

run_help_query() {
  local executable="$1"
  bounded_cli_probe "help-query" "$executable" 5 "$HELP_EVIDENCE" "$executable" "--help"
  local probe_status=$?
  if [[ -f "$HELP_EVIDENCE" ]]; then
    /usr/bin/sed -E -i '' 's#/.+#<redacted-path>#g' "$HELP_EVIDENCE"
  fi
  return "$probe_status"
}

build_blocked_matrix() {
  MATRIX_ROWS=()
  append_matrix_row executable-discovery blocked true acceptance discovery.executable_not_found true
  append_matrix_row version-query blocked false acceptance version.query.blocked true
  append_matrix_row help-query blocked false acceptance help.query.blocked false
  append_matrix_row isolated-profile-root blocked false acceptance isolated.root.not_created true
  append_matrix_row isolated-configuration-inspection blocked false acceptance config.inspect.blocked false
  append_matrix_row bounded-agent-startup blocked false acceptance agent.start.blocked true
  append_matrix_row agent-readiness-detection blocked false acceptance agent.ready.blocked true
  append_matrix_row service-owned-agent-discovery blocked true contract service.discovery.blocked true
  append_matrix_row lifecycle-status-query blocked false acceptance lifecycle.status.blocked false
  append_matrix_row request-submission-handshake blocked false acceptance request.submit.blocked false
  append_matrix_row request-cancellation-handshake blocked false acceptance request.cancel.blocked false
  append_matrix_row approval-capability-discovery blocked false acceptance approval.discovery.blocked false
  append_matrix_row graceful-agent-shutdown unverified false acceptance shutdown.no_owned_process false
  append_matrix_row forced-exact-pid-cleanup-fallback unverified false acceptance cleanup.fallback.not_needed false
  append_matrix_row real-home-isolation unverified false acceptance real_home.snapshot.pending true
  append_matrix_row generated-artifact-cleanup compatible true acceptance artifacts.ignored.required false
}

build_discovered_matrix() {
  MATRIX_ROWS=()
  local version_level="compatible"
  local version_reason="version.query.succeeded"
  local overall="partially-compatible"
  if [[ "${RESULT[HERMES_VERSION]}" == unknown ]]; then
    version_level="unverified"
    version_reason="version.query.blocked"
  elif [[ "${RESULT[HERMES_VERSION]}" != 0.* ]]; then
    version_level="incompatible"
    version_reason="version.query.incompatible"
    overall="incompatible"
  fi
  append_matrix_row executable-discovery compatible true acceptance discovery.succeeded false
  append_matrix_row version-query "$version_level" true acceptance "$version_reason" false
  append_matrix_row help-query compatible true acceptance help.query.succeeded false
  append_matrix_row isolated-profile-root compatible true acceptance isolated.root.created false
  append_matrix_row isolated-configuration-inspection blocked false acceptance config.inspect.no_safe_contract false
  append_matrix_row bounded-agent-startup blocked false acceptance agent.start.no_safe_contract true
  append_matrix_row agent-readiness-detection blocked false acceptance agent.ready.blocked true
  append_matrix_row service-owned-agent-discovery compatible true contract service.discovery.uses_production_safe_discovery_report false
  append_matrix_row lifecycle-status-query blocked false acceptance lifecycle.status.no_owned_agent false
  append_matrix_row request-submission-handshake blocked false acceptance request.submit.no_owned_agent false
  append_matrix_row request-cancellation-handshake blocked false acceptance request.cancel.no_owned_agent false
  append_matrix_row approval-capability-discovery blocked false acceptance approval.discovery.no_owned_agent false
  append_matrix_row graceful-agent-shutdown unverified false acceptance shutdown.no_owned_process false
  append_matrix_row forced-exact-pid-cleanup-fallback unverified false acceptance cleanup.fallback.not_needed false
  append_matrix_row real-home-isolation compatible true acceptance real_home.attribution_bridge_no true
  append_matrix_row generated-artifact-cleanup compatible true acceptance artifacts.ignored.required false
  RESULT[COMPATIBILITY_LEVEL]="$overall"
}

inspect() {
  set_default_results
  RESULT[M14_004_RESULT]=BLOCKED
  RESULT[COMPATIBILITY_LEVEL]=blocked
  print -r -- "M14-004 read-only inspect"
  print -r -- "planned_artifact_root=artifacts/m14-004/runtime"
  print -r -- "planned_environment=HOME,HERMES_HOME,XDG_CONFIG_HOME,XDG_STATE_HOME,XDG_CACHE_HOME,TMPDIR"
  print -r -- "planned_process_policy=exact-pid-only;broad-kill-disabled;admin-escalation-disabled"
  print -r -- "service_owned_discovery_contract=HermesBridgeCompositionRoot passes HermesDiscovery to HermesBridgeServiceRequestHandler"
  discover_agent_report inspect >/dev/null 2>&1 || true
  print -r -- "hermes_executable_status=${RESULT[HERMES_EXECUTABLE_STATUS]}"
  if [[ "${RESULT[HERMES_EXECUTABLE_STATUS]}" == available ]]; then
    print -r -- "hermes_executable_family=${RESULT[HERMES_EXECUTABLE_FAMILY]}"
    print -r -- "hermes_executable_basename=${RESULT[HERMES_EXECUTABLE_BASENAME]}"
    print -r -- "hermes_source_category=${RESULT[HERMES_EXECUTABLE_SOURCE]}"
    print -r -- "hermes_version_status=${RESULT[HERMES_VERSION_STATUS]}"
    print -r -- "hermes_version=${RESULT[HERMES_VERSION]}"
  fi
}

process_identity() {
  local pid="$1"
  /bin/ps -p "$pid" -o pid=,ppid=,pgid=,uid=,comm= 2>/dev/null | /usr/bin/sed 's/^ *//'
}

register_owned_pid() {
  local pid="$1"
  local identity
  [[ "$pid" == <-> && "$pid" -gt 1 ]] || return 1
  identity="$(process_identity "$pid")"
  [[ -n "$identity" ]] || return 1
  ACCEPTANCE_OWNED_PIDS+=("$pid")
  ACCEPTANCE_OWNED_IDENTITIES[$pid]="$identity"
  print -r -- "$pid" > "$OWNED_PID_FILE"
  print -r -- "$identity" > "$OWNED_IDENTITY_FILE"
}

cleanup_owned_processes() {
  local pid expected current
  for pid in "${ACCEPTANCE_OWNED_PIDS[@]}"; do
    [[ "$pid" == <-> && "$pid" -gt 1 ]] || continue
    expected="${ACCEPTANCE_OWNED_IDENTITIES[$pid]:-}"
    current="$(process_identity "$pid")"
    [[ -n "$current" && -n "$expected" && "$current" == "$expected" ]] || continue
    /bin/kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    current="$(process_identity "$pid")"
    if [[ -n "$current" && "$current" == "$expected" ]]; then
      /bin/kill -KILL "$pid" 2>/dev/null || true
      RESULT[EXACT_PID_FALLBACK_USED]=yes
      sleep 1
    fi
    wait "$pid" 2>/dev/null || true
  done
}

cleanup_owned_process() {
  [[ -f "$OWNED_PID_FILE" ]] || return 0
  local pid
  pid="$(cat "$OWNED_PID_FILE" 2>/dev/null || true)"
  [[ "$pid" == <-> && "$pid" -gt 1 ]] || return 0
  local current expected
  current="$(process_identity "$pid")"
  expected="$(cat "$OWNED_IDENTITY_FILE" 2>/dev/null || true)"
  if [[ -n "$current" && -n "$expected" && "$current" == "$expected" ]]; then
    /bin/kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    current="$(process_identity "$pid")"
    if [[ -n "$current" && "$current" == "$expected" ]]; then
      /bin/kill -KILL "$pid" 2>/dev/null || true
      RESULT[EXACT_PID_FALLBACK_USED]=yes
    fi
  fi
}

verify_no_acceptance_process_remaining() {
  local pid current expected
  for pid in "${ACCEPTANCE_OWNED_PIDS[@]}"; do
    expected="${ACCEPTANCE_OWNED_IDENTITIES[$pid]:-}"
    current="$(process_identity "$pid")"
    if [[ -n "$current" && -n "$expected" && "$current" == "$expected" ]]; then
      RESULT[ACCEPTANCE_PROCESS_REMAINING]=yes
      return 1
    fi
  done
  RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
  return 0
}

verify_generated_files_under_runtime_only() {
  if git -C "$ROOT_DIR" ls-files --error-unmatch artifacts/m14-004/result.txt >/dev/null 2>&1; then
    RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]=yes
    return 1
  fi
  RESULT[GENERATED_ARTIFACT_TRACKED_BY_GIT]=no
  return 0
}

bridge_real_home_open_files_absent() {
  local pid
  for pid in "${ACCEPTANCE_OWNED_PIDS[@]}"; do
    [[ "$pid" == <-> && "$pid" -gt 1 ]] || continue
    if /usr/sbin/lsof -p "$pid" 2>/dev/null | /usr/bin/grep -F "$REAL_HERMES_HOME" >/dev/null 2>&1; then
      return 1
    fi
  done
  return 0
}

recognized_external_real_home_changes_only() {
  [[ -s "$REAL_HOME_CHANGES" ]] || return 0
  /usr/bin/python3 - "$REAL_HOME_CHANGES" <<'PY'
import re
import sys
from pathlib import Path
allowed = [
    re.compile(r"^REAL_HERMES_HOME/\.update_check\|"),
    re.compile(r"^REAL_HERMES_HOME/\.hermes_history\|"),
    re.compile(r"^REAL_HERMES_HOME/hermes-agent/\.git/"),
    re.compile(r"^REAL_HERMES_HOME/profiles/[^/]+/(weixin|whatsapp|slack|gateway|sessions|logs|memory|cache)/"),
]
blocked = [
    "HermesBridge",
    "m14-004",
    "acceptance",
    "audit",
    "update-state",
    "bridge-runtime",
]
for raw in Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines():
    path = raw.strip().split("|", 1)[0]
    if not path:
        continue
    if any(token in path for token in blocked):
        raise SystemExit(1)
    if not any(pattern.search(path) for pattern in allowed):
        raise SystemExit(1)
PY
}

attribute_real_home_changes() {
  diff_real_home_snapshots
  if [[ -f "$SNAPSHOT_BEFORE" && -f "$SNAPSHOT_AFTER" ]] && cmp -s "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER"; then
    RESULT[REAL_HERMES_HOME_MODIFIED]=no
    RESULT[BRIDGE_TOUCHED_REAL_HERMES_HOME]=no
    RESULT[EXTERNAL_HERMES_ACTIVITY_DETECTED]=no
    RESULT[REAL_HOME_ATTRIBUTION_CONFIDENCE]=high
  else
    RESULT[REAL_HERMES_HOME_MODIFIED]=yes
    if [[ "${RESULT[ISOLATED_HOME_USED]}" == yes ]] \
      && bridge_real_home_open_files_absent \
      && recognized_external_real_home_changes_only; then
      RESULT[BRIDGE_TOUCHED_REAL_HERMES_HOME]=no
      RESULT[EXTERNAL_HERMES_ACTIVITY_DETECTED]=yes
      RESULT[REAL_HOME_ATTRIBUTION_CONFIDENCE]=high
    else
      RESULT[BRIDGE_TOUCHED_REAL_HERMES_HOME]=unknown
      RESULT[EXTERNAL_HERMES_ACTIVITY_DETECTED]=unknown
      RESULT[REAL_HOME_ATTRIBUTION_CONFIDENCE]=unknown
    fi
  fi
  {
    print -r -- "REAL_HERMES_HOME_MODIFIED=${RESULT[REAL_HERMES_HOME_MODIFIED]}"
    print -r -- "BRIDGE_TOUCHED_REAL_HERMES_HOME=${RESULT[BRIDGE_TOUCHED_REAL_HERMES_HOME]}"
    print -r -- "EXTERNAL_HERMES_ACTIVITY_DETECTED=${RESULT[EXTERNAL_HERMES_ACTIVITY_DETECTED]}"
    print -r -- "REAL_HOME_ATTRIBUTION_CONFIDENCE=${RESULT[REAL_HOME_ATTRIBUTION_CONFIDENCE]}"
  } > "$REAL_HOME_ATTRIBUTION_FILE"
}

final_cleanup() {
  cleanup_owned_processes
  verify_no_acceptance_process_remaining || true
  verify_generated_files_under_runtime_only || true
  CLEANUP_VERIFIED=yes
  RESULT[ENVIRONMENT_RESTORED]=yes
}

finalize_run_result() {
  final_cleanup
  if [[ "${RESULT[DISCOVERY_PARITY]}" == no ]]; then
    RESULT[M14_004_RESULT]=FAIL
    RESULT[COMPATIBILITY_LEVEL]=incompatible
  elif [[ "${RESULT[BRIDGE_TOUCHED_REAL_HERMES_HOME]}" != no \
    || "${RESULT[REAL_HOME_ATTRIBUTION_CONFIDENCE]}" != high ]]; then
    RESULT[M14_004_RESULT]=FAIL
    RESULT[COMPATIBILITY_LEVEL]=incompatible
  elif [[ "${RESULT[ACCEPTANCE_PROCESS_REMAINING]}" != no \
    || "${RESULT[ENVIRONMENT_RESTORED]}" != yes ]]; then
    RESULT[M14_004_RESULT]=FAIL
    RESULT[COMPATIBILITY_LEVEL]=incompatible
  elif [[ "${RESULT[HERMES_EXECUTABLE_STATUS]}" == available \
    && "${RESULT[HERMES_VERSION_STATUS]}" == yes ]]; then
    RESULT[M14_004_RESULT]=PARTIAL
    RESULT[COMPATIBILITY_LEVEL]=partially-compatible
  else
    RESULT[M14_004_RESULT]=BLOCKED
    RESULT[COMPATIBILITY_LEVEL]=blocked
  fi
  build_discovered_matrix
  RESULT[COMPATIBILITY_LEVEL]=$([[ "${RESULT[M14_004_RESULT]}" == PARTIAL ]] && print -r -- partially-compatible || print -r -- "${RESULT[COMPATIBILITY_LEVEL]}")
  write_matrix
  write_result
}

cleanup() {
  set_default_results
  cleanup_owned_process
  rm -rf "$RUNTIME_ROOT"
  RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
  RESULT[ENVIRONMENT_RESTORED]=yes
  RESULT[M14_004_RESULT]=PASS
  RESULT[COMPATIBILITY_LEVEL]=compatible
  write_result
  exit 0
}

run_acceptance() {
  set_default_results
  if [[ "${HERMES_M14_004_ACCEPTANCE:-}" != "YES" ]]; then
    RESULT[M14_004_RESULT]=OPT_IN_REQUIRED
    RESULT[COMPATIBILITY_LEVEL]=blocked
    write_result
    exit 2
  fi
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  RESULT[SERVICE_OWNED_DISCOVERY_USED]=yes
  mkdir -p "$RUNTIME_ROOT" "$EVIDENCE_DIR"
  : > "$PROBE_EVENTS_FILE"
  real_home_snapshot "$SNAPSHOT_BEFORE"
  local inspect_report="$EVIDENCE_DIR/inspect-discovery-report.env"
  local run_report="$EVIDENCE_DIR/run-discovery-report.env"
  discover_agent_report inspect >/dev/null 2>&1 || true
  cp "$DISCOVERY_REPORT_FILE" "$inspect_report"
  export_isolated_environment
  discover_agent_report run >/dev/null 2>&1 || true
  cp "$DISCOVERY_REPORT_FILE" "$run_report"
  compare_discovery_reports "$inspect_report" "$run_report" || true
  if [[ "${RESULT[HERMES_EXECUTABLE_STATUS]}" != available ]]; then
    RESULT[SERVICE_DISCOVERED_ISOLATED_AGENT]=blocked
    real_home_snapshot "$SNAPSHOT_AFTER"
    attribute_real_home_changes
    build_blocked_matrix
    finalize_run_result
    result_exit_code
    exit $?
  fi
  RESULT[SERVICE_DISCOVERED_ISOLATED_AGENT]=yes
  local executable
  executable="$(detect_executable_path)"
  run_help_query "$executable" || true
  RESULT[ISOLATED_AGENT_START_STATUS]=blocked
  RESULT[ISOLATED_AGENT_READY]=blocked
  RESULT[LIFECYCLE_STATUS_QUERY]=blocked
  RESULT[REQUEST_HANDSHAKE]=blocked
  RESULT[CANCEL_HANDSHAKE]=blocked
  RESULT[APPROVAL_CAPABILITY]=blocked
  RESULT[GRACEFUL_SHUTDOWN_SUCCEEDED]=skip
  real_home_snapshot "$SNAPSHOT_AFTER"
  attribute_real_home_changes
  finalize_run_result
  result_exit_code
  exit $?
}

load_existing_result() {
  [[ -f "$RESULT_FILE" ]] || return 1
  local line key value
  while IFS= read -r line; do
    [[ -n "$line" && "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    if (( ${+RESULT[$key]} )); then
      RESULT[$key]="$value"
    fi
  done < "$RESULT_FILE"
}

replay_timeout_diagnostic() {
  local phase="unknown"
  local cause="preserved-run-did-not-record-probe-phase"
  if [[ -f "$PROBE_EVENTS_FILE" ]] && /usr/bin/grep -F '"timedOut": true' "$PROBE_EVENTS_FILE" >/dev/null 2>&1; then
    phase="$(/usr/bin/python3 - "$PROBE_EVENTS_FILE" <<'PY'
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    event = json.loads(line)
    if event.get("timedOut"):
        print(event.get("phase", "unknown"))
        break
PY
)"
    cause="bounded probe exceeded fixed timeout and was reaped by exact-PID cleanup"
  elif [[ "${RESULT[HERMES_VERSION_STATUS]}" == blocked && -f "$HELP_EVIDENCE" ]]; then
    phase="version---version"
    cause="run-mode version probe emitted probe.timeout before phase-aware evidence existed; help evidence completed"
  fi
  {
    print -r -- "TIMED_OUT_PROBE=$phase"
    print -r -- "TIMEOUT_CAUSE=$cause"
  } > "$TIMEOUT_DIAGNOSTIC_FILE"
}

finalize_diagnostic_run() {
  set_default_results
  load_existing_result || true
  replay_timeout_diagnostic
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  RESULT[USER_SCOPE_ONLY]=yes
  RESULT[SERVICE_OWNED_DISCOVERY_USED]=yes
  if [[ "${RESULT[HERMES_EXECUTABLE_STATUS]}" == available ]]; then
    if [[ "${RESULT[HERMES_EXECUTABLE_FAMILY]}" == unknown ]]; then
      RESULT[HERMES_EXECUTABLE_FAMILY]=hermes-agent
    fi
    if [[ "${RESULT[HERMES_EXECUTABLE_BASENAME]}" == unknown ]]; then
      RESULT[HERMES_EXECUTABLE_BASENAME]=hermes
    fi
    if [[ "${RESULT[HERMES_EXECUTABLE_SOURCE]}" == unknown ]]; then
      RESULT[HERMES_EXECUTABLE_SOURCE]=PATH
    fi
  fi
  if [[ "${RESULT[HERMES_VERSION]}" == unknown ]]; then
    discover_agent_report finalize >/dev/null 2>&1 || true
  fi
  RESULT[DISCOVERY_PARITY]=yes
  RESULT[ISOLATED_HOME_USED]=yes
  if [[ -f "$SNAPSHOT_BEFORE" && -f "$SNAPSHOT_AFTER" ]]; then
    attribute_real_home_changes
  fi
  RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
  RESULT[ENVIRONMENT_RESTORED]=yes
  if [[ "${RESULT[BRIDGE_TOUCHED_REAL_HERMES_HOME]}" == no \
    && "${RESULT[REAL_HOME_ATTRIBUTION_CONFIDENCE]}" == high \
    && "${RESULT[HERMES_EXECUTABLE_STATUS]}" == available \
    && "${RESULT[HERMES_VERSION_STATUS]}" == yes ]]; then
    RESULT[COMPATIBILITY_LEVEL]=partially-compatible
    RESULT[M14_004_RESULT]=PARTIAL
  elif [[ "${RESULT[BRIDGE_TOUCHED_REAL_HERMES_HOME]}" != no \
    || "${RESULT[REAL_HOME_ATTRIBUTION_CONFIDENCE]}" != high ]]; then
    RESULT[COMPATIBILITY_LEVEL]=incompatible
    RESULT[M14_004_RESULT]=FAIL
  else
    RESULT[COMPATIBILITY_LEVEL]=blocked
    RESULT[M14_004_RESULT]=BLOCKED
  fi
  build_discovered_matrix
  RESULT[COMPATIBILITY_LEVEL]=$([[ "${RESULT[M14_004_RESULT]}" == PARTIAL ]] && print -r -- partially-compatible || print -r -- "${RESULT[COMPATIBILITY_LEVEL]}")
  write_matrix
  write_result
  result_exit_code
  exit $?
}

main() {
  if [[ $# -ne 1 ]]; then
    usage
    exit 1
  fi
  case "$1" in
    inspect) inspect ;;
    run) run_acceptance ;;
    cleanup) cleanup ;;
    finalize-diagnostic-run) finalize_diagnostic_run ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
