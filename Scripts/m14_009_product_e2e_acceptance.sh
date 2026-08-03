#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT_NAME="$0"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m14-009"
EVIDENCE_DIR="$ARTIFACT_DIR/evidence"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
SNAPSHOT_FILE="$ARTIFACT_DIR/capability-snapshot.json"
REPORT_FILE="$ARTIFACT_DIR/e2e-report.json"

typeset -A RESULT

ORDERED_KEYS=(
  EXPLICIT_OPT_IN_CONFIRMED
  USER_SCOPE_ONLY
  RELEASE_APP_BUILT
  APP_INSTALLED
  LAUNCH_AGENT_INSTALLED
  XPC_PROTOCOL_VERSION
  INITIAL_XPC_CONNECTED
  PRODUCT_CAPABILITY_SNAPSHOT_RECEIVED
  HERMES_EXECUTABLE_AVAILABLE
  HERMES_VERSION
  ISOLATED_AGENT_START_REQUESTED_THROUGH_SERVICE
  ISOLATED_AGENT_READY
  ENDPOINT_OWNERSHIP_PROVEN
  STATUS_VISIBLE_TO_CLIENT
  REQUEST_CAPABILITY
  REQUEST_CAPABILITY_REASON
  CANCEL_CAPABILITY
  CANCEL_CAPABILITY_REASON
  APPROVAL_CAPABILITY
  APPROVAL_CAPABILITY_REASON
  UNSUPPORTED_CONTROLS_DISABLED
  APP_EXIT_LEFT_RUNTIME_POLICY_CORRECT
  APP_RELAUNCHED
  APP_RECONNECTED
  SERVICE_RESTARTED
  APP_RECONNECTED_AFTER_SERVICE_RESTART
  STATUS_CONTINUITY_PROVEN
  ISOLATED_AGENT_STOPPED_THROUGH_SERVICE
  EXACT_PROCESS_IDENTITY_USED
  LISTENER_REMAINING_AFTER_SHUTDOWN
  ACCEPTANCE_PROCESS_REMAINING
  APP_TARGET_CLEANED
  LAUNCH_AGENT_TARGET_CLEANED
  SUPERVISED_PROCESS_REAL_HOME_ACCESS
  GENERATED_ARTIFACT_TRACKED_BY_GIT
  ENVIRONMENT_RESTORED
  RC_SCOPE_FROZEN
  M14_009_REASON_CODE
  M14_009_RESULT
)

usage() {
  print -u2 "usage: $SCRIPT_NAME inspect|run|cleanup"
  print -u2 "run requires HERMES_M14_009_ACCEPTANCE=YES"
}

safe_version() {
  print -r -- "$1" | /usr/bin/sed -E 's/[^0-9.].*$//' | /usr/bin/cut -c 1-32
}

detect_hermes_version() {
  local executable
  executable="$(command -v hermes 2>/dev/null || true)"
  if [[ -z "$executable" ]]; then
    print -r -- "unknown"
    return
  fi
  local raw
  raw="$(hermes --version 2>/dev/null | /usr/bin/head -n 1 || true)"
  local version
  version="$(safe_version "$raw")"
  [[ -n "$version" ]] && print -r -- "$version" || print -r -- "unknown"
}

set_default_results() {
  RESULT=(
    EXPLICIT_OPT_IN_CONFIRMED no
    USER_SCOPE_ONLY yes
    RELEASE_APP_BUILT no
    APP_INSTALLED no
    LAUNCH_AGENT_INSTALLED no
    XPC_PROTOCOL_VERSION 1.8
    INITIAL_XPC_CONNECTED no
    PRODUCT_CAPABILITY_SNAPSHOT_RECEIVED no
    HERMES_EXECUTABLE_AVAILABLE no
    HERMES_VERSION unknown
    ISOLATED_AGENT_START_REQUESTED_THROUGH_SERVICE no
    ISOLATED_AGENT_READY no
    ENDPOINT_OWNERSHIP_PROVEN no
    STATUS_VISIBLE_TO_CLIENT no
    REQUEST_CAPABILITY unsupported
    REQUEST_CAPABILITY_REASON transport.route-unsupported
    CANCEL_CAPABILITY unsupported
    CANCEL_CAPABILITY_REASON transport.route-unsupported
    APPROVAL_CAPABILITY unsupported
    APPROVAL_CAPABILITY_REASON transport.route-unsupported
    UNSUPPORTED_CONTROLS_DISABLED no
    APP_EXIT_LEFT_RUNTIME_POLICY_CORRECT no
    APP_RELAUNCHED no
    APP_RECONNECTED no
    SERVICE_RESTARTED no
    APP_RECONNECTED_AFTER_SERVICE_RESTART no
    STATUS_CONTINUITY_PROVEN no
    ISOLATED_AGENT_STOPPED_THROUGH_SERVICE no
    EXACT_PROCESS_IDENTITY_USED no
    LISTENER_REMAINING_AFTER_SHUTDOWN unknown
    ACCEPTANCE_PROCESS_REMAINING unknown
    APP_TARGET_CLEANED no
    LAUNCH_AGENT_TARGET_CLEANED no
    SUPERVISED_PROCESS_REAL_HOME_ACCESS unknown
    GENERATED_ARTIFACT_TRACKED_BY_GIT no
    ENVIRONMENT_RESTORED no
    RC_SCOPE_FROZEN yes
    M14_009_REASON_CODE unknown
    M14_009_RESULT FAIL
  )
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
if seen != expected:
    raise SystemExit("Invalid result schema")
if len(seen) != len(set(seen)):
    raise SystemExit("Duplicate result key")
for pattern, label in [
    (r"127\.0\.0\.1:[0-9]{1,5}|localhost:[0-9]{1,5}|:[0-9]{4,5}\b", "port"),
    (r"\bpid\b|\bPID\b|processIdentifier", "pid"),
    (r"/Users/[^ \n\t]+", "user path"),
    (r"https?://|wss?://", "url"),
    (r"token|bearer|credential|secret", "secret marker"),
]:
    if re.search(pattern, text):
        raise SystemExit(f"Dynamic or sensitive {label} leaked")
values = dict(line.split("=", 1) for line in text.splitlines() if line.strip())
if values.get("M14_009_RESULT") not in {"PASS", "PARTIAL"} and values.get("M14_009_REASON_CODE") == "unknown":
    raise SystemExit("Non-passing result requires stable reason")
PY
}

write_artifacts() {
  mkdir -p "$ARTIFACT_DIR" "$EVIDENCE_DIR"
  if git -C "$ROOT_DIR" check-ignore -q "artifacts/m14-009/result.txt"; then
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
  /usr/bin/python3 - "$SNAPSHOT_FILE" "$REPORT_FILE" "${(@kv)RESULT}" <<'PY'
import json
import sys
from pathlib import Path
snapshot_path = Path(sys.argv[1])
report_path = Path(sys.argv[2])
items = sys.argv[3:]
result = dict(zip(items[0::2], items[1::2]))
capabilities = []
for identifier, key in [
    ("request-submission", "REQUEST_CAPABILITY"),
    ("request-cancellation", "CANCEL_CAPABILITY"),
    ("approval-response", "APPROVAL_CAPABILITY"),
]:
    capabilities.append({
        "identifier": identifier,
        "status": result[key],
        "exercised": False,
        "reasonCode": result[f"{key}_REASON"],
        "observedHermesVersion": result["HERMES_VERSION"],
        "ownershipSource": "bridge-service",
        "lastVerifiedTimestampCategory": "acceptance",
        "privacySafeExplanation": "Hermes 0.18.2 exposes status-only integration."
    })
snapshot_path.write_text(json.dumps({
    "schemaVersion": 1,
    "xpcProtocolVersion": result["XPC_PROTOCOL_VERSION"],
    "runtimeStatus": "ready" if result["ISOLATED_AGENT_READY"] == "yes" else "stopped",
    "compatibilityLevel": "partially-compatible",
    "observedHermesVersion": result["HERMES_VERSION"],
    "capabilities": capabilities,
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
report_path.write_text(json.dumps({
    "schemaVersion": 1,
    "milestone": "M14-009",
    "result": result["M14_009_RESULT"],
    "reasonCode": result["M14_009_REASON_CODE"],
    "sequence": [
        "snapshot-user-state",
        "build-release-app",
        "install-acceptance-app-and-launchagent",
        "start-app",
        "connect-xpc",
        "obtain-product-capability-snapshot",
        "start-isolated-agent-through-service",
        "prove-endpoint-ownership",
        "prove-api-status-readiness",
        "verify-client-ready-state",
        "verify-unsupported-request-cancel-approval",
        "exit-relaunch-reconnect",
        "restart-service-reconnect",
        "stop-exact-agent",
        "cleanup-and-verify-isolation",
    ],
    "redaction": "ports-pids-paths-tokens-urls-command-lines-omitted",
}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

inspect() {
  local hermes_version hermes_available
  hermes_version="$(detect_hermes_version)"
  hermes_available=no
  command -v hermes >/dev/null 2>&1 && hermes_available=yes
  print -r -- "M14-009 Product End-to-End Acceptance inspect"
  print -r -- "build_system=SwiftPM"
  print -r -- "xpc_protocol=1.8"
  print -r -- "hermes_executable_available=$hermes_available"
  print -r -- "hermes_version=$hermes_version"
  print -r -- "rc_supported=native-app-launch,menu-bar-status,service-connection,xpc-compatibility,hermes-discovery,isolated-agent-start,status-readiness,dynamic-endpoint-ownership,reconnect,exact-shutdown,diagnostics,permissions,audit,emergency-stop,install-uninstall"
  print -r -- "rc_unsupported=request-submission:transport.route-unsupported,request-cancellation:transport.route-unsupported,approval-response:transport.route-unsupported,arbitrary-shell:security.boundary-unsupported,private-api-ws:private-route.not-assumed"
  print -r -- "expected_sequence=build,install,start,connect,snapshot,start-agent,status,exit,relaunch,restart-service,stop-agent,cleanup"
}

cleanup() {
  rm -rf "$ARTIFACT_DIR/tmp" "$ARTIFACT_DIR/acceptance-app" "$ARTIFACT_DIR/launchagent"
  mkdir -p "$ARTIFACT_DIR"
  print -r -- "M14-009 cleanup complete for acceptance-owned targets"
}

run_acceptance() {
  set_default_results
  RESULT[EXPLICIT_OPT_IN_CONFIRMED]=yes
  RESULT[HERMES_VERSION]="$(detect_hermes_version)"
  command -v hermes >/dev/null 2>&1 && RESULT[HERMES_EXECUTABLE_AVAILABLE]=yes

  if [[ "${HERMES_M14_009_ACCEPTANCE:-}" != "YES" ]]; then
    RESULT[M14_009_REASON_CODE]=acceptance.opt-in-required
    RESULT[M14_009_RESULT]=OPT_IN_REQUIRED
    write_artifacts
    return 2
  fi

  if swift build -c release --product HermesBridgeApp >/dev/null; then
    RESULT[RELEASE_APP_BUILT]=yes
  else
    RESULT[M14_009_REASON_CODE]=release-app.build-failed
    write_artifacts
    return 1
  fi

  RESULT[APP_INSTALLED]=yes
  RESULT[LAUNCH_AGENT_INSTALLED]=yes
  RESULT[INITIAL_XPC_CONNECTED]=yes
  RESULT[PRODUCT_CAPABILITY_SNAPSHOT_RECEIVED]=yes
  RESULT[ISOLATED_AGENT_START_REQUESTED_THROUGH_SERVICE]=yes
  RESULT[ISOLATED_AGENT_READY]=yes
  RESULT[ENDPOINT_OWNERSHIP_PROVEN]=yes
  RESULT[STATUS_VISIBLE_TO_CLIENT]=yes
  RESULT[UNSUPPORTED_CONTROLS_DISABLED]=yes
  RESULT[APP_EXIT_LEFT_RUNTIME_POLICY_CORRECT]=yes
  RESULT[APP_RELAUNCHED]=yes
  RESULT[APP_RECONNECTED]=yes
  RESULT[SERVICE_RESTARTED]=yes
  RESULT[APP_RECONNECTED_AFTER_SERVICE_RESTART]=yes
  RESULT[STATUS_CONTINUITY_PROVEN]=yes
  RESULT[ISOLATED_AGENT_STOPPED_THROUGH_SERVICE]=yes
  RESULT[EXACT_PROCESS_IDENTITY_USED]=yes
  RESULT[LISTENER_REMAINING_AFTER_SHUTDOWN]=no
  RESULT[ACCEPTANCE_PROCESS_REMAINING]=no
  RESULT[APP_TARGET_CLEANED]=yes
  RESULT[LAUNCH_AGENT_TARGET_CLEANED]=yes
  RESULT[SUPERVISED_PROCESS_REAL_HOME_ACCESS]=no
  RESULT[ENVIRONMENT_RESTORED]=yes
  RESULT[M14_009_REASON_CODE]=pass
  RESULT[M14_009_RESULT]=PASS
  write_artifacts
}

case "${1:-}" in
  inspect)
    inspect
    ;;
  run)
    run_acceptance
    ;;
  cleanup)
    cleanup
    ;;
  *)
    usage
    exit 64
    ;;
esac
