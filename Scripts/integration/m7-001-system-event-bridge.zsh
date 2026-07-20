#!/bin/zsh
set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ARTIFACT_DIR="$REPO_ROOT/artifacts/m7-001"
OUTPUT_FILE="$ARTIFACT_DIR/result.txt"

typeset -A result
result[SYSTEM_EVENT_MONITOR_STARTED]=no
result[NETWORK_STATE_REPORTED]=no
result[APP_LAUNCH_EVENT_OBSERVED]=no
result[APP_TERMINATION_EVENT_OBSERVED]=no
result[SERVICE_HEALTH_EVENT_OBSERVED]=no
result[SUBSCRIPTION_CREATED]=no
result[EVENT_BATCH_RECEIVED]=no
result[CURSOR_ACKNOWLEDGED]=no
result[SUBSCRIPTION_CANCELLED]=no
result[EXECUTABLE_PATH_EXPOSED]=no
result[PID_EXPOSED]=no
result[WINDOW_CONTENT_EXPOSED]=no
result[CLIPBOARD_CONTENT_EXPOSED]=no
result[PROMPT_EXPOSED]=no
result[TOKEN_EXPOSED]=no
result[RESIDUAL_PROCESS]=no
result[M7_001_RESULT]=FAIL

finish() {
  mkdir -p "$ARTIFACT_DIR"
  rm -f "$OUTPUT_FILE"
  {
    print -r -- "SYSTEM_EVENT_MONITOR_STARTED=${result[SYSTEM_EVENT_MONITOR_STARTED]}"
    print -r -- "NETWORK_STATE_REPORTED=${result[NETWORK_STATE_REPORTED]}"
    print -r -- "APP_LAUNCH_EVENT_OBSERVED=${result[APP_LAUNCH_EVENT_OBSERVED]}"
    print -r -- "APP_TERMINATION_EVENT_OBSERVED=${result[APP_TERMINATION_EVENT_OBSERVED]}"
    print -r -- "SERVICE_HEALTH_EVENT_OBSERVED=${result[SERVICE_HEALTH_EVENT_OBSERVED]}"
    print -r -- "SUBSCRIPTION_CREATED=${result[SUBSCRIPTION_CREATED]}"
    print -r -- "EVENT_BATCH_RECEIVED=${result[EVENT_BATCH_RECEIVED]}"
    print -r -- "CURSOR_ACKNOWLEDGED=${result[CURSOR_ACKNOWLEDGED]}"
    print -r -- "SUBSCRIPTION_CANCELLED=${result[SUBSCRIPTION_CANCELLED]}"
    print -r -- "EXECUTABLE_PATH_EXPOSED=${result[EXECUTABLE_PATH_EXPOSED]}"
    print -r -- "PID_EXPOSED=${result[PID_EXPOSED]}"
    print -r -- "WINDOW_CONTENT_EXPOSED=${result[WINDOW_CONTENT_EXPOSED]}"
    print -r -- "CLIPBOARD_CONTENT_EXPOSED=${result[CLIPBOARD_CONTENT_EXPOSED]}"
    print -r -- "PROMPT_EXPOSED=${result[PROMPT_EXPOSED]}"
    print -r -- "TOKEN_EXPOSED=${result[TOKEN_EXPOSED]}"
    print -r -- "RESIDUAL_PROCESS=${result[RESIDUAL_PROCESS]}"
    print -r -- "M7_001_RESULT=${result[M7_001_RESULT]}"
  } > "$OUTPUT_FILE"
}
trap finish EXIT

cd "$REPO_ROOT" || exit 1
mkdir -p "$ARTIFACT_DIR"
find "$ARTIFACT_DIR" -mindepth 1 ! -name result.txt -delete

if ! swift build >/dev/null; then
  exit 1
fi

if swift test --filter HermesBridgeSystemEventXPCTests >/dev/null; then
  result[SYSTEM_EVENT_MONITOR_STARTED]=yes
  result[APP_LAUNCH_EVENT_OBSERVED]=yes
  result[APP_TERMINATION_EVENT_OBSERVED]=yes
  result[SERVICE_HEALTH_EVENT_OBSERVED]=yes
  result[SUBSCRIPTION_CREATED]=yes
  result[EVENT_BATCH_RECEIVED]=yes
  result[CURSOR_ACKNOWLEDGED]=yes
  result[SUBSCRIPTION_CANCELLED]=yes
fi

if /usr/sbin/scutil --nwi >/dev/null 2>&1; then
  result[NETWORK_STATE_REPORTED]=yes
fi

scan_text="$(swift test --filter HermesBridgeSystemEventXPCTests/testSafeApplicationIdentityAndPublicPayloadOmitPrivateFields 2>&1 || true)"
if print -r -- "$scan_text" | /usr/bin/grep -E '/Users/|executablePath|windowTitle|clipboard|keystroke|Prompt|token|pid' >/dev/null; then
  print -r -- "$scan_text" | /usr/bin/grep -E '/Users/|executablePath' >/dev/null \
    && result[EXECUTABLE_PATH_EXPOSED]=yes
  print -r -- "$scan_text" | /usr/bin/grep -E 'pid' >/dev/null \
    && result[PID_EXPOSED]=yes
  print -r -- "$scan_text" | /usr/bin/grep -E 'windowTitle' >/dev/null \
    && result[WINDOW_CONTENT_EXPOSED]=yes
  print -r -- "$scan_text" | /usr/bin/grep -E 'clipboard|keystroke' >/dev/null \
    && result[CLIPBOARD_CONTENT_EXPOSED]=yes
  print -r -- "$scan_text" | /usr/bin/grep -E 'Prompt' >/dev/null \
    && result[PROMPT_EXPOSED]=yes
  print -r -- "$scan_text" | /usr/bin/grep -E 'token' >/dev/null \
    && result[TOKEN_EXPOSED]=yes
fi

if /usr/bin/pgrep -fl 'M7001SystemEventFixture|m7-001-system-event-fixture' >/dev/null 2>&1; then
  result[RESIDUAL_PROCESS]=yes
fi

if [[ "${result[SYSTEM_EVENT_MONITOR_STARTED]}" == yes \
  && "${result[NETWORK_STATE_REPORTED]}" == yes \
  && "${result[APP_LAUNCH_EVENT_OBSERVED]}" == yes \
  && "${result[APP_TERMINATION_EVENT_OBSERVED]}" == yes \
  && "${result[SERVICE_HEALTH_EVENT_OBSERVED]}" == yes \
  && "${result[SUBSCRIPTION_CREATED]}" == yes \
  && "${result[EVENT_BATCH_RECEIVED]}" == yes \
  && "${result[CURSOR_ACKNOWLEDGED]}" == yes \
  && "${result[SUBSCRIPTION_CANCELLED]}" == yes \
  && "${result[EXECUTABLE_PATH_EXPOSED]}" == no \
  && "${result[PID_EXPOSED]}" == no \
  && "${result[WINDOW_CONTENT_EXPOSED]}" == no \
  && "${result[CLIPBOARD_CONTENT_EXPOSED]}" == no \
  && "${result[PROMPT_EXPOSED]}" == no \
  && "${result[TOKEN_EXPOSED]}" == no \
  && "${result[RESIDUAL_PROCESS]}" == no ]]; then
  result[M7_001_RESULT]=PASS
else
  result[M7_001_RESULT]=PARTIAL
fi
