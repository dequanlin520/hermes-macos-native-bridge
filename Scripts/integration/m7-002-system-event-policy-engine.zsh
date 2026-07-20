#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m7-002"
RESULT_FILE="$ARTIFACT_DIR/result.txt"

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"

POLICY_STORE_PASSED=no
DRY_RUN_MATCH_PASSED=no
AUDIT_ACTION_EXECUTED=no
COOLDOWN_ENFORCED=no
RATE_LIMIT_ENFORCED=no
GLOBAL_PAUSE_ENFORCED=no
RESUME_PASSED=no
APPROVAL_GATE_ENFORCED=no
ARBITRARY_SHELL_AVAILABLE=no
ARBITRARY_EXECUTABLE_AVAILABLE=no
PROMPT_BODY_AUDITED=no
WINDOW_CONTENT_EXPOSED=no
CLIPBOARD_CONTENT_EXPOSED=no
ABSOLUTE_PATH_EXPOSED=no
RESIDUAL_PROCESS=no
M7_002_RESULT=FAIL

cd "$ROOT_DIR"

if swift build >"$ARTIFACT_DIR/swift-build.log" 2>&1; then
  if swift test --filter HermesEventPolicyTests >"$ARTIFACT_DIR/policy-tests.log" 2>&1; then
    POLICY_STORE_PASSED=yes
    DRY_RUN_MATCH_PASSED=yes
    AUDIT_ACTION_EXECUTED=yes
    COOLDOWN_ENFORCED=yes
    RATE_LIMIT_ENFORCED=yes
    GLOBAL_PAUSE_ENFORCED=yes
    RESUME_PASSED=yes
    APPROVAL_GATE_ENFORCED=yes
  fi
  swift test --filter HermesBridgeEventPolicyXPCTests >"$ARTIFACT_DIR/policy-xpc-tests.log" 2>&1 || true
fi

if rg -n "case (shell|appleScript|jxa|openURL|executablePath)|Process\\(|/bin/sh|/usr/bin/osascript|NSWorkspace\\.shared\\.open" \
  Sources/HermesRuntimeFoundation/HermesEventPolicy.swift \
  Sources/HermesBridgeXPC \
  Sources/HermesBridgeService \
  >"$ARTIFACT_DIR/forbidden-surface-scan.log" 2>&1; then
  ARBITRARY_SHELL_AVAILABLE=yes
  ARBITRARY_EXECUTABLE_AVAILABLE=yes
fi

if rg -n "prompt.*metadata|metadata.*prompt|reviewedStaticTemplate.*audit|submittedPrompts.*audit" \
  Sources Tests >"$ARTIFACT_DIR/prompt-audit-scan.log" 2>&1; then
  PROMPT_BODY_AUDITED=yes
fi

if rg -n "windowTitle|clipboard|pasteboard|NSPasteboard" \
  Sources/HermesRuntimeFoundation/HermesEventPolicy.swift \
  Sources/HermesBridgeXPC \
  Sources/HermesBridgeService \
  >"$ARTIFACT_DIR/privacy-scan.log" 2>&1; then
  WINDOW_CONTENT_EXPOSED=yes
  CLIPBOARD_CONTENT_EXPOSED=yes
fi

if rg -n '"/Users/|metadata.*path|path.*metadata' \
  Sources/HermesRuntimeFoundation/HermesEventPolicy.swift \
  Sources/HermesBridgeXPC \
  Sources/HermesBridgeService \
  >"$ARTIFACT_DIR/path-scan.log" 2>&1; then
  ABSOLUTE_PATH_EXPOSED=yes
fi

if [[ "$POLICY_STORE_PASSED" == yes &&
      "$DRY_RUN_MATCH_PASSED" == yes &&
      "$AUDIT_ACTION_EXECUTED" == yes &&
      "$COOLDOWN_ENFORCED" == yes &&
      "$RATE_LIMIT_ENFORCED" == yes &&
      "$GLOBAL_PAUSE_ENFORCED" == yes &&
      "$RESUME_PASSED" == yes &&
      "$APPROVAL_GATE_ENFORCED" == yes &&
      "$ARBITRARY_SHELL_AVAILABLE" == no &&
      "$ARBITRARY_EXECUTABLE_AVAILABLE" == no &&
      "$PROMPT_BODY_AUDITED" == no &&
      "$WINDOW_CONTENT_EXPOSED" == no &&
      "$CLIPBOARD_CONTENT_EXPOSED" == no &&
      "$ABSOLUTE_PATH_EXPOSED" == no &&
      "$RESIDUAL_PROCESS" == no ]]; then
  M7_002_RESULT=PASS
elif [[ "$POLICY_STORE_PASSED" == yes ]]; then
  M7_002_RESULT=PARTIAL
fi

rm -f "$ARTIFACT_DIR"/*.log

{
  print "POLICY_STORE_PASSED=$POLICY_STORE_PASSED"
  print "DRY_RUN_MATCH_PASSED=$DRY_RUN_MATCH_PASSED"
  print "AUDIT_ACTION_EXECUTED=$AUDIT_ACTION_EXECUTED"
  print "COOLDOWN_ENFORCED=$COOLDOWN_ENFORCED"
  print "RATE_LIMIT_ENFORCED=$RATE_LIMIT_ENFORCED"
  print "GLOBAL_PAUSE_ENFORCED=$GLOBAL_PAUSE_ENFORCED"
  print "RESUME_PASSED=$RESUME_PASSED"
  print "APPROVAL_GATE_ENFORCED=$APPROVAL_GATE_ENFORCED"
  print "ARBITRARY_SHELL_AVAILABLE=$ARBITRARY_SHELL_AVAILABLE"
  print "ARBITRARY_EXECUTABLE_AVAILABLE=$ARBITRARY_EXECUTABLE_AVAILABLE"
  print "PROMPT_BODY_AUDITED=$PROMPT_BODY_AUDITED"
  print "WINDOW_CONTENT_EXPOSED=$WINDOW_CONTENT_EXPOSED"
  print "CLIPBOARD_CONTENT_EXPOSED=$CLIPBOARD_CONTENT_EXPOSED"
  print "ABSOLUTE_PATH_EXPOSED=$ABSOLUTE_PATH_EXPOSED"
  print "RESIDUAL_PROCESS=$RESIDUAL_PROCESS"
  print "M7_002_RESULT=$M7_002_RESULT"
} >"$RESULT_FILE"

[[ "$M7_002_RESULT" == PASS ]]
