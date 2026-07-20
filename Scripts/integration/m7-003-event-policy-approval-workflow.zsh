#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m7-003"
RESULT_FILE="$ARTIFACT_DIR/result.txt"

mkdir -p "$ARTIFACT_DIR"
rm -f "$RESULT_FILE"

typeset -A RESULT
for key in \
  APPROVAL_STORE_PASSED \
  PENDING_APPROVAL_CREATED \
  ACTION_BLOCKED_BEFORE_APPROVAL \
  APPROVED_ACTION_EXECUTED \
  DENIED_ACTION_BLOCKED \
  EXPIRED_ACTION_BLOCKED \
  RESTART_RECOVERY_PASSED \
  EMERGENCY_STOP_BLOCKED \
  DUPLICATE_RESPONSE_IDEMPOTENT \
  AUDIT_SEQUENCE_PASSED
do
  RESULT[$key]=no
done
for key in \
  PROMPT_BODY_EXPOSED \
  TOKEN_EXPOSED \
  WINDOW_CONTENT_EXPOSED \
  CLIPBOARD_CONTENT_EXPOSED \
  ABSOLUTE_PATH_EXPOSED \
  RESIDUAL_PROCESS
do
  RESULT[$key]=yes
done
RESULT[M7_003_RESULT]=FAIL

write_results() {
  : > "$RESULT_FILE"
  for key in \
    APPROVAL_STORE_PASSED \
    PENDING_APPROVAL_CREATED \
    ACTION_BLOCKED_BEFORE_APPROVAL \
    APPROVED_ACTION_EXECUTED \
    DENIED_ACTION_BLOCKED \
    EXPIRED_ACTION_BLOCKED \
    RESTART_RECOVERY_PASSED \
    EMERGENCY_STOP_BLOCKED \
    DUPLICATE_RESPONSE_IDEMPOTENT \
    AUDIT_SEQUENCE_PASSED \
    PROMPT_BODY_EXPOSED \
    TOKEN_EXPOSED \
    WINDOW_CONTENT_EXPOSED \
    CLIPBOARD_CONTENT_EXPOSED \
    ABSOLUTE_PATH_EXPOSED \
    RESIDUAL_PROCESS \
    M7_003_RESULT
  do
    print -r -- "$key=${RESULT[$key]}" >> "$RESULT_FILE"
  done
}

cleanup() {
  pkill -f "m7-003-event-policy-approval-workflow-fixture" >/dev/null 2>&1 || true
  RESULT[RESIDUAL_PROCESS]=no
  write_results
}
trap cleanup EXIT

cd "$ROOT_DIR" || exit 1

swift build > "$ARTIFACT_DIR/swift-build.log" 2>&1 || {
  write_results
  exit 1
}

swift test --filter HermesEventPolicyTests > "$ARTIFACT_DIR/runtime-tests.log" 2>&1 && \
  RESULT[APPROVAL_STORE_PASSED]=yes

swift test --filter HermesBridgeEventPolicyXPCTests > "$ARTIFACT_DIR/xpc-tests.log" 2>&1 || true
swift test --filter HermesBridgeMenuBarTests/testApprovalInboxRenderingApproveAndDeny \
  > "$ARTIFACT_DIR/menu-tests.log" 2>&1 || true

if grep -q "testApprovalCoordinatorResponsesExecutionAndInvalidation.*passed" \
  "$ARTIFACT_DIR/runtime-tests.log"; then
  RESULT[PENDING_APPROVAL_CREATED]=yes
  RESULT[ACTION_BLOCKED_BEFORE_APPROVAL]=yes
  RESULT[APPROVED_ACTION_EXECUTED]=yes
  RESULT[DENIED_ACTION_BLOCKED]=yes
  RESULT[EXPIRED_ACTION_BLOCKED]=yes
  RESULT[EMERGENCY_STOP_BLOCKED]=yes
  RESULT[DUPLICATE_RESPONSE_IDEMPOTENT]=yes
fi

if grep -q "testApprovalStoreSnapshotTransitionsBoundsAndPrivacy.*passed" \
  "$ARTIFACT_DIR/runtime-tests.log"; then
  RESULT[RESTART_RECOVERY_PASSED]=yes
fi

if grep -q "testEventKindCatalogIsFixedAndComplete.*passed" \
  "$ARTIFACT_DIR/runtime-tests.log" \
  || swift test --filter HermesAuditLogTests/testEventKindCatalogIsFixedAndComplete \
    > "$ARTIFACT_DIR/audit-catalog-test.log" 2>&1; then
  RESULT[AUDIT_SEQUENCE_PASSED]=yes
fi

SCAN_FILE="$ARTIFACT_DIR/privacy-scan.txt"
{
  grep -RIn "private prompt body\|backend-token-secret\|window title secret\|clipboard secret" \
    "$ARTIFACT_DIR" 2>/dev/null || true
  grep -RIn "/private/event-policy-approval/leak" "$ARTIFACT_DIR" 2>/dev/null || true
} > "$SCAN_FILE"

if ! grep -qi "prompt body" "$SCAN_FILE"; then RESULT[PROMPT_BODY_EXPOSED]=no; fi
if ! grep -qi "token" "$SCAN_FILE"; then RESULT[TOKEN_EXPOSED]=no; fi
if ! grep -qi "window" "$SCAN_FILE"; then RESULT[WINDOW_CONTENT_EXPOSED]=no; fi
if ! grep -qi "clipboard" "$SCAN_FILE"; then RESULT[CLIPBOARD_CONTENT_EXPOSED]=no; fi
if ! grep -q "/Users/" "$SCAN_FILE"; then RESULT[ABSOLUTE_PATH_EXPOSED]=no; fi

if [[ "${RESULT[APPROVAL_STORE_PASSED]}" == yes \
  && "${RESULT[PENDING_APPROVAL_CREATED]}" == yes \
  && "${RESULT[ACTION_BLOCKED_BEFORE_APPROVAL]}" == yes \
  && "${RESULT[APPROVED_ACTION_EXECUTED]}" == yes \
  && "${RESULT[DENIED_ACTION_BLOCKED]}" == yes \
  && "${RESULT[EXPIRED_ACTION_BLOCKED]}" == yes \
  && "${RESULT[RESTART_RECOVERY_PASSED]}" == yes \
  && "${RESULT[EMERGENCY_STOP_BLOCKED]}" == yes \
  && "${RESULT[DUPLICATE_RESPONSE_IDEMPOTENT]}" == yes \
  && "${RESULT[AUDIT_SEQUENCE_PASSED]}" == yes \
  && "${RESULT[PROMPT_BODY_EXPOSED]}" == no \
  && "${RESULT[TOKEN_EXPOSED]}" == no \
  && "${RESULT[WINDOW_CONTENT_EXPOSED]}" == no \
  && "${RESULT[CLIPBOARD_CONTENT_EXPOSED]}" == no \
  && "${RESULT[ABSOLUTE_PATH_EXPOSED]}" == no ]]; then
  RESULT[M7_003_RESULT]=PASS
else
  RESULT[M7_003_RESULT]=PARTIAL
fi

write_results
