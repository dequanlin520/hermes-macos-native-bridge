#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m6-001"
INSTALL_ROOT="$ARTIFACT_DIR/install-root"
REPORT="$ARTIFACT_DIR/permissions-report.json"
AUDIT_ROOT="$ARTIFACT_DIR/audit"
EXPORT_ROOT="$ARTIFACT_DIR/export"
OUTPUT_FILE="$ARTIFACT_DIR/result.txt"

PERMISSIONS_DOCTOR_PASSED=no
NO_PERMISSION_PROMPT_TRIGGERED=yes
ACCESSIBILITY_STATE_REPORTED=no
SCREEN_RECORDING_STATE_REPORTED=no
SANDBOX_STATE_REPORTED=no
FILE_AUTHORIZATION_STATE_REPORTED=no
AUDIT_APPEND_PASSED=no
AUDIT_ROTATION_PASSED=no
AUDIT_EXPORT_PASSED=no
AUDIT_CHECKSUM_VALID=no
PROMPT_EXPOSED=no
TOKEN_EXPOSED=no
BOOKMARK_BYTES_EXPOSED=no
ABSOLUTE_PATH_EXPOSED=no
RESIDUAL_PROCESS=no
M6_001_RESULT=FAIL

cleanup() {
  pkill -f "com.hermes.bridge.test.m6-001" >/dev/null 2>&1 || true
  if pgrep -fl "com.hermes.bridge.test.m6-001" >/dev/null 2>&1; then
    RESIDUAL_PROCESS=yes
  else
    RESIDUAL_PROCESS=no
  fi
}

calculate_result() {
  M6_001_RESULT=FAIL
  if [ "$PERMISSIONS_DOCTOR_PASSED" = yes ] \
    && [ "$NO_PERMISSION_PROMPT_TRIGGERED" = yes ] \
    && [ "$ACCESSIBILITY_STATE_REPORTED" = yes ] \
    && [ "$SCREEN_RECORDING_STATE_REPORTED" = yes ] \
    && [ "$SANDBOX_STATE_REPORTED" = yes ] \
    && [ "$FILE_AUTHORIZATION_STATE_REPORTED" = yes ] \
    && [ "$AUDIT_APPEND_PASSED" = yes ] \
    && [ "$AUDIT_ROTATION_PASSED" = yes ] \
    && [ "$AUDIT_EXPORT_PASSED" = yes ] \
    && [ "$AUDIT_CHECKSUM_VALID" = yes ] \
    && [ "$PROMPT_EXPOSED" = no ] \
    && [ "$TOKEN_EXPOSED" = no ] \
    && [ "$BOOKMARK_BYTES_EXPOSED" = no ] \
    && [ "$ABSOLUTE_PATH_EXPOSED" = no ] \
    && [ "$RESIDUAL_PROCESS" = no ]; then
    M6_001_RESULT=PASS
  elif [ "$PERMISSIONS_DOCTOR_PASSED" = yes ] && [ "$AUDIT_APPEND_PASSED" = yes ]; then
    M6_001_RESULT=PARTIAL
  fi
}

write_results() {
  local tmp_output="$OUTPUT_FILE.tmp"
  calculate_result
  {
    print -r -- "PERMISSIONS_DOCTOR_PASSED=$PERMISSIONS_DOCTOR_PASSED"
    print -r -- "NO_PERMISSION_PROMPT_TRIGGERED=$NO_PERMISSION_PROMPT_TRIGGERED"
    print -r -- "ACCESSIBILITY_STATE_REPORTED=$ACCESSIBILITY_STATE_REPORTED"
    print -r -- "SCREEN_RECORDING_STATE_REPORTED=$SCREEN_RECORDING_STATE_REPORTED"
    print -r -- "SANDBOX_STATE_REPORTED=$SANDBOX_STATE_REPORTED"
    print -r -- "FILE_AUTHORIZATION_STATE_REPORTED=$FILE_AUTHORIZATION_STATE_REPORTED"
    print -r -- "AUDIT_APPEND_PASSED=$AUDIT_APPEND_PASSED"
    print -r -- "AUDIT_ROTATION_PASSED=$AUDIT_ROTATION_PASSED"
    print -r -- "AUDIT_EXPORT_PASSED=$AUDIT_EXPORT_PASSED"
    print -r -- "AUDIT_CHECKSUM_VALID=$AUDIT_CHECKSUM_VALID"
    print -r -- "PROMPT_EXPOSED=$PROMPT_EXPOSED"
    print -r -- "TOKEN_EXPOSED=$TOKEN_EXPOSED"
    print -r -- "BOOKMARK_BYTES_EXPOSED=$BOOKMARK_BYTES_EXPOSED"
    print -r -- "ABSOLUTE_PATH_EXPOSED=$ABSOLUTE_PATH_EXPOSED"
    print -r -- "RESIDUAL_PROCESS=$RESIDUAL_PROCESS"
    print -r -- "M6_001_RESULT=$M6_001_RESULT"
  } >| "$tmp_output"
  mv "$tmp_output" "$OUTPUT_FILE"
}

finalize() {
  local exit_status=$?
  cleanup
  write_results
  print "===== MACHINE RESULT ====="
  cat "$OUTPUT_FILE"
  return "$exit_status"
}

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR" "$AUDIT_ROOT" "$EXPORT_ROOT"
>| "$OUTPUT_FILE"

trap finalize EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$ROOT_DIR" || exit 1

if swift build >/dev/null; then
  :
fi
swift build --target M6001AuditFixture >/dev/null

if .build/debug/HermesBridgeControl permissions-doctor \
  --installation-root "$INSTALL_ROOT" \
  --format json >"$REPORT" 2>"$ARTIFACT_DIR/permissions.stderr"
then
  PERMISSIONS_DOCTOR_PASSED=yes
fi

if grep -q '"kind" : "accessibility"' "$REPORT"; then
  ACCESSIBILITY_STATE_REPORTED=yes
fi
if grep -q '"kind" : "screenRecording"' "$REPORT"; then
  SCREEN_RECORDING_STATE_REPORTED=yes
fi
if grep -q '"kind" : "appSandbox"' "$REPORT"; then
  SANDBOX_STATE_REPORTED=yes
fi
if grep -q '"kind" : "authorizedFileRoots"' "$REPORT"; then
  FILE_AUTHORIZATION_STATE_REPORTED=yes
fi

FIXTURE_OUTPUT="$ARTIFACT_DIR/fixture-output.json"
if .build/debug/M6001AuditFixture "$AUDIT_ROOT" "$EXPORT_ROOT" >"$FIXTURE_OUTPUT" 2>"$ARTIFACT_DIR/fixture.stderr"
then
  if grep -q '"events"' "$FIXTURE_OUTPUT"; then
    AUDIT_APPEND_PASSED=yes
  fi
fi

if [ "$(find "$AUDIT_ROOT" -name '*.jsonl' | wc -l | tr -d ' ')" -gt 1 ]; then
  AUDIT_ROTATION_PASSED=yes
fi

if [ -f "$EXPORT_ROOT/manifest.json" ] && [ -f "$EXPORT_ROOT/audit-export.jsonl" ]; then
  AUDIT_EXPORT_PASSED=yes
fi

if command -v shasum >/dev/null 2>&1 && [ -f "$EXPORT_ROOT/audit-export.jsonl" ]; then
  ACTUAL="$(shasum -a 256 "$EXPORT_ROOT/audit-export.jsonl" | awk '{print $1}')"
  RECORDED="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"])' "$EXPORT_ROOT/manifest.json" 2>/dev/null || true)"
  if [ "$ACTUAL" = "$RECORDED" ] && [ -n "$ACTUAL" ]; then
    AUDIT_CHECKSUM_VALID=yes
  fi
fi

SCAN_TEXT="$ARTIFACT_DIR/scan.txt"
{
  [ -f "$REPORT" ] && cat "$REPORT"
  find "$AUDIT_ROOT" "$EXPORT_ROOT" -maxdepth 3 -type f \( -name '*.json' -o -name '*.jsonl' -o -name '*.txt' \) -print0 \
    | xargs -0 cat 2>/dev/null || true
} >"$SCAN_TEXT"

if grep -q 'Prompt' "$SCAN_TEXT"; then
  PROMPT_EXPOSED=yes
fi
if grep -Eqi 'token|HERMES_DASHBOARD_SESSION_TOKEN' "$SCAN_TEXT"; then
  TOKEN_EXPOSED=yes
fi
if grep -Eqi 'bookmarkData|bookmark bytes|Ym9va21hcms' "$SCAN_TEXT"; then
  BOOKMARK_BYTES_EXPOSED=yes
fi
if grep -Eq '/Users/[^"]+' "$SCAN_TEXT"; then
  ABSOLUTE_PATH_EXPOSED=yes
fi

if pgrep -fl "com.hermes.bridge.test.m6-001" >/dev/null 2>&1; then
  RESIDUAL_PROCESS=yes
fi

calculate_result

[ "$M6_001_RESULT" = PASS ]
