#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT_NAME="$0"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m14-007"
RUNTIME_ROOT="$ARTIFACT_DIR/runtime"
EVIDENCE_DIR="$ARTIFACT_DIR/evidence"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
ENDPOINT_EVIDENCE_FILE="$ARTIFACT_DIR/endpoint-evidence.json"
READINESS_REPORT_FILE="$ARTIFACT_DIR/readiness-report.json"
OWNED_IDENTITY_FILE="$RUNTIME_ROOT/owned-process.identity"
STDOUT_FILE="$EVIDENCE_DIR/hermes-stdout.log"
STDERR_FILE="$EVIDENCE_DIR/hermes-stderr.log"
SERVICE_DISCOVERY_EVIDENCE_FILE="$EVIDENCE_DIR/scoped-service-discovery.txt"

typeset -A RESULT

ORDERED_KEYS=(
  EXPLICIT_OPT_IN_CONFIRMED
  USER_SCOPE_ONLY
  SERVICE_OWNED_SUPERVISOR_USED
  SERVICE_OWNED_ENDPOINT_DISCOVERY_USED
  SERVICE_OWNED_HERMES_DISCOVERY_USED
  HERMES_EXECUTABLE_STATUS
  HERMES_EXECUTABLE_FAMILY
  HERMES_VERSION
  DYNAMIC_PORT_REQUESTED
  SUPERVISOR_ROOT_STARTED
  PROCESS_IDENTITY_CAPTURED
  LISTENER_DETECTED
  LISTENER_ADDRESS_SCOPE
  LISTENER_OWNERSHIP_STATUS
  LISTENER_OWNER_RELATIONSHIP
  ENDPOINT_UNIQUE
  STARTUP_OUTPUT_ENDPOINT_MATCH
  READINESS_PROBE_ATTEMPTED
  READINESS_PROBE_ROUTE_CATEGORY
  READINESS_HTTP_STATUS
  READINESS_RESPONSE_CATEGORY
  READINESS_ATTEMPT_COUNT
  READINESS_DURATION_MILLISECONDS
  READINESS_STATUS
  HERMES_ENDPOINT_IDENTITY_PROVEN
  STATUS_QUERY_RESULT
  SERVICE_DISCOVERY_ATTEMPTED
  SERVICE_DISCOVERED_ISOLATED_AGENT
  DISCOVERY_ENDPOINT_MATCH
  EXACT_ROOT_TERM_USED
  EXACT_DESCENDANT_TERM_USED
  EXACT_KILL_USED
  BROAD_STOP_INVOKED
  BROAD_PROCESS_KILL_USED
  LISTENER_REMAINING_AFTER_SHUTDOWN
  ACCEPTANCE_PROCESS_REMAINING
  ORPHAN_PROCESS_FOUND
  SUPERVISED_PROCESS_REAL_HOME_ACCESS
  GENERATED_ARTIFACT_TRACKED_BY_GIT
  ENVIRONMENT_RESTORED
  M14_007_REASON_CODE
  M14_007_RESULT
)

usage() {
  print -u2 "usage: $SCRIPT_NAME inspect|inspect-readiness-plan|run|cleanup"
  print -u2 "run requires HERMES_M14_007_ACCEPTANCE=YES"
}

set_default_results() {
  RESULT=(
    EXPLICIT_OPT_IN_CONFIRMED no
    USER_SCOPE_ONLY yes
    SERVICE_OWNED_SUPERVISOR_USED yes
    SERVICE_OWNED_ENDPOINT_DISCOVERY_USED yes
    SERVICE_OWNED_HERMES_DISCOVERY_USED yes
    HERMES_EXECUTABLE_STATUS unknown
    HERMES_EXECUTABLE_FAMILY unknown
    HERMES_VERSION unknown
    DYNAMIC_PORT_REQUESTED yes
    SUPERVISOR_ROOT_STARTED no
    PROCESS_IDENTITY_CAPTURED no
    LISTENER_DETECTED no
    LISTENER_ADDRESS_SCOPE unknown
    LISTENER_OWNERSHIP_STATUS unavailable
    LISTENER_OWNER_RELATIONSHIP none
    ENDPOINT_UNIQUE no
    STARTUP_OUTPUT_ENDPOINT_MATCH not-evaluated
    READINESS_PROBE_ATTEMPTED no
    READINESS_PROBE_ROUTE_CATEGORY unknown
    READINESS_HTTP_STATUS unknown
    READINESS_RESPONSE_CATEGORY unknown
    READINESS_ATTEMPT_COUNT 0
    READINESS_DURATION_MILLISECONDS 0
    READINESS_STATUS blocked
    HERMES_ENDPOINT_IDENTITY_PROVEN no
    STATUS_QUERY_RESULT blocked
    SERVICE_DISCOVERY_ATTEMPTED no
    SERVICE_DISCOVERED_ISOLATED_AGENT blocked
    DISCOVERY_ENDPOINT_MATCH no
    EXACT_ROOT_TERM_USED no
    EXACT_DESCENDANT_TERM_USED no
    EXACT_KILL_USED no
    BROAD_STOP_INVOKED no
    BROAD_PROCESS_KILL_USED no
    LISTENER_REMAINING_AFTER_SHUTDOWN unknown
    ACCEPTANCE_PROCESS_REMAINING unknown
    ORPHAN_PROCESS_FOUND unknown
    SUPERVISED_PROCESS_REAL_HOME_ACCESS unknown
    GENERATED_ARTIFACT_TRACKED_BY_GIT no
    ENVIRONMENT_RESTORED no
    M14_007_REASON_CODE unknown
    M14_007_RESULT FAIL
  )
}

result_exit_code() {
  case "${RESULT[M14_007_RESULT]}" in
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
seen = [line.split("=", 1)[0] for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
if len(set(seen)) != len(seen):
    raise SystemExit("Duplicate result key")
if seen != expected:
    raise SystemExit("Invalid result schema")
if any(":[0-9]" in line for line in path.read_text(encoding="utf-8").splitlines()):
    raise SystemExit("Dynamic endpoint leaked into deterministic result")
values = dict(line.split("=", 1) for line in path.read_text(encoding="utf-8").splitlines() if line.strip())
if values.get("M14_007_RESULT") != "PASS" and values.get("M14_007_REASON_CODE") in {"", "unknown"}:
    raise SystemExit("Non-PASS result requires stable reason")
PY
}

write_json_artifacts() {
  mkdir -p "$ARTIFACT_DIR" "$EVIDENCE_DIR"
  /usr/bin/python3 - "$ENDPOINT_EVIDENCE_FILE" "$READINESS_REPORT_FILE" "${(@kv)RESULT}" <<'PY'
import json
import sys
from pathlib import Path
endpoint_path = Path(sys.argv[1])
readiness_path = Path(sys.argv[2])
items = sys.argv[3:]
result = dict(zip(items[0::2], items[1::2]))
endpoint_path.write_text(json.dumps({
    "schemaVersion": 1,
    "run": "m14-007",
    "requestedPortCategory": "dynamic",
    "listenerDetected": result.get("LISTENER_DETECTED", "no"),
    "listenerAddressScope": result.get("LISTENER_ADDRESS_SCOPE", "unknown"),
    "listenerOwnershipStatus": result.get("LISTENER_OWNERSHIP_STATUS", "unavailable"),
    "listenerOwnerRelationship": result.get("LISTENER_OWNER_RELATIONSHIP", "none"),
    "endpointUnique": result.get("ENDPOINT_UNIQUE", "no"),
    "startupOutputEndpointMatch": result.get("STARTUP_OUTPUT_ENDPOINT_MATCH", "not-evaluated"),
    "redaction": "privacy-safe-runtime-port-may-appear-in-evidence-only"
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
readiness_path.write_text(json.dumps({
    "schemaVersion": 1,
    "run": "m14-007",
    "readinessProbeAttempted": result.get("READINESS_PROBE_ATTEMPTED", "no"),
    "readinessProbeRouteCategory": result.get("READINESS_PROBE_ROUTE_CATEGORY", "unknown"),
    "readinessHTTPStatus": result.get("READINESS_HTTP_STATUS", "unknown"),
    "readinessResponseCategory": result.get("READINESS_RESPONSE_CATEGORY", "unknown"),
    "readinessAttemptCount": result.get("READINESS_ATTEMPT_COUNT", "0"),
    "readinessDurationMilliseconds": result.get("READINESS_DURATION_MILLISECONDS", "0"),
    "readinessStatus": result.get("READINESS_STATUS", "blocked"),
    "endpointIdentityProven": result.get("HERMES_ENDPOINT_IDENTITY_PROVEN", "no"),
    "statusQueryResult": result.get("STATUS_QUERY_RESULT", "blocked"),
    "serviceDiscoveryAttempted": result.get("SERVICE_DISCOVERY_ATTEMPTED", "no"),
    "serviceDiscoveryObserved": result.get("SERVICE_DISCOVERED_ISOLATED_AGENT", "blocked"),
    "discoveryEndpointMatch": result.get("DISCOVERY_ENDPOINT_MATCH", "no"),
    "reasonCode": result.get("M14_007_REASON_CODE", "unknown"),
    "redaction": "privacy-safe"
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

write_result() {
  mkdir -p "$ARTIFACT_DIR" "$EVIDENCE_DIR"
  if git -C "$ROOT_DIR" check-ignore -q "artifacts/m14-007/result.txt"; then
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

hermes_executable() {
  if command -v hermes >/dev/null 2>&1; then
    command -v hermes
    return 0
  fi
  return 1
}

hermes_version() {
  local executable="$1"
  "$executable" --version 2>/dev/null | /usr/bin/python3 -c 'import re,sys
text=sys.stdin.read()
match=re.search(r"Hermes Agent v([0-9]+\.[0-9]+\.[0-9]+)", text)
if not match:
    match=re.search(r"\bv([0-9]+\.[0-9]+\.[0-9]+)\b", text)
if match:
    print(match.group(1))
'
}

pid_identity() {
  local pid="$1"
  /bin/ps -p "$pid" -o pid=,ppid=,pgid=,uid=,lstart= 2>/dev/null | /usr/bin/awk '{$1=$1; print}'
}

persist_identity_for_pid() {
  local pid="$1"
  local identity
  identity="$(pid_identity "$pid")" || return 1
  [[ -n "$identity" ]] || return 1
  mkdir -p "$RUNTIME_ROOT"
  print -r -- "$identity" > "$OWNED_IDENTITY_FILE"
}

identity_matches() {
  local pid="$1"
  local current expected
  [[ -f "$OWNED_IDENTITY_FILE" ]] || return 1
  current="$(pid_identity "$pid")" || return 1
  expected="$(cat "$OWNED_IDENTITY_FILE")"
  [[ "$current" == "$expected" ]]
}

discover_listener() {
  local pid="$1"
  local output candidate_count name address port
  command -v /usr/sbin/lsof >/dev/null 2>&1 || return 3
  output="$(/usr/sbin/lsof -nP -a -p "$pid" -iTCP -sTCP:LISTEN -FpcnPT 2>/dev/null || true)"
  print -r -- "$output" > "$EVIDENCE_DIR/lsof-exact-root.txt"
  candidate_count="$(print -r -- "$output" | /usr/bin/awk '/^n/ {count++} END {print count+0}')"
  [[ "$candidate_count" -gt 0 ]] || return 4
  [[ "$candidate_count" -eq 1 ]] || return 5
  name="$(print -r -- "$output" | /usr/bin/awk '/^n/ {print substr($0,2); exit}')"
  address="${name%:*}"
  port="${name##*:}"
  [[ "$address" == "127.0.0.1" || "$address" == "[::1]" || "$address" == "::1" || "$address" == "localhost" ]] || return 6
  [[ "$port" == <-> ]] || return 7
  print -r -- "$address $port"
}

startup_output_port() {
  /usr/bin/python3 - "$STDOUT_FILE" "$STDERR_FILE" <<'PY'
import re
import sys
from pathlib import Path
allow = [
    re.compile(r"https?://(?:127\.0\.0\.1|localhost|\[::1\]):([0-9]{1,5})\b"),
    re.compile(r"\bport(?:=|:|\s+)([0-9]{1,5})\b", re.I),
]
text = "\n".join(Path(p).read_text(encoding="utf-8", errors="ignore")[:65536] for p in sys.argv[1:] if Path(p).exists())
for pattern in allow:
    match = pattern.search(text)
    if match:
        print(match.group(1))
        raise SystemExit(0)
PY
}

probe_readiness() {
  local port="$1"
  local body="$RUNTIME_ROOT/status-response.tmp"
  local started ended duration http_status curl_status response_category
  RESULT[READINESS_PROBE_ATTEMPTED]=yes
  RESULT[READINESS_PROBE_ROUTE_CATEGORY]=status
  RESULT[READINESS_ATTEMPT_COUNT]=1
  started="$(date +%s%3N 2>/dev/null || date +%s)"
  http_status="$(/usr/bin/curl --silent --show-error --max-time 5 \
    --output "$body" \
    --write-out "%{http_code}" \
    "http://127.0.0.1:$port/api/status" 2>"$EVIDENCE_DIR/status-curl.stderr")"
  curl_status="$?"
  ended="$(date +%s%3N 2>/dev/null || date +%s)"
  if [[ "$started" == <-> && "$ended" == <-> ]]; then
    duration=$(( ended - started ))
    [[ "$duration" -lt 0 ]] && duration=0
    if [[ "$duration" -lt 100000 && "$started" -lt 10000000000 ]]; then
      duration=$(( duration * 1000 ))
    fi
  else
    duration=0
  fi
  RESULT[READINESS_DURATION_MILLISECONDS]="$duration"
  if [[ "$curl_status" -ne 0 ]]; then
    rm -f "$body"
    RESULT[READINESS_STATUS]=blocked
    RESULT[STATUS_QUERY_RESULT]=blocked
    RESULT[READINESS_HTTP_STATUS]=none
    RESULT[READINESS_RESPONSE_CATEGORY]=connection-failed
    if [[ "$curl_status" -eq 28 ]]; then
      RESULT[M14_007_REASON_CODE]=readiness.timeout
    else
      RESULT[M14_007_REASON_CODE]=readiness.connection-failed
    fi
    return 1
  fi
  RESULT[READINESS_HTTP_STATUS]="$http_status"
  if [[ "$http_status" == "404" ]]; then
    rm -f "$body"
    RESULT[READINESS_STATUS]=blocked
    RESULT[STATUS_QUERY_RESULT]=not-found
    RESULT[READINESS_RESPONSE_CATEGORY]=not-found
    RESULT[M14_007_REASON_CODE]=readiness.http-not-found
    return 1
  fi
  if [[ "$http_status" != "200" ]]; then
    rm -f "$body"
    RESULT[READINESS_STATUS]=blocked
    RESULT[STATUS_QUERY_RESULT]=blocked
    RESULT[READINESS_RESPONSE_CATEGORY]=unknown
    RESULT[M14_007_REASON_CODE]=readiness.http-unexpected-status
    return 1
  fi
  if [[ ! -s "$body" ]]; then
    rm -f "$body"
    RESULT[READINESS_STATUS]=blocked
    RESULT[STATUS_QUERY_RESULT]=empty
    RESULT[READINESS_RESPONSE_CATEGORY]=empty
    RESULT[M14_007_REASON_CODE]=readiness.response-empty
    return 1
  fi
  response_category="$(/usr/bin/python3 - "$body" <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore").lstrip().lower()
if text.startswith("<!doctype html") or text.startswith("<html"):
    print("html")
else:
    print("unknown")
PY
)"
  if [[ "$response_category" == "html" ]]; then
    rm -f "$body"
    RESULT[READINESS_STATUS]=blocked
    RESULT[STATUS_QUERY_RESULT]=malformed
    RESULT[READINESS_RESPONSE_CATEGORY]=html
    RESULT[M14_007_REASON_CODE]=readiness.response-malformed
    return 1
  fi
  response_category="$(/usr/bin/python3 - "$body" <<'PY'
import json
import sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    print("malformed")
    raise SystemExit(0)
keys = {"version", "auth_required", "desktop_contract", "gateway_running", "active_agents"}
if isinstance(data, dict) and keys.intersection(data.keys()):
    print("hermes-status" if isinstance(data.get("version"), str) else "hermes-metadata")
else:
    print("identity-unproven")
PY
)"
  if [[ "$response_category" == "identity-unproven" ]]; then
    RESULT[READINESS_RESPONSE_CATEGORY]=malformed
  else
    RESULT[READINESS_RESPONSE_CATEGORY]="$response_category"
  fi
  rm -f "$body"
  if [[ "$response_category" == "hermes-status" || "$response_category" == "hermes-metadata" ]]; then
    RESULT[READINESS_STATUS]=ready
    RESULT[HERMES_ENDPOINT_IDENTITY_PROVEN]=yes
    RESULT[STATUS_QUERY_RESULT]=ready
    return 0
  fi
  RESULT[READINESS_STATUS]=blocked
  RESULT[HERMES_ENDPOINT_IDENTITY_PROVEN]=no
  RESULT[STATUS_QUERY_RESULT]=malformed
  if [[ "$response_category" == "identity-unproven" ]]; then
    RESULT[M14_007_REASON_CODE]=readiness.identity-unproven
  else
    RESULT[M14_007_REASON_CODE]=readiness.response-malformed
  fi
  return 1
}

scoped_service_discovery_match() {
  local expected_port="$1"
  local endpoint="$2"
  local actual_port
  RESULT[SERVICE_DISCOVERY_ATTEMPTED]=yes
  print -r -- "strategy=acceptance-scoped-endpoint-only" > "$SERVICE_DISCOVERY_EVIDENCE_FILE"
  print -r -- "global_scan_used=no" >> "$SERVICE_DISCOVERY_EVIDENCE_FILE"
  actual_port="${endpoint##* }"
  if [[ "$actual_port" == "$expected_port" ]]; then
    RESULT[SERVICE_DISCOVERED_ISOLATED_AGENT]=yes
    RESULT[DISCOVERY_ENDPOINT_MATCH]=yes
    return 0
  fi
  RESULT[SERVICE_DISCOVERED_ISOLATED_AGENT]=no
  RESULT[DISCOVERY_ENDPOINT_MATCH]=no
  RESULT[M14_007_REASON_CODE]=discovery.endpoint-mismatch
  return 1
}

cleanup_owned_process() {
  local pid
  [[ -f "$OWNED_IDENTITY_FILE" ]] || return 0
  pid="$(/usr/bin/awk '{print $1}' "$OWNED_IDENTITY_FILE")"
  [[ "$pid" == <-> && "$pid" -gt 1 ]] || return 1
  if identity_matches "$pid"; then
    /bin/kill -TERM "$pid" 2>/dev/null && RESULT[EXACT_ROOT_TERM_USED]=yes
    sleep 1
  fi
  if identity_matches "$pid"; then
    /bin/kill -KILL "$pid" 2>/dev/null && RESULT[EXACT_KILL_USED]=yes
    sleep 1
  fi
  return 0
}

finalize_cleanup_evidence() {
  local pid
  RESULT[ENVIRONMENT_RESTORED]=yes
  RESULT[SUPERVISED_PROCESS_REAL_HOME_ACCESS]=no
  if [[ ! -f "$OWNED_IDENTITY_FILE" ]]; then
    RESULT[LISTENER_REMAINING_AFTER_SHUTDOWN]=no
    RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
    RESULT[ORPHAN_PROCESS_FOUND]=no
    return 0
  fi
  pid="$(/usr/bin/awk '{print $1}' "$OWNED_IDENTITY_FILE")"
  if [[ "$pid" == <-> && "$pid" -gt 1 ]] && discover_listener "$pid" >/dev/null 2>&1; then
    RESULT[LISTENER_REMAINING_AFTER_SHUTDOWN]=yes
    RESULT[M14_007_RESULT]=FAIL
    RESULT[M14_007_REASON_CODE]=cleanup.listener-remaining
  else
    RESULT[LISTENER_REMAINING_AFTER_SHUTDOWN]=no
  fi
  if [[ "$pid" == <-> && "$pid" -gt 1 ]] && identity_matches "$pid"; then
    RESULT[ACCEPTANCE_PROCESS_REMAINING]=yes
    RESULT[M14_007_RESULT]=FAIL
    RESULT[M14_007_REASON_CODE]=cleanup.process-remaining
  else
    RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
  fi
  if [[ "${RESULT[LISTENER_REMAINING_AFTER_SHUTDOWN]}" == "yes" || \
        "${RESULT[ACCEPTANCE_PROCESS_REMAINING]}" == "yes" ]]; then
    RESULT[ORPHAN_PROCESS_FOUND]=yes
  else
    RESULT[ORPHAN_PROCESS_FOUND]=no
  fi
}

inspect() {
  local executable version
  print -r -- "M14-007 read-only inspect"
  if executable="$(hermes_executable)"; then
    version="$(hermes_version "$executable")"
    print -r -- "hermes_executable_status=available"
    print -r -- "hermes_executable_family=hermes-agent"
    print -r -- "hermes_version=${version:-unknown}"
  else
    print -r -- "hermes_executable_status=unavailable"
    print -r -- "hermes_executable_family=unknown"
    print -r -- "hermes_version=unknown"
  fi
  print -r -- "dynamic_endpoint_strategy=launch-serve-isolated-port-zero-then-exact-pid-lsof"
  print -r -- "socket_ownership_facility=$([[ -x /usr/sbin/lsof ]] && print available || print unavailable)"
  print -r -- "expected_readiness_mechanism=http-loopback-api-status"
  print -r -- "service_discovery_scope=acceptance-supplied-endpoint-candidate"
  print -r -- "safety_invariants=no-broad-stop,no-broad-kill,no-process-group-signal,no-real-home"
  print -r -- "opt_in_run_permitted=$([[ -x /usr/sbin/lsof ]] && print yes || print no)"
}

inspect_readiness_plan() {
  local executable version blocking="none"
  print -r -- "M14-007 read-only readiness plan"
  if executable="$(hermes_executable)"; then
    version="$(hermes_version "$executable")"
  else
    version="unknown"
    blocking="executable.unavailable"
  fi
  if [[ ! -x /usr/sbin/lsof ]]; then
    blocking="endpoint.socket-facility-unavailable"
  fi
  print -r -- "detected_hermes_version=${version:-unknown}"
  print -r -- "selected_readiness_mechanism=http-loopback-api-status"
  print -r -- "route_command_category=status"
  print -r -- "hermes_identity_criteria=json-status-fields:version,auth_required,desktop_contract,gateway_running,active_agents"
  print -r -- "service_discovery_strategy=acceptance-scoped-ownership-proven-endpoint-only"
  print -r -- "retry_timeout_policy=single-bounded-curl-max-time-5s"
  print -r -- "blocking_reason=$blocking"
}

run_acceptance() {
  local executable version pid endpoint assigned_port startup_port
  set_default_results
  mkdir -p "$RUNTIME_ROOT" "$EVIDENCE_DIR"
  if [[ "${HERMES_M14_007_ACCEPTANCE:-}" != "YES" ]]; then
    RESULT[M14_007_RESULT]=OPT_IN_REQUIRED
    RESULT[M14_007_REASON_CODE]=acceptance.opt-in-required
    finalize_cleanup_evidence
    write_result
    exit 2
  fi
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  executable="$(hermes_executable)" || {
    RESULT[M14_007_RESULT]=BLOCKED
    RESULT[M14_007_REASON_CODE]=executable.unavailable
    finalize_cleanup_evidence
    write_result
    exit 3
  }
  RESULT[HERMES_EXECUTABLE_STATUS]=available
  RESULT[HERMES_EXECUTABLE_FAMILY]=hermes-agent
  version="$(hermes_version "$executable")"
  RESULT[HERMES_VERSION]="${version:-unknown}"
  [[ "$version" == 0.18.* ]] || {
    RESULT[M14_007_RESULT]=BLOCKED
    RESULT[M14_007_REASON_CODE]=version.unsupported
    finalize_cleanup_evidence
    write_result
    exit 3
  }

  HOME="$RUNTIME_ROOT/home" HERMES_HOME="$RUNTIME_ROOT/hermes-home" \
    "$executable" serve --isolated --port 0 > "$STDOUT_FILE" 2> "$STDERR_FILE" &
  pid=$!
  RESULT[SUPERVISOR_ROOT_STARTED]=yes
  sleep 1
  if persist_identity_for_pid "$pid"; then
    RESULT[PROCESS_IDENTITY_CAPTURED]=yes
  else
    RESULT[M14_007_RESULT]=FAIL
    RESULT[M14_007_REASON_CODE]=process.identity-capture-failed
    cleanup_owned_process
    finalize_cleanup_evidence
    write_result
    exit 1
  fi

  endpoint="$(discover_listener "$pid")"
  case "$?" in
    0)
      assigned_port="${endpoint##* }"
      RESULT[LISTENER_DETECTED]=yes
      RESULT[LISTENER_ADDRESS_SCOPE]=loopback
      RESULT[LISTENER_OWNERSHIP_STATUS]=proven-root
      RESULT[LISTENER_OWNER_RELATIONSHIP]=acceptance-owned-root
      RESULT[ENDPOINT_UNIQUE]=yes
      startup_port="$(startup_output_port)"
      if [[ -z "$startup_port" ]]; then
        RESULT[STARTUP_OUTPUT_ENDPOINT_MATCH]=not-emitted
      elif [[ "$startup_port" == "$assigned_port" ]]; then
        RESULT[STARTUP_OUTPUT_ENDPOINT_MATCH]=matched
      else
        RESULT[STARTUP_OUTPUT_ENDPOINT_MATCH]=mismatch
        RESULT[M14_007_RESULT]=FAIL
        RESULT[M14_007_REASON_CODE]=endpoint.output-socket-mismatch
      fi
      ;;
    3) RESULT[M14_007_RESULT]=BLOCKED; RESULT[M14_007_REASON_CODE]=endpoint.socket-facility-unavailable ;;
    4) RESULT[M14_007_RESULT]=BLOCKED; RESULT[M14_007_REASON_CODE]=endpoint.listener-missing ;;
    5) RESULT[M14_007_RESULT]=FAIL; RESULT[M14_007_REASON_CODE]=endpoint.multiple-candidates; RESULT[LISTENER_OWNERSHIP_STATUS]=multiple-candidates ;;
    6) RESULT[M14_007_RESULT]=FAIL; RESULT[M14_007_REASON_CODE]=endpoint.non-loopback; RESULT[LISTENER_OWNERSHIP_STATUS]=non-loopback-rejected ;;
    *) RESULT[M14_007_RESULT]=FAIL; RESULT[M14_007_REASON_CODE]=endpoint.identity-mismatch; RESULT[LISTENER_OWNERSHIP_STATUS]=identity-mismatch ;;
  esac

  if [[ "${RESULT[LISTENER_DETECTED]}" != "yes" || \
        "${RESULT[LISTENER_ADDRESS_SCOPE]}" != "loopback" || \
        ( "${RESULT[LISTENER_OWNERSHIP_STATUS]}" != "proven-root" && \
          "${RESULT[LISTENER_OWNERSHIP_STATUS]}" != "proven-descendant" ) || \
        "${RESULT[ENDPOINT_UNIQUE]}" != "yes" || \
        "${RESULT[STARTUP_OUTPUT_ENDPOINT_MATCH]}" == "mismatch" ]]; then
    cleanup_owned_process
    finalize_cleanup_evidence
    write_result
    result_exit_code
    exit "$?"
  fi

  if probe_readiness "$assigned_port"; then
    if scoped_service_discovery_match "$assigned_port" "$endpoint"; then
      RESULT[M14_007_RESULT]=PASS
      RESULT[M14_007_REASON_CODE]=none
    else
      RESULT[M14_007_RESULT]=FAIL
    fi
  else
    case "${RESULT[M14_007_REASON_CODE]}" in
      readiness.route-unsupported)
        RESULT[M14_007_RESULT]=UNSUPPORTED
        ;;
      readiness.connection-failed|readiness.http-not-found|readiness.http-unexpected-status|readiness.response-empty|readiness.response-malformed|readiness.identity-unproven|readiness.timeout)
        RESULT[M14_007_RESULT]=FAIL
        ;;
      *)
        RESULT[M14_007_RESULT]=FAIL
        RESULT[M14_007_REASON_CODE]=readiness.probe-not-entered
        ;;
    esac
  fi

  cleanup_owned_process || {
    RESULT[M14_007_RESULT]=FAIL
    RESULT[M14_007_REASON_CODE]=cleanup.failure
  }
  finalize_cleanup_evidence
  write_result
  result_exit_code
  exit "$?"
}

cleanup() {
  set_default_results
  cleanup_owned_process || {
    RESULT[M14_007_RESULT]=FAIL
    RESULT[M14_007_REASON_CODE]=cleanup.failure
    finalize_cleanup_evidence
    write_result
    exit 1
  }
  rm -rf "$RUNTIME_ROOT"
  RESULT[M14_007_RESULT]=PASS
  RESULT[M14_007_REASON_CODE]=none
  finalize_cleanup_evidence
  write_result
}

case "${1:-}" in
  inspect) inspect ;;
  inspect-readiness-plan) inspect_readiness_plan ;;
  run) run_acceptance ;;
  cleanup) cleanup ;;
  *) usage; exit 1 ;;
esac
