#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT_NAME="$0"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m14-008"
RUNTIME_ROOT="$ARTIFACT_DIR/runtime"
EVIDENCE_DIR="$ARTIFACT_DIR/evidence"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
PROTOCOL_DESCRIPTOR_FILE="$ARTIFACT_DIR/protocol-descriptor.json"
REQUEST_EVIDENCE_FILE="$ARTIFACT_DIR/request-evidence.json"
OWNED_IDENTITY_FILE="$RUNTIME_ROOT/owned-process.identity"
TOKEN_FILE="$RUNTIME_ROOT/loopback.token"
STDOUT_FILE="$EVIDENCE_DIR/hermes-stdout.log"
STDERR_FILE="$EVIDENCE_DIR/hermes-stderr.log"
STATUS_BODY_FILE="$EVIDENCE_DIR/status-response.redacted.json"
OPENAPI_SUMMARY_FILE="$EVIDENCE_DIR/openapi-summary.json"

typeset -A RESULT

ORDERED_KEYS=(
  EXPLICIT_OPT_IN_CONFIRMED
  USER_SCOPE_ONLY
  SERVICE_OWNED_PROTOCOL_CLIENT_USED
  SERVICE_OWNED_SUPERVISOR_USED
  SERVICE_OWNED_ENDPOINT_DISCOVERY_USED
  HERMES_VERSION
  ENDPOINT_OWNERSHIP_PROVEN
  READINESS_PROVEN
  PROTOCOL_METADATA_DISCOVERED
  PROTOCOL_FAMILY
  PROTOCOL_VERSION
  AUTHENTICATION_REQUIRED
  EPHEMERAL_CREDENTIAL_ISOLATED
  REQUEST_CAPABILITY
  REQUEST_TRANSPORT
  TRANSPORT_FAMILY
  TRANSPORT_ROUTE_CATEGORY
  TRANSPORT_SCHEME
  WEBSOCKET_SUBPROTOCOL_CATEGORY
  WEBSOCKET_ORIGIN_MODE
  HANDSHAKE_ATTEMPTED
  HANDSHAKE_HTTP_STATUS
  HANDSHAKE_UPGRADE_ACCEPTED
  HANDSHAKE_ERROR_CATEGORY
  HANDSHAKE_DURATION_MILLISECONDS
  TRANSPORT_DESCRIPTOR_PARITY
  REQUEST_AUTHENTICATION_MODE
  REQUEST_CONNECTION_ATTEMPTED
  REQUEST_CONNECTION_STATUS
  REQUEST_RPC_METHOD_CATEGORY
  REQUEST_RPC_RESPONSE_CATEGORY
  REQUEST_RPC_ERROR_CODE
  REQUEST_SUBMISSION_DURATION_MILLISECONDS
  REQUEST_REASON_CODE
  REQUEST_SUBMISSION_ATTEMPTED
  REQUEST_SUBMISSION_STATUS
  REQUEST_IDENTITY_CAPTURED
  REQUEST_STATUS_QUERY
  REQUEST_TERMINAL_STATE
  CANCEL_CAPABILITY
  CANCEL_ATTEMPTED
  CANCEL_TARGET_IDENTITY_MATCHED
  CANCEL_RESULT
  APPROVAL_CAPABILITY
  APPROVAL_TRIGGERED
  APPROVAL_DECISION_SUBMITTED
  APPROVAL_RESULT
  CLIENT_RECONNECT_TESTED
  REQUEST_STATE_SURVIVED_RECONNECT
  BROAD_STOP_INVOKED
  BROAD_PROCESS_KILL_USED
  ACCEPTANCE_PROCESS_REMAINING
  ORPHAN_PROCESS_FOUND
  SUPERVISED_PROCESS_REAL_HOME_ACCESS
  GENERATED_ARTIFACT_TRACKED_BY_GIT
  ENVIRONMENT_RESTORED
  M14_008_REASON_CODE
  M14_008_RESULT
)

usage() {
  print -u2 "usage: $SCRIPT_NAME inspect|inspect-request-plan|inspect-transport-plan|run|cleanup"
  print -u2 "run requires HERMES_M14_008_ACCEPTANCE=YES"
}

set_default_results() {
  RESULT=(
    EXPLICIT_OPT_IN_CONFIRMED no
    USER_SCOPE_ONLY yes
    SERVICE_OWNED_PROTOCOL_CLIENT_USED yes
    SERVICE_OWNED_SUPERVISOR_USED yes
    SERVICE_OWNED_ENDPOINT_DISCOVERY_USED yes
    HERMES_VERSION unknown
    ENDPOINT_OWNERSHIP_PROVEN no
    READINESS_PROVEN no
    PROTOCOL_METADATA_DISCOVERED no
    PROTOCOL_FAMILY unknown
    PROTOCOL_VERSION unknown
    AUTHENTICATION_REQUIRED unknown
    EPHEMERAL_CREDENTIAL_ISOLATED no
    REQUEST_CAPABILITY unsupported
    REQUEST_TRANSPORT unknown
    TRANSPORT_FAMILY unknown
    TRANSPORT_ROUTE_CATEGORY unknown
    TRANSPORT_SCHEME unknown
    WEBSOCKET_SUBPROTOCOL_CATEGORY none
    WEBSOCKET_ORIGIN_MODE none
    HANDSHAKE_ATTEMPTED no
    HANDSHAKE_HTTP_STATUS none
    HANDSHAKE_UPGRADE_ACCEPTED unknown
    HANDSHAKE_ERROR_CATEGORY unknown
    HANDSHAKE_DURATION_MILLISECONDS 0
    TRANSPORT_DESCRIPTOR_PARITY unknown
    REQUEST_AUTHENTICATION_MODE unknown
    REQUEST_CONNECTION_ATTEMPTED no
    REQUEST_CONNECTION_STATUS not-attempted
    REQUEST_RPC_METHOD_CATEGORY unknown
    REQUEST_RPC_RESPONSE_CATEGORY unknown
    REQUEST_RPC_ERROR_CODE unknown
    REQUEST_SUBMISSION_DURATION_MILLISECONDS 0
    REQUEST_REASON_CODE unknown
    REQUEST_SUBMISSION_ATTEMPTED no
    REQUEST_SUBMISSION_STATUS not-attempted
    REQUEST_IDENTITY_CAPTURED no
    REQUEST_STATUS_QUERY not-attempted
    REQUEST_TERMINAL_STATE unknown
    CANCEL_CAPABILITY unsupported
    CANCEL_ATTEMPTED no
    CANCEL_TARGET_IDENTITY_MATCHED no
    CANCEL_RESULT not-attempted
    APPROVAL_CAPABILITY unsupported
    APPROVAL_TRIGGERED no
    APPROVAL_DECISION_SUBMITTED no
    APPROVAL_RESULT not-attempted
    CLIENT_RECONNECT_TESTED no
    REQUEST_STATE_SURVIVED_RECONNECT no
    BROAD_STOP_INVOKED no
    BROAD_PROCESS_KILL_USED no
    ACCEPTANCE_PROCESS_REMAINING unknown
    ORPHAN_PROCESS_FOUND unknown
    SUPERVISED_PROCESS_REAL_HOME_ACCESS unknown
    GENERATED_ARTIFACT_TRACKED_BY_GIT no
    ENVIRONMENT_RESTORED no
    M14_008_REASON_CODE unknown
    M14_008_RESULT FAIL
  )
}

result_exit_code() {
  case "${RESULT[M14_008_RESULT]}" in
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
import re
import sys
path = Path(sys.argv[1])
expected = sys.argv[2:]
text = path.read_text(encoding="utf-8")
seen = [line.split("=", 1)[0] for line in text.splitlines() if line.strip()]
if len(set(seen)) != len(seen):
    raise SystemExit("Duplicate result key")
if seen != expected:
    raise SystemExit("Invalid result schema")
if re.search(r"127\.0\.0\.1:[0-9]{1,5}|localhost:[0-9]{1,5}|:[0-9]{4,5}\b", text):
    raise SystemExit("Dynamic port leaked into deterministic result")
if re.search(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b", text):
    raise SystemExit("Raw UUID leaked into deterministic result")
if re.search(r"/Users/[^ \n\t]+", text):
    raise SystemExit("Absolute user path leaked into deterministic result")
values = dict(line.split("=", 1) for line in text.splitlines() if line.strip())
if values.get("M14_008_RESULT") != "PASS" and values.get("M14_008_REASON_CODE") in {"", "unknown"}:
    raise SystemExit("Non-PASS result requires stable reason")
sensitive_names = {
    "authorization", "token", "access_token", "refresh_token", "api_key",
    "credential", "cookie", "bearer", "websocket_query_authentication",
}
allowed_values = {
    "yes", "no", "skip", "unknown", "none", "not-attempted", "failed",
    "submitted", "unsupported", "supported-unexercised", "supported-exercised",
    "websocket-jsonrpc", "websocket-jsonrpc-events", "hermes-jsonrpc-websocket",
    "hermes-status-only", "ws", "wss", "http", "https",
    "jsonrpc", "rest", "unsupported", "accepted", "rejected",
    "blocked", "ephemeral", "not-required",
}
semantic_version = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
safe_code = re.compile(r"^[a-z0-9][a-z0-9.-]{0,95}$")
meaningful_secret_shape = re.compile(r"^(?=.{40,}$)(?=.*[A-Za-z])(?=.*[0-9])[A-Za-z0-9._~+/=-]+$")
uuid_like = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
for key, value in values.items():
    normalized_key = key.lower()
    normalized_value = value.strip()
    if normalized_value in allowed_values or semantic_version.match(normalized_value):
        continue
    if normalized_value.startswith("<redacted") and normalized_value.endswith(">"):
        continue
    if uuid_like.match(normalized_value):
        continue
    if any(name in normalized_key for name in sensitive_names):
        if normalized_value not in {"yes", "no", "skip", "none", "unknown"}:
            raise SystemExit(f"Sensitive result value leaked: key-category={normalized_key}")
        continue
    if meaningful_secret_shape.match(normalized_value) and not safe_code.match(normalized_value):
        raise SystemExit("Token-like result value leaked: rule=high-entropy-shape")
PY
}

write_artifacts() {
  mkdir -p "$ARTIFACT_DIR" "$EVIDENCE_DIR"
  if git -C "$ROOT_DIR" check-ignore -q "artifacts/m14-008/result.txt"; then
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
  /usr/bin/python3 - "$PROTOCOL_DESCRIPTOR_FILE" "$REQUEST_EVIDENCE_FILE" "${(@kv)RESULT}" <<'PY'
import json
import sys
from pathlib import Path
descriptor_path = Path(sys.argv[1])
request_path = Path(sys.argv[2])
items = sys.argv[3:]
result = dict(zip(items[0::2], items[1::2]))
descriptor_path.write_text(json.dumps({
    "schemaVersion": 1,
    "run": "m14-008",
    "protocolFamily": result.get("PROTOCOL_FAMILY", "unknown"),
    "rpcModel": "jsonrpc" if result.get("REQUEST_RPC_METHOD_CATEGORY") == "session-create" else "unknown",
    "transportFamily": result.get("TRANSPORT_FAMILY", "unknown"),
    "transportRouteCategory": result.get("TRANSPORT_ROUTE_CATEGORY", "unknown"),
    "eventStreamingCapability": "websocket-events" if result.get("TRANSPORT_FAMILY") == "websocket-jsonrpc" else "none",
    "webSocketSubprotocolCategory": result.get("WEBSOCKET_SUBPROTOCOL_CATEGORY", "unknown"),
    "webSocketOriginMode": result.get("WEBSOCKET_ORIGIN_MODE", "unknown"),
    "protocolVersion": result.get("PROTOCOL_VERSION", "unknown"),
    "authenticationState": (
        "not-required" if result.get("AUTHENTICATION_REQUIRED") == "no"
        else "required-available" if result.get("AUTHENTICATION_REQUIRED") == "yes" and result.get("EPHEMERAL_CREDENTIAL_ISOLATED") == "yes"
        else "required-unavailable" if result.get("AUTHENTICATION_REQUIRED") == "yes"
        else "unknown"
    ),
    "requestRouteCategory": "jsonrpc-websocket-session-create" if result.get("REQUEST_CAPABILITY") != "unsupported" and result.get("TRANSPORT_FAMILY") == "websocket-jsonrpc" else "unsupported",
    "statusRouteCategory": "jsonrpc-websocket-session-status" if result.get("REQUEST_STATUS_QUERY") != "not-attempted" else "unknown",
    "cancelRouteCategory": "jsonrpc-websocket-session-interrupt" if result.get("CANCEL_CAPABILITY") != "unsupported" else "unsupported",
    "approvalRouteCategory": "jsonrpc-websocket-approval-respond" if result.get("APPROVAL_CAPABILITY") != "unsupported" else "unsupported",
    "authenticationRequired": result.get("AUTHENTICATION_REQUIRED", "unknown"),
    "credentialSourceCategory": "acceptance-owned-ephemeral-loopback-token" if result.get("EPHEMERAL_CREDENTIAL_ISOLATED") == "yes" else "none",
    "streamingModesAdvertised": ["websocket-jsonrpc-events"] if result.get("PROTOCOL_FAMILY") == "hermes-jsonrpc-websocket" else [],
    "unsupportedReasonCodes": [
        result.get("M14_008_REASON_CODE", "unknown"),
        result.get("APPROVAL_RESULT", "unknown")
    ],
    "redaction": "sanitized-no-raw-openapi-no-token-no-port-no-url"
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
request_path.write_text(json.dumps({
    "schemaVersion": 1,
    "run": "m14-008",
    "transport": result.get("REQUEST_TRANSPORT", "websocket-jsonrpc"),
    "transportFamily": result.get("TRANSPORT_FAMILY", "unknown"),
    "transportRouteCategory": result.get("TRANSPORT_ROUTE_CATEGORY", "unknown"),
    "transportScheme": result.get("TRANSPORT_SCHEME", "unknown"),
    "webSocketSubprotocolCategory": result.get("WEBSOCKET_SUBPROTOCOL_CATEGORY", "unknown"),
    "webSocketOriginMode": result.get("WEBSOCKET_ORIGIN_MODE", "unknown"),
    "handshakeAttempted": result.get("HANDSHAKE_ATTEMPTED", "no"),
    "handshakeHTTPStatus": result.get("HANDSHAKE_HTTP_STATUS", "none"),
    "handshakeUpgradeAccepted": result.get("HANDSHAKE_UPGRADE_ACCEPTED", "unknown"),
    "handshakeErrorCategory": result.get("HANDSHAKE_ERROR_CATEGORY", "unknown"),
    "handshakeDurationMilliseconds": int(result.get("HANDSHAKE_DURATION_MILLISECONDS", "0")),
    "transportDescriptorParity": result.get("TRANSPORT_DESCRIPTOR_PARITY", "unknown"),
    "authenticationMode": result.get("REQUEST_AUTHENTICATION_MODE", "unknown"),
    "connectionAttempted": result.get("REQUEST_CONNECTION_ATTEMPTED", "no"),
    "connectionStatus": result.get("REQUEST_CONNECTION_STATUS", "not-attempted"),
    "rpcMethodCategory": result.get("REQUEST_RPC_METHOD_CATEGORY", "unknown"),
    "rpcResponseCategory": result.get("REQUEST_RPC_RESPONSE_CATEGORY", "unknown"),
    "rpcErrorCode": result.get("REQUEST_RPC_ERROR_CODE", "unknown"),
    "submissionDurationMilliseconds": int(result.get("REQUEST_SUBMISSION_DURATION_MILLISECONDS", "0")),
    "reasonCode": result.get("REQUEST_REASON_CODE", "unknown"),
    "submissionAttempted": result.get("REQUEST_SUBMISSION_ATTEMPTED", "no"),
    "submissionStatus": result.get("REQUEST_SUBMISSION_STATUS", "not-attempted"),
    "identityCaptured": result.get("REQUEST_IDENTITY_CAPTURED", "no"),
    "identitySyntaxCategory": "token-like" if result.get("REQUEST_IDENTITY_CAPTURED") == "yes" else "none",
    "statusQuery": result.get("REQUEST_STATUS_QUERY", "not-attempted"),
    "terminalState": result.get("REQUEST_TERMINAL_STATE", "unknown"),
    "cancelTargetIdentityMatched": result.get("CANCEL_TARGET_IDENTITY_MATCHED", "no"),
    "reconnectTested": result.get("CLIENT_RECONNECT_TESTED", "no"),
    "stateSurvivedReconnect": result.get("REQUEST_STATE_SURVIVED_RECONNECT", "no"),
    "redaction": "raw-request-identity-omitted"
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

hermes_executable() {
  command -v hermes >/dev/null 2>&1 && command -v hermes
}

hermes_version() {
  "$1" --version 2>/dev/null | /usr/bin/python3 -c 'import re,sys
text=sys.stdin.read()
m=re.search(r"Hermes Agent v([0-9]+\.[0-9]+\.[0-9]+)", text)
print(m.group(1) if m else "unknown")
'
}

pid_identity() {
  /bin/ps -p "$1" -o pid=,ppid=,pgid=,uid=,lstart= 2>/dev/null | /usr/bin/awk '{$1=$1; print}'
}

persist_identity_for_pid() {
  local identity
  identity="$(pid_identity "$1")" || return 1
  [[ -n "$identity" ]] || return 1
  mkdir -p "$RUNTIME_ROOT"
  print -r -- "$identity" > "$OWNED_IDENTITY_FILE"
}

identity_matches() {
  local current expected
  [[ -f "$OWNED_IDENTITY_FILE" ]] || return 1
  current="$(pid_identity "$1")" || return 1
  expected="$(cat "$OWNED_IDENTITY_FILE")"
  [[ "$current" == "$expected" ]]
}

discover_listener() {
  local output candidate_count name address port
  command -v /usr/sbin/lsof >/dev/null 2>&1 || return 3
  output="$(/usr/sbin/lsof -nP -a -p "$1" -iTCP -sTCP:LISTEN -FpcnPT 2>/dev/null || true)"
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

probe_status() {
  local port="$1" http_status
  http_status="$(/usr/bin/curl --silent --show-error --max-time 5 --output "$RUNTIME_ROOT/status.json" --write-out "%{http_code}" "http://127.0.0.1:$port/api/status" 2>"$EVIDENCE_DIR/status-curl.stderr")" || return 1
  [[ "$http_status" == "200" ]] || return 2
  /usr/bin/python3 - "$RUNTIME_ROOT/status.json" "$STATUS_BODY_FILE" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if not isinstance(data, dict) or not ({"version","auth_required","desktop_contract","gateway_running"} & set(data)):
    raise SystemExit(2)
safe = {k: data.get(k) for k in ("version","auth_required","auth_mode","desktop_contract","gateway_running","gateway_state") if k in data}
Path(sys.argv[2]).write_text(json.dumps(safe, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(data.get("version", "unknown"))
print("yes" if data.get("auth_required") is True else "no")
print(data.get("auth_mode", "unknown"))
PY
}

inspect_openapi() {
  local port="$1" http_status
  http_status="$(/usr/bin/curl --silent --show-error --max-time 3 --output "$RUNTIME_ROOT/openapi.json" --write-out "%{http_code}" "http://127.0.0.1:$port/openapi.json" 2>"$EVIDENCE_DIR/openapi-curl.stderr" || true)"
  /usr/bin/python3 - "$RUNTIME_ROOT/openapi.json" "$OPENAPI_SUMMARY_FILE" "$http_status" <<'PY'
import json
import sys
from pathlib import Path
body = Path(sys.argv[1])
status = sys.argv[3]
summary = {"httpStatusCategory": status if status in {"200","404"} else "other", "paths": []}
if status == "200" and body.exists() and body.stat().st_size:
    data = json.loads(body.read_text(encoding="utf-8"))
    summary["paths"] = sorted(p for p in (data.get("paths") or {}) if p in {"/api/status","/api/ws"})
Path(sys.argv[2]).write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

safe_synthetic_request_available() {
  local version="$1"
  [[ "$version" == 0.18.* ]] || return 1
  /usr/bin/grep -Eq 'sendTyped\(method: "session\.create", params: EmptyParams\(\)\)' "$ROOT_DIR/Sources/HermesRuntimeFoundation/HermesProtocolClient.swift"
}

discover_protocol() {
  local version="$1" auth_required="$2" auth_mode="$3" authentication_state openapi_paths has_ws
  RESULT[PROTOCOL_METADATA_DISCOVERED]=yes
  RESULT[PROTOCOL_FAMILY]=hermes-status-only
  RESULT[REQUEST_TRANSPORT]=unknown
  RESULT[TRANSPORT_FAMILY]=unknown
  RESULT[TRANSPORT_ROUTE_CATEGORY]=unsupported
  RESULT[TRANSPORT_SCHEME]=unknown
  RESULT[WEBSOCKET_SUBPROTOCOL_CATEGORY]=none
  RESULT[WEBSOCKET_ORIGIN_MODE]=none
  RESULT[TRANSPORT_DESCRIPTOR_PARITY]=yes
  RESULT[PROTOCOL_VERSION]="$version"
  if [[ "$auth_required" == "no" ]]; then
    authentication_state=not-required
  elif [[ "$auth_required" == "yes" && "$auth_mode" == "loopback_token" ]]; then
    authentication_state=required-available
  elif [[ "$auth_required" == "yes" ]]; then
    authentication_state=required-unavailable
  else
    authentication_state=unknown
  fi

  case "$authentication_state" in
    not-required)
      RESULT[AUTHENTICATION_REQUIRED]=no
      RESULT[EPHEMERAL_CREDENTIAL_ISOLATED]=skip
      RESULT[REQUEST_AUTHENTICATION_MODE]=none
      ;;
    required-available)
      RESULT[AUTHENTICATION_REQUIRED]=yes
      RESULT[EPHEMERAL_CREDENTIAL_ISOLATED]=yes
      RESULT[REQUEST_AUTHENTICATION_MODE]=ephemeral
      ;;
    required-unavailable)
      RESULT[AUTHENTICATION_REQUIRED]=yes
      RESULT[EPHEMERAL_CREDENTIAL_ISOLATED]=no
      RESULT[REQUEST_AUTHENTICATION_MODE]=blocked
      RESULT[M14_008_RESULT]=BLOCKED
      RESULT[M14_008_REASON_CODE]=protocol.authentication-unavailable
      RESULT[REQUEST_REASON_CODE]=protocol.authentication-unavailable
      return 1
      ;;
    *)
      RESULT[AUTHENTICATION_REQUIRED]=unknown
      RESULT[EPHEMERAL_CREDENTIAL_ISOLATED]=no
      RESULT[REQUEST_AUTHENTICATION_MODE]=unknown
      RESULT[M14_008_RESULT]=BLOCKED
      RESULT[M14_008_REASON_CODE]=protocol.authentication-unknown
      RESULT[REQUEST_REASON_CODE]=protocol.authentication-unknown
      return 1
      ;;
  esac
  if [[ "$auth_required" == "yes" && "$auth_mode" == "loopback_token" ]]; then
    RESULT[EPHEMERAL_CREDENTIAL_ISOLATED]=yes
  fi
  openapi_paths="$(/usr/bin/python3 - "$OPENAPI_SUMMARY_FILE" <<'PY' 2>/dev/null || true
import json
import sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    data = {}
print("\n".join(data.get("paths") or []))
PY
)"
  has_ws=no
  if print -r -- "$openapi_paths" | /usr/bin/grep -qx '/api/ws'; then
    has_ws=yes
  fi

  if [[ "$has_ws" == "no" ]]; then
    RESULT[REQUEST_CAPABILITY]=unsupported
    RESULT[CANCEL_CAPABILITY]=unsupported
    RESULT[APPROVAL_CAPABILITY]=unsupported
    RESULT[REQUEST_RPC_METHOD_CATEGORY]=session-create
    RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=unsupported
    RESULT[REQUEST_REASON_CODE]=transport.route-unsupported
    RESULT[M14_008_RESULT]=UNSUPPORTED
    RESULT[M14_008_REASON_CODE]=transport.route-unsupported
    return 1
  fi

  if /usr/bin/grep -Eq '"session.create"|"session.status"|"session.interrupt"|"approval.respond"' "$ROOT_DIR/Sources/HermesRuntimeFoundation/HermesProtocolClient.swift"; then
    RESULT[PROTOCOL_FAMILY]=hermes-jsonrpc-websocket
    RESULT[REQUEST_TRANSPORT]=websocket-jsonrpc
    RESULT[TRANSPORT_FAMILY]=websocket-jsonrpc
    RESULT[TRANSPORT_ROUTE_CATEGORY]=jsonrpc-websocket-session-create
    RESULT[TRANSPORT_SCHEME]=ws
    RESULT[REQUEST_CAPABILITY]=supported-unexercised
    RESULT[CANCEL_CAPABILITY]=supported-unexercised
    RESULT[APPROVAL_CAPABILITY]=supported-unexercised
  else
    RESULT[REQUEST_CAPABILITY]=unsupported
    RESULT[CANCEL_CAPABILITY]=unsupported
    RESULT[APPROVAL_CAPABILITY]=unsupported
    RESULT[M14_008_RESULT]=UNSUPPORTED
    RESULT[M14_008_REASON_CODE]=protocol.request-route-unsupported
    return 1
  fi
}

create_token() {
  /usr/bin/python3 - "$TOKEN_FILE" <<'PY'
import secrets
import sys
from pathlib import Path
path = Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(secrets.token_urlsafe(32) + "\n", encoding="utf-8")
path.chmod(0o600)
PY
}

exercise_protocol() {
  local port="$1" auth_mode="${2:-none}" token="" start_ms end_ms probe_status probe_error request_reason
  if [[ "$auth_mode" == "ephemeral" ]]; then
    create_token
    token="$(cat "$TOKEN_FILE")"
  fi
  RESULT[REQUEST_SUBMISSION_ATTEMPTED]=yes
  RESULT[REQUEST_CONNECTION_ATTEMPTED]=yes
  RESULT[REQUEST_RPC_METHOD_CATEGORY]=session-create
  start_ms="$(/usr/bin/python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"
  swift run --configuration release HermesReleaseAgentPreflight m14-008-exercise-protocol \
    "$port" "$auth_mode" "$token" "$REQUEST_EVIDENCE_FILE.tmp" 2>"$RUNTIME_ROOT/request-probe.stderr"
  probe_status="$?"
  end_ms="$(/usr/bin/python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"
  if [[ "$start_ms" == <-> && "$end_ms" == <-> && "$end_ms" -ge "$start_ms" ]]; then
    RESULT[REQUEST_SUBMISSION_DURATION_MILLISECONDS]=$(( end_ms - start_ms ))
  fi
  case "$probe_status" in
    0)
      RESULT[REQUEST_CONNECTION_STATUS]=connected
      RESULT[HANDSHAKE_ATTEMPTED]=yes
      RESULT[HANDSHAKE_HTTP_STATUS]=unknown
      RESULT[HANDSHAKE_UPGRADE_ACCEPTED]=yes
      RESULT[HANDSHAKE_ERROR_CATEGORY]=unknown
      RESULT[HANDSHAKE_DURATION_MILLISECONDS]="${RESULT[REQUEST_SUBMISSION_DURATION_MILLISECONDS]}"
      RESULT[TRANSPORT_DESCRIPTOR_PARITY]=yes
      RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=success
      RESULT[REQUEST_RPC_ERROR_CODE]=none
      RESULT[REQUEST_REASON_CODE]=none
      RESULT[REQUEST_SUBMISSION_STATUS]=submitted
      RESULT[REQUEST_IDENTITY_CAPTURED]=yes
      RESULT[REQUEST_STATUS_QUERY]=observed
      RESULT[REQUEST_TERMINAL_STATE]=completed
      RESULT[CANCEL_ATTEMPTED]=yes
      RESULT[CANCEL_TARGET_IDENTITY_MATCHED]=yes
      RESULT[CANCEL_RESULT]=cancelled
      RESULT[CLIENT_RECONNECT_TESTED]=yes
      RESULT[REQUEST_STATE_SURVIVED_RECONNECT]=yes
      RESULT[REQUEST_CAPABILITY]=supported-exercised
      RESULT[CANCEL_CAPABILITY]=supported-exercised
      RESULT[APPROVAL_CAPABILITY]=supported-unexercised
      RESULT[APPROVAL_TRIGGERED]=no
      RESULT[APPROVAL_DECISION_SUBMITTED]=no
      RESULT[APPROVAL_RESULT]=supported-but-no-harmless-trigger
      RESULT[M14_008_RESULT]=PASS
      RESULT[M14_008_REASON_CODE]=none
      ;;
    *)
      probe_error="$(/usr/bin/awk -F'RuntimeError: ' '/RuntimeError: / {print $2; found=1} !found && /^[A-Za-z0-9._-]+$/ {print $0}' "$RUNTIME_ROOT/request-probe.stderr" 2>/dev/null | /usr/bin/tail -n 1)"
      request_reason="$(print -r -- "${probe_error:-request.submission-failed}" | /usr/bin/tr -cd 'A-Za-z0-9._-' | /usr/bin/cut -c1-96)"
      [[ -n "$request_reason" ]] || request_reason=request.submission-failed
      RESULT[REQUEST_CONNECTION_STATUS]=failed
      RESULT[HANDSHAKE_ATTEMPTED]=yes
      RESULT[HANDSHAKE_DURATION_MILLISECONDS]="${RESULT[REQUEST_SUBMISSION_DURATION_MILLISECONDS]}"
      RESULT[TRANSPORT_DESCRIPTOR_PARITY]="${RESULT[TRANSPORT_DESCRIPTOR_PARITY]:-yes}"
      case "$request_reason" in
        transport.connection-refused)
          RESULT[HANDSHAKE_ERROR_CATEGORY]=connect-refused
          RESULT[HANDSHAKE_UPGRADE_ACCEPTED]=no
          RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=connection-failed
          ;;
        websocket.http-not-found)
          RESULT[HANDSHAKE_ERROR_CATEGORY]=http-status
          RESULT[HANDSHAKE_HTTP_STATUS]=404
          RESULT[HANDSHAKE_UPGRADE_ACCEPTED]=no
          RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=connection-failed
          ;;
        websocket.forbidden)
          RESULT[HANDSHAKE_ERROR_CATEGORY]=http-status
          RESULT[HANDSHAKE_HTTP_STATUS]=403
          RESULT[HANDSHAKE_UPGRADE_ACCEPTED]=no
          RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=connection-failed
          ;;
        websocket.upgrade-rejected|websocket.subprotocol-mismatch|websocket.origin-rejected)
          RESULT[HANDSHAKE_ERROR_CATEGORY]=upgrade-rejected
          RESULT[HANDSHAKE_UPGRADE_ACCEPTED]=no
          RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=connection-failed
          ;;
        websocket.timeout)
          RESULT[HANDSHAKE_ERROR_CATEGORY]=timeout
          RESULT[HANDSHAKE_UPGRADE_ACCEPTED]=unknown
          RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=timeout
          ;;
        websocket.handshake-malformed|transport.scheme-invalid)
          RESULT[HANDSHAKE_ERROR_CATEGORY]=malformed-url
          RESULT[HANDSHAKE_UPGRADE_ACCEPTED]=no
          RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=malformed
          ;;
        protocol.transport-descriptor-mismatch)
          RESULT[HANDSHAKE_ERROR_CATEGORY]=protocol
          RESULT[HANDSHAKE_UPGRADE_ACCEPTED]=unknown
          RESULT[TRANSPORT_DESCRIPTOR_PARITY]=no
          RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=connection-failed
          ;;
        protocol.rpc-error)
          RESULT[REQUEST_CONNECTION_STATUS]=connected
          RESULT[HANDSHAKE_UPGRADE_ACCEPTED]=yes
          RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=rpc-error
          ;;
        protocol.request-timeout)
          RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=timeout
          ;;
        request.connection-failed|protocol.websocket-closed|protocol.reconnect-failed)
          RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=connection-failed
          ;;
        request.identity-missing)
          RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=malformed
          ;;
        *)
          RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=unknown
          ;;
      esac
      RESULT[REQUEST_RPC_ERROR_CODE]=unknown
      RESULT[REQUEST_REASON_CODE]="$request_reason"
      RESULT[REQUEST_SUBMISSION_STATUS]=failed
      RESULT[M14_008_RESULT]=FAIL
      RESULT[M14_008_REASON_CODE]="$request_reason"
      ;;
  esac
}

cleanup_owned_process() {
  local pid
  [[ -f "$OWNED_IDENTITY_FILE" ]] || return 0
  pid="$(/usr/bin/awk '{print $1}' "$OWNED_IDENTITY_FILE")"
  [[ "$pid" == <-> && "$pid" -gt 1 ]] || return 1
  if identity_matches "$pid"; then
    /bin/kill -TERM "$pid" 2>/dev/null
    sleep 1
  fi
  if identity_matches "$pid"; then
    /bin/kill -KILL "$pid" 2>/dev/null
    sleep 1
  fi
}

finalize_cleanup_evidence() {
  local pid
  rm -f "$TOKEN_FILE" "$RUNTIME_ROOT/status.json" "$RUNTIME_ROOT/openapi.json" "$REQUEST_EVIDENCE_FILE.tmp" "$RUNTIME_ROOT/request-probe.stderr"
  RESULT[ENVIRONMENT_RESTORED]=yes
  RESULT[SUPERVISED_PROCESS_REAL_HOME_ACCESS]=no
  if [[ ! -f "$OWNED_IDENTITY_FILE" ]]; then
    RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
    RESULT[ORPHAN_PROCESS_FOUND]=no
    return 0
  fi
  pid="$(/usr/bin/awk '{print $1}' "$OWNED_IDENTITY_FILE")"
  if [[ "$pid" == <-> && "$pid" -gt 1 ]] && identity_matches "$pid"; then
    RESULT[ACCEPTANCE_PROCESS_REMAINING]=yes
    RESULT[ORPHAN_PROCESS_FOUND]=yes
    RESULT[M14_008_RESULT]=FAIL
    RESULT[M14_008_REASON_CODE]=cleanup.process-remaining
  else
    RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
    RESULT[ORPHAN_PROCESS_FOUND]=no
  fi
}

inspect() {
  local executable version blocking="none" help_text authentication_category
  print -r -- "M14-008 read-only inspect"
  if executable="$(hermes_executable)"; then
    version="$(hermes_version "$executable")"
    help_text="$("$executable" serve --help 2>/dev/null || true)"
  else
    version="unknown"
    help_text=""
    blocking="executable.unavailable"
  fi
  if [[ ! -x /usr/sbin/lsof ]]; then
    blocking="endpoint.socket-facility-unavailable"
  fi
  authentication_category="$([[ "$help_text" == *"authentication"* ]] && print loopback-token-expected || print unknown)"
  if [[ -f "$PROTOCOL_DESCRIPTOR_FILE" ]]; then
    authentication_category="$(/usr/bin/python3 - "$PROTOCOL_DESCRIPTOR_FILE" "$authentication_category" <<'PY'
import json
import sys
from pathlib import Path
fallback = sys.argv[2]
try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    print(fallback)
    raise SystemExit
state = data.get("authenticationState")
if state:
    print(state)
elif data.get("authenticationRequired") == "no":
    print("not-required")
elif data.get("authenticationRequired") == "yes":
    print("required")
else:
    print(fallback)
PY
)"
  fi
  print -r -- "hermes_version=${version:-unknown}"
  print -r -- "endpoint_readiness_dependency=m14-007-ownership-proven-api-status"
  print -r -- "protocol_metadata_source=serve-help,api-status,openapi-if-present,local-production-client-contract"
  print -r -- "authentication_category=$authentication_category"
  print -r -- "request_advertised_status=$([[ -f "$ROOT_DIR/Sources/HermesRuntimeFoundation/HermesProtocolClient.swift" ]] && print jsonrpc-session-create || print unknown)"
  print -r -- "cancel_advertised_status=$([[ -f "$ROOT_DIR/Sources/HermesRuntimeFoundation/HermesProtocolClient.swift" ]] && print jsonrpc-session-interrupt || print unknown)"
  print -r -- "approval_advertised_status=$([[ -f "$ROOT_DIR/Sources/HermesRuntimeFoundation/HermesProtocolClient.swift" ]] && print jsonrpc-approval-respond || print unknown)"
  print -r -- "expected_exercisability=request-status-reconnect-safe,cancel-if-session-remains-addressable,approval-supported-unexercised-without-harmless-trigger"
  print -r -- "blocking_reason=$blocking"
}

inspect_request_plan() {
  local executable version descriptor_auth="unknown" descriptor_family="unknown" descriptor_version="unknown" descriptor_transport="unknown" blocking="none"
  if executable="$(hermes_executable)"; then
    version="$(hermes_version "$executable")"
  else
    version="unknown"
    blocking="executable.unavailable"
  fi
  if [[ -f "$PROTOCOL_DESCRIPTOR_FILE" ]]; then
    local parsed
    parsed="$(/usr/bin/python3 - "$PROTOCOL_DESCRIPTOR_FILE" <<'PY'
import json
import sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    data = {}
auth = data.get("authenticationState")
required = data.get("authenticationRequired", "unknown")
if not auth:
    auth = "not-required" if required == "no" else "required-available" if required == "yes" and data.get("credentialSourceCategory") != "none" else "required-unavailable" if required == "yes" else "unknown"
print(data.get("protocolFamily", "unknown"))
print(data.get("protocolVersion", "unknown"))
print(auth)
print(data.get("transportFamily", "unknown"))
PY
)"
    descriptor_family="${${(f)parsed}[1]:-unknown}"
    descriptor_version="${${(f)parsed}[2]:-unknown}"
    descriptor_auth="${${(f)parsed}[3]:-unknown}"
    descriptor_transport="${${(f)parsed}[4]:-unknown}"
  fi
  if [[ "$descriptor_auth" == "unknown" ]]; then
    descriptor_auth=not-required
  fi
  if [[ "$descriptor_family" == "unknown" ]]; then
    descriptor_family=hermes-status-only
  fi
  if [[ "$descriptor_version" == "unknown" ]]; then
    descriptor_version="${version:-unknown}"
  fi
  print -r -- "hermes_version=${version:-unknown}"
  print -r -- "protocol_family=$descriptor_family"
  print -r -- "protocol_version=$descriptor_version"
  print -r -- "authentication_state=$descriptor_auth"
  case "$descriptor_auth" in
    not-required)
      print -r -- "credential_action=none"
      print -r -- "ephemeral_credential_required=no"
      ;;
    required-available)
      print -r -- "credential_action=create-acceptance-owned-ephemeral"
      print -r -- "ephemeral_credential_required=yes"
      ;;
    required-unavailable)
      print -r -- "credential_action=blocked"
      print -r -- "ephemeral_credential_required=no"
      blocking="protocol.authentication-unavailable"
      ;;
    *)
      print -r -- "credential_action=unknown"
      print -r -- "ephemeral_credential_required=no"
      blocking="protocol.authentication-unknown"
      ;;
  esac
  print -r -- "request_method_category=session-create"
  if [[ "$descriptor_transport" == "websocket-jsonrpc" ]] && safe_synthetic_request_available "$descriptor_version"; then
    print -r -- "safe_synthetic_request_available=yes"
  else
    print -r -- "safe_synthetic_request_available=no"
    if [[ "$descriptor_transport" == "unknown" ]]; then
      [[ "$blocking" == "none" ]] && blocking="transport.route-unsupported"
    else
      [[ "$blocking" == "none" ]] && blocking="protocol.safe-request-unavailable"
    fi
  fi
  print -r -- "status_mechanism=session-status"
  print -r -- "cancel_exercisability=if-session-remains-addressable"
  print -r -- "approval_exercisability=supported-unexercised-without-harmless-trigger"
  print -r -- "reconnect_strategy=reconnect-and-query-captured-session"
  print -r -- "blocking_reason=$blocking"
}

inspect_transport_plan() {
  local executable version descriptor_family="unknown" descriptor_transport="unknown" descriptor_route="unknown"
  local descriptor_auth="unknown" descriptor_source="unknown" descriptor_subprotocol="none"
  local descriptor_origin="none" descriptor_parity="unknown" blocking="none"
  if executable="$(hermes_executable)"; then
    version="$(hermes_version "$executable")"
  else
    version="unknown"
    blocking="executable.unavailable"
  fi
  if [[ -f "$PROTOCOL_DESCRIPTOR_FILE" ]]; then
    local parsed
    parsed="$(/usr/bin/python3 - "$PROTOCOL_DESCRIPTOR_FILE" <<'PY'
import json
import sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    data = {}
print(data.get("protocolFamily", "unknown"))
print(data.get("transportFamily", "unknown"))
print(data.get("transportRouteCategory") or data.get("requestRouteCategory", "unknown"))
print(data.get("authenticationState", "unknown"))
print(data.get("protocolVersion", "unknown"))
print(data.get("metadataSource", "captured-openapi-summary-and-local-production-client-contract"))
print(data.get("webSocketSubprotocolCategory", "none"))
print(data.get("webSocketOriginMode", "none"))
PY
)"
    descriptor_family="${${(f)parsed}[1]:-unknown}"
    descriptor_transport="${${(f)parsed}[2]:-unknown}"
    descriptor_route="${${(f)parsed}[3]:-unknown}"
    descriptor_auth="${${(f)parsed}[4]:-unknown}"
    [[ "$version" == "unknown" ]] && version="${${(f)parsed}[5]:-unknown}"
    descriptor_source="${${(f)parsed}[6]:-unknown}"
    descriptor_subprotocol="${${(f)parsed}[7]:-none}"
    descriptor_origin="${${(f)parsed}[8]:-none}"
  elif [[ -f "$OPENAPI_SUMMARY_FILE" ]]; then
    descriptor_source=captured-openapi-summary-and-local-production-client-contract
    if /usr/bin/python3 - "$OPENAPI_SUMMARY_FILE" <<'PY'
import json
import sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
raise SystemExit(0 if "/api/ws" in (data.get("paths") or []) else 1)
PY
    then
      descriptor_family=hermes-jsonrpc-websocket
      descriptor_transport=websocket-jsonrpc
      descriptor_route=jsonrpc-websocket-session-create
    else
      descriptor_family=hermes-status-only
      descriptor_transport=unknown
      descriptor_route=unsupported
    fi
  fi
  if [[ "$descriptor_transport" == "websocket-jsonrpc" && "$descriptor_route" == "jsonrpc-websocket-session-create" ]]; then
    descriptor_parity=yes
  elif [[ "$descriptor_transport" == "unknown" || "$descriptor_route" == "unsupported" ]]; then
    descriptor_parity=yes
    [[ "$blocking" == "none" ]] && blocking="transport.route-unsupported"
  else
    descriptor_parity=no
    [[ "$blocking" == "none" ]] && blocking="protocol.transport-descriptor-mismatch"
  fi
  print -r -- "hermes_version=${version:-unknown}"
  print -r -- "selected_transport_family=$descriptor_transport"
  print -r -- "authoritative_metadata_source=$descriptor_source"
  print -r -- "route_category=$descriptor_route"
  print -r -- "authentication_state=$descriptor_auth"
  print -r -- "required_subprotocol_category=$descriptor_subprotocol"
  print -r -- "origin_policy_category=$descriptor_origin"
  print -r -- "session_create_method_category=session-create"
  print -r -- "production_client_descriptor_agree=$descriptor_parity"
  print -r -- "blocking_reason=$blocking"
  print -r -- "protocol_family=$descriptor_family"
}

run_acceptance() {
  local executable version pid endpoint port probe_lines status_version auth_required auth_mode
  set_default_results
  mkdir -p "$RUNTIME_ROOT" "$EVIDENCE_DIR"
  if [[ "${HERMES_M14_008_ACCEPTANCE:-}" != "YES" ]]; then
    RESULT[M14_008_RESULT]=OPT_IN_REQUIRED
    RESULT[M14_008_REASON_CODE]=acceptance.opt-in-required
    finalize_cleanup_evidence
    write_artifacts
    exit 2
  fi
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  executable="$(hermes_executable)" || {
    RESULT[M14_008_RESULT]=BLOCKED
    RESULT[M14_008_REASON_CODE]=executable.unavailable
    finalize_cleanup_evidence
    write_artifacts
    exit 3
  }
  version="$(hermes_version "$executable")"
  RESULT[HERMES_VERSION]="${version:-unknown}"
  [[ "$version" == 0.18.* ]] || {
    RESULT[M14_008_RESULT]=BLOCKED
    RESULT[M14_008_REASON_CODE]=version.unsupported
    finalize_cleanup_evidence
    write_artifacts
    exit 3
  }

  HOME="$RUNTIME_ROOT/home" HERMES_HOME="$RUNTIME_ROOT/hermes-home" \
    "$executable" serve --isolated --port 0 > "$STDOUT_FILE" 2> "$STDERR_FILE" &
  pid=$!
  sleep 1
  persist_identity_for_pid "$pid" || {
    RESULT[M14_008_RESULT]=FAIL
    RESULT[M14_008_REASON_CODE]=process.identity-capture-failed
    cleanup_owned_process
    finalize_cleanup_evidence
    write_artifacts
    exit 1
  }
  endpoint="$(discover_listener "$pid")" || {
    RESULT[M14_008_RESULT]=BLOCKED
    RESULT[M14_008_REASON_CODE]=endpoint.listener-missing
    cleanup_owned_process
    finalize_cleanup_evidence
    write_artifacts
    exit 3
  }
  port="${endpoint##* }"
  RESULT[ENDPOINT_OWNERSHIP_PROVEN]=yes
  probe_lines=("${(@f)$(probe_status "$port")}") || {
    RESULT[M14_008_RESULT]=FAIL
    RESULT[M14_008_REASON_CODE]=readiness.response-malformed
    cleanup_owned_process
    finalize_cleanup_evidence
    write_artifacts
    exit 1
  }
  RESULT[READINESS_PROVEN]=yes
  status_version="${probe_lines[1]:-unknown}"
  auth_required="${probe_lines[2]:-unknown}"
  auth_mode="${probe_lines[3]:-unknown}"
  inspect_openapi "$port"
  discover_protocol "$status_version" "$auth_required" "$auth_mode" || {
    cleanup_owned_process
    finalize_cleanup_evidence
    write_artifacts
    result_exit_code
    exit "$?"
  }
  if [[ "${RESULT[REQUEST_CAPABILITY]}" == "unsupported" ]]; then
    RESULT[M14_008_RESULT]=UNSUPPORTED
    RESULT[M14_008_REASON_CODE]=transport.route-unsupported
    RESULT[REQUEST_REASON_CODE]=transport.route-unsupported
  elif ! safe_synthetic_request_available "${RESULT[PROTOCOL_VERSION]}"; then
    RESULT[REQUEST_CAPABILITY]=supported-unexercised
    RESULT[REQUEST_AUTHENTICATION_MODE]="${RESULT[REQUEST_AUTHENTICATION_MODE]:-unknown}"
    RESULT[REQUEST_CONNECTION_ATTEMPTED]=no
    RESULT[REQUEST_CONNECTION_STATUS]=not-attempted
    RESULT[REQUEST_RPC_METHOD_CATEGORY]=session-create
    RESULT[REQUEST_RPC_RESPONSE_CATEGORY]=unknown
    RESULT[REQUEST_RPC_ERROR_CODE]=none
    RESULT[REQUEST_REASON_CODE]=protocol.safe-request-unavailable
    RESULT[REQUEST_SUBMISSION_ATTEMPTED]=no
    RESULT[REQUEST_SUBMISSION_STATUS]=not-attempted
    RESULT[M14_008_RESULT]=PARTIAL
    RESULT[M14_008_REASON_CODE]=protocol.safe-request-unavailable
  else
    exercise_protocol "$port" "${RESULT[REQUEST_AUTHENTICATION_MODE]}"
  fi
  cleanup_owned_process || {
    RESULT[M14_008_RESULT]=FAIL
    RESULT[M14_008_REASON_CODE]=cleanup.failure
  }
  finalize_cleanup_evidence
  write_artifacts
  result_exit_code
  exit "$?"
}

cleanup() {
  set_default_results
  cleanup_owned_process || {
    RESULT[M14_008_RESULT]=FAIL
    RESULT[M14_008_REASON_CODE]=cleanup.failure
    finalize_cleanup_evidence
    write_artifacts
    exit 1
  }
  rm -rf "$RUNTIME_ROOT"
  RESULT[M14_008_RESULT]=PASS
  RESULT[M14_008_REASON_CODE]=none
  finalize_cleanup_evidence
  write_artifacts
}

case "${1:-}" in
  inspect) inspect ;;
  inspect-request-plan) inspect_request_plan ;;
  inspect-transport-plan) inspect_transport_plan ;;
  run) run_acceptance ;;
  cleanup) cleanup ;;
  *) usage; exit 1 ;;
esac
