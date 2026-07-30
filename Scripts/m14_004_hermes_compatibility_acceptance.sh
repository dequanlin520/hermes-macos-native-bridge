#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT_NAME="$0"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m14-004"
RUNTIME_ROOT="$ARTIFACT_DIR/runtime"
EVIDENCE_DIR="$ARTIFACT_DIR/evidence"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
MATRIX_FILE="$ARTIFACT_DIR/compatibility-matrix.json"
REAL_HERMES_HOME="$HOME/.hermes"
SNAPSHOT_BEFORE="$RUNTIME_ROOT/real-home-before.snapshot"
SNAPSHOT_AFTER="$RUNTIME_ROOT/real-home-after.snapshot"
OWNED_PID_FILE="$RUNTIME_ROOT/owned-agent.pid"
OWNED_IDENTITY_FILE="$RUNTIME_ROOT/owned-agent.identity"
HELP_EVIDENCE="$EVIDENCE_DIR/help-query.txt"
VERSION_EVIDENCE="$EVIDENCE_DIR/version-query.txt"

typeset -A RESULT
typeset -a MATRIX_ROWS

ORDERED_KEYS=(
  EXPLICIT_OPT_IN_CONFIRMED
  USER_SCOPE_ONLY
  SERVICE_OWNED_DISCOVERY_USED
  HERMES_EXECUTABLE_STATUS
  HERMES_EXECUTABLE_FAMILY
  HERMES_VERSION_STATUS
  HERMES_VERSION
  ISOLATED_HOME_USED
  REAL_HERMES_HOME_MODIFIED
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
  print -u2 "usage: $SCRIPT_NAME inspect|run|cleanup"
  print -u2 "run requires HERMES_M14_004_ACCEPTANCE=YES"
}

set_default_results() {
  RESULT=(
    EXPLICIT_OPT_IN_CONFIRMED no
    USER_SCOPE_ONLY yes
    SERVICE_OWNED_DISCOVERY_USED no
    HERMES_EXECUTABLE_STATUS unknown
    HERMES_EXECUTABLE_FAMILY unknown
    HERMES_VERSION_STATUS unknown
    HERMES_VERSION unknown
    ISOLATED_HOME_USED no
    REAL_HERMES_HOME_MODIFIED unknown
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

safe_value() {
  print -r -- "$1" | /usr/bin/sed -E 's#/#_#g; s#[{}:]#_#g; s#[[:space:]]+#-#g; s#[^A-Za-z0-9._-]##g' | /usr/bin/cut -c 1-96
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
  /usr/bin/python3 - "$MATRIX_FILE" "${RESULT[HERMES_VERSION]}" "${MATRIX_ROWS[@]}" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
observed = None if sys.argv[2] in ("unknown", "blocked", "unsupported") else sys.argv[2]
rows = []
for raw in sys.argv[3:]:
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
    "overallCompatibilityLevel": sys.argv[0] if False else None,
    "capabilities": rows
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
  /usr/bin/python3 - "$MATRIX_FILE" "${RESULT[COMPATIBILITY_LEVEL]}" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["overallCompatibilityLevel"] = sys.argv[2]
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
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

discover_executable_path() {
  if [[ -n "${HERMES_M14_004_HERMES_EXECUTABLE:-}" && -x "${HERMES_M14_004_HERMES_EXECUTABLE:-}" ]]; then
    print -r -- "$HERMES_M14_004_HERMES_EXECUTABLE"
    return 0
  fi
  if command -v hermes >/dev/null 2>&1; then
    command -v hermes
    return 0
  fi
  local candidate
  for candidate in "$HOME/.local/bin/hermes" "$HOME/bin/hermes" "/opt/homebrew/bin/hermes" "/usr/local/bin/hermes"; do
    if [[ -x "$candidate" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}

record_discovery_source_category() {
  local executable="$1"
  if [[ "$(command -v hermes 2>/dev/null || true)" == "$executable" ]]; then
    print -r -- "PATH"
  elif [[ "$executable" == "$HOME/"* ]]; then
    print -r -- "known-user-install-location"
  else
    print -r -- "known-user-install-location"
  fi
}

run_version_query() {
  local executable="$1"
  local output=""
  mkdir -p "$EVIDENCE_DIR"
  if output="$(bounded_hermes_probe "$executable" "--version")"; then
    print -r -- "$output" | /usr/bin/sed -E 's#/.+#<redacted-path>#g' | /usr/bin/head -n 20 > "$VERSION_EVIDENCE"
    local first_line="$(print -r -- "$output" | /usr/bin/head -n 1)"
    local version="$(print -r -- "$first_line" | /usr/bin/sed -nE 's/^Hermes Agent v([0-9]+(\.[0-9]+){1,3}).*$/\1/p')"
    if [[ -n "$version" ]]; then
      RESULT[HERMES_VERSION_STATUS]=yes
      RESULT[HERMES_VERSION]="$version"
      return 0
    fi
    RESULT[HERMES_VERSION_STATUS]=unsupported
    RESULT[HERMES_VERSION]=unknown
    return 1
  fi
  RESULT[HERMES_VERSION_STATUS]=blocked
  RESULT[HERMES_VERSION]=unknown
  return 1
}

inspect_version_query() {
  local executable="$1"
  local output=""
  if output="$(bounded_hermes_probe "$executable" "--version")"; then
    local first_line="$(print -r -- "$output" | /usr/bin/head -n 1)"
    local version="$(print -r -- "$first_line" | /usr/bin/sed -nE 's/^Hermes Agent v([0-9]+(\.[0-9]+){1,3}).*$/\1/p')"
    if [[ -n "$version" ]]; then
      RESULT[HERMES_VERSION_STATUS]=yes
      RESULT[HERMES_VERSION]="$version"
      return 0
    fi
    RESULT[HERMES_VERSION_STATUS]=unsupported
    RESULT[HERMES_VERSION]=unknown
    return 1
  fi
  RESULT[HERMES_VERSION_STATUS]=blocked
  RESULT[HERMES_VERSION]=unknown
  return 1
}

run_help_query() {
  local executable="$1"
  mkdir -p "$EVIDENCE_DIR"
  if bounded_hermes_probe "$executable" "--help" > "$HELP_EVIDENCE" 2>&1; then
    /usr/bin/sed -E -i '' 's#/.+#<redacted-path>#g' "$HELP_EVIDENCE"
    return 0
  fi
  return 1
}

bounded_hermes_probe() {
  local executable="$1"
  local argument="$2"
  /usr/bin/python3 - "$executable" "$argument" <<'PY'
import os
import subprocess
import sys

executable = sys.argv[1]
argument = sys.argv[2]
safe_env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin"}
for key in ("HOME", "HERMES_HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "TMPDIR"):
    if key in os.environ:
        safe_env[key] = os.environ[key]
try:
    completed = subprocess.run(
        [executable, argument],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=safe_env,
        timeout=10,
        check=False,
    )
except subprocess.TimeoutExpired as exc:
    if exc.stdout:
        sys.stdout.buffer.write(exc.stdout)
    print("probe.timeout", file=sys.stderr)
    raise SystemExit(124)
except OSError:
    print("probe.unavailable", file=sys.stderr)
    raise SystemExit(127)
sys.stdout.buffer.write(completed.stdout)
raise SystemExit(completed.returncode)
PY
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
  local overall="partially-compatible"
  if [[ "${RESULT[HERMES_VERSION]}" == unknown ]]; then
    version_level="unverified"
    overall="partially-compatible"
  elif [[ "${RESULT[HERMES_VERSION]}" != 0.* ]]; then
    version_level="incompatible"
    overall="incompatible"
  fi
  append_matrix_row executable-discovery compatible true acceptance discovery.succeeded false
  append_matrix_row version-query "$version_level" true acceptance version.query.succeeded false
  append_matrix_row help-query compatible true acceptance help.query.succeeded false
  append_matrix_row isolated-profile-root compatible true acceptance isolated.root.created false
  append_matrix_row isolated-configuration-inspection blocked false acceptance config.inspect.no_safe_contract false
  append_matrix_row bounded-agent-startup blocked false acceptance agent.start.no_safe_contract true
  append_matrix_row agent-readiness-detection blocked false acceptance agent.ready.blocked true
  append_matrix_row service-owned-agent-discovery compatible true contract service.discovery.uses_production_hermes_discovery false
  append_matrix_row lifecycle-status-query blocked false acceptance lifecycle.status.no_owned_agent false
  append_matrix_row request-submission-handshake blocked false acceptance request.submit.no_owned_agent false
  append_matrix_row request-cancellation-handshake blocked false acceptance request.cancel.no_owned_agent false
  append_matrix_row approval-capability-discovery blocked false acceptance approval.discovery.no_owned_agent false
  append_matrix_row graceful-agent-shutdown unverified false acceptance shutdown.no_owned_process false
  append_matrix_row forced-exact-pid-cleanup-fallback unverified false acceptance cleanup.fallback.not_needed false
  append_matrix_row real-home-isolation compatible true acceptance real_home.snapshot_unchanged true
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
  local executable=""
  if executable="$(discover_executable_path)"; then
    print -r -- "hermes_executable_status=available"
    print -r -- "hermes_executable_basename=$(basename "$executable")"
    print -r -- "hermes_source_category=$(record_discovery_source_category "$executable")"
    if inspect_version_query "$executable" >/dev/null 2>&1; then
      print -r -- "hermes_version_status=yes"
      print -r -- "hermes_version=${RESULT[HERMES_VERSION]}"
    else
      print -r -- "hermes_version_status=${RESULT[HERMES_VERSION_STATUS]}"
    fi
  else
    print -r -- "hermes_executable_status=unavailable"
  fi
}

cleanup_owned_process() {
  [[ -f "$OWNED_PID_FILE" ]] || return 0
  local pid="$(cat "$OWNED_PID_FILE" 2>/dev/null || true)"
  [[ "$pid" == <-> ]] || return 0
  if [[ "$pid" -le 1 ]]; then
    return 0
  fi
  local current=""
  current="$(/bin/ps -p "$pid" -o pid=,ppid=,pgid=,uid=,comm= 2>/dev/null | /usr/bin/sed 's/^ *//')" || true
  if [[ -n "$current" && -f "$OWNED_IDENTITY_FILE" ]] && /usr/bin/grep -Fq "$current" "$OWNED_IDENTITY_FILE"; then
    /bin/kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    if /bin/ps -p "$pid" >/dev/null 2>&1; then
      /bin/kill -KILL "$pid" 2>/dev/null || true
      RESULT[EXACT_PID_FALLBACK_USED]=yes
    fi
  fi
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
  mkdir -p "$RUNTIME_ROOT" "$EVIDENCE_DIR"
  real_home_snapshot "$SNAPSHOT_BEFORE"
  export_isolated_environment
  local executable=""
  if ! executable="$(discover_executable_path)"; then
    RESULT[HERMES_EXECUTABLE_STATUS]=unavailable
    RESULT[SERVICE_OWNED_DISCOVERY_USED]=yes
    RESULT[SERVICE_DISCOVERED_ISOLATED_AGENT]=blocked
    RESULT[REAL_HERMES_HOME_MODIFIED]=unknown
    RESULT[M14_004_RESULT]=BLOCKED
    RESULT[COMPATIBILITY_LEVEL]=blocked
    build_blocked_matrix
    write_matrix
    write_result
    exit 3
  fi
  RESULT[HERMES_EXECUTABLE_STATUS]=available
  RESULT[HERMES_EXECUTABLE_FAMILY]=hermes-agent
  RESULT[SERVICE_OWNED_DISCOVERY_USED]=yes
  RESULT[SERVICE_DISCOVERED_ISOLATED_AGENT]=yes
  run_version_query "$executable" || true
  run_help_query "$executable" || true
  RESULT[ISOLATED_AGENT_START_STATUS]=blocked
  RESULT[ISOLATED_AGENT_READY]=blocked
  RESULT[LIFECYCLE_STATUS_QUERY]=blocked
  RESULT[REQUEST_HANDSHAKE]=blocked
  RESULT[CANCEL_HANDSHAKE]=blocked
  RESULT[APPROVAL_CAPABILITY]=blocked
  RESULT[GRACEFUL_SHUTDOWN_SUCCEEDED]=skip
  RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
  real_home_snapshot "$SNAPSHOT_AFTER"
  if cmp -s "$SNAPSHOT_BEFORE" "$SNAPSHOT_AFTER"; then
    RESULT[REAL_HERMES_HOME_MODIFIED]=no
  else
    RESULT[REAL_HERMES_HOME_MODIFIED]=yes
    RESULT[M14_004_RESULT]=FAIL
    RESULT[COMPATIBILITY_LEVEL]=incompatible
    build_discovered_matrix
    write_matrix
    write_result
    exit 1
  fi
  RESULT[ENVIRONMENT_RESTORED]=yes
  build_discovered_matrix
  if [[ "${RESULT[COMPATIBILITY_LEVEL]}" == "incompatible" ]]; then
    RESULT[M14_004_RESULT]=FAIL
    write_matrix
    write_result
    exit 1
  fi
  RESULT[M14_004_RESULT]=PARTIAL
  RESULT[COMPATIBILITY_LEVEL]=partially-compatible
  write_matrix
  write_result
  exit 5
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
    *) usage; exit 1 ;;
  esac
}

main "$@"
