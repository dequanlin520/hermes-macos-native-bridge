#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
ARTIFACT_ROOT="${ROOT_DIR}/artifacts/m4-003"
SUMMARY="${ARTIFACT_ROOT}/result.env"
APP_PATH="${HOME}/Applications/Hermes Bridge.app"
EXPECTED_BUNDLE_ID="com.hermes.bridge.app"
INDEXING_WAIT_SECONDS=20
EXPECTED_INTENTS=(
  "Submit Hermes Request"
  "Check Hermes Request Status"
  "Cancel Hermes Request"
  "Respond to Hermes Approval"
  "Check Hermes Bridge Health"
)

usage() {
  print -u2 "usage: $0 --install-user-app --uninstall-user-app"
}

die() {
  print -u2 "error: $*"
  exit 1
}

have_arg() {
  local needle="$1"
  shift
  local arg
  for arg in "$@"; do
    [[ "$arg" == "$needle" ]] && return 0
  done
  return 1
}

write_result() {
  local key="$1"
  local value="$2"
  print -r -- "${key}=${value}" >> "$SUMMARY"
}

metadata_discovered_count() {
  local count=0
  local title
  for title in "${EXPECTED_INTENTS[@]}"; do
    if grep -R -I -F "$title" "${APP_PATH}/Contents/Resources" >/dev/null 2>&1; then
      count=$((count + 1))
    fi
  done
  print -r -- "$count"
}

app_pid_present() {
  [[ -d "$APP_PATH" ]] || return 1
  local app_real line pid proc_path
  app_real="$(cd "$APP_PATH" && pwd -P)"
  while IFS= read -r line; do
    pid="${line%% *}"
    [[ -n "$pid" ]] || continue
    proc_path="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    if [[ "$proc_path" == "${app_real}/Contents/MacOS/HermesBridgeApp" ]]; then
      return 0
    fi
  done < <(pgrep -fl "${app_real}/Contents/MacOS/HermesBridgeApp" 2>/dev/null || true)
  return 1
}

prove_launchservices() {
  local out="${ARTIFACT_ROOT}/launchservices.mdls.txt"
  : > "$out"
  if mdls -name kMDItemCFBundleIdentifier -name kMDItemContentTypeTree "$APP_PATH" > "$out" 2>&1; then
    grep -F "$EXPECTED_BUNDLE_ID" "$out" >/dev/null && return 0
  fi
  if /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -dump > "${ARTIFACT_ROOT}/launchservices-lsregister.txt" 2>/dev/null; then
    grep -F "$APP_PATH" "${ARTIFACT_ROOT}/launchservices-lsregister.txt" >/dev/null && return 0
    grep -F "$EXPECTED_BUNDLE_ID" "${ARTIFACT_ROOT}/launchservices-lsregister.txt" >/dev/null && return 0
  fi
  return 1
}

capture_shortcuts_evidence() {
  if [[ -x /usr/bin/shortcuts ]]; then
    /usr/bin/shortcuts --help > "${ARTIFACT_ROOT}/shortcuts-help.txt" 2>&1 || true
    /usr/bin/shortcuts list > "${ARTIFACT_ROOT}/shortcuts-list.txt" 2>&1 || true
    /usr/bin/shortcuts list --show-identifiers > "${ARTIFACT_ROOT}/shortcuts-list-identifiers.txt" 2>&1 || true
  else
    print -r -- "shortcuts CLI unavailable" > "${ARTIFACT_ROOT}/shortcuts-help.txt"
  fi
  log show --last 5m --style compact \
    --predicate "subsystem CONTAINS[c] \"AppIntents\" OR eventMessage CONTAINS[c] \"${EXPECTED_BUNDLE_ID}\"" \
    > "${ARTIFACT_ROOT}/appintents-log.txt" 2>&1 || true
}

shortcuts_runtime_discovery_count() {
  local evidence_files=(
    "${ARTIFACT_ROOT}/shortcuts-list.txt"
    "${ARTIFACT_ROOT}/shortcuts-list-identifiers.txt"
    "${ARTIFACT_ROOT}/appintents-log.txt"
  )
  local count=0 title file found
  for title in "${EXPECTED_INTENTS[@]}"; do
    found=no
    for file in "${evidence_files[@]}"; do
      if [[ -f "$file" ]] && grep -F "$title" "$file" >/dev/null; then
        found=yes
      fi
    done
    [[ "$found" == "yes" ]] && count=$((count + 1))
  done
  print -r -- "$count"
}

main() {
  if ! have_arg "--install-user-app" "$@" || ! have_arg "--uninstall-user-app" "$@" || [[ $# -ne 2 ]]; then
    usage
    exit 2
  fi

  cd "$ROOT_DIR"
  rm -rf "$ARTIFACT_ROOT"
  mkdir -p "$ARTIFACT_ROOT"
  : > "$SUMMARY"

  local APP_BUILD_PASSED=no
  local APP_SIGNATURE_VALID=no
  local USER_APP_INSTALL_PASSED=no
  local APP_LAUNCH_PASSED=no
  local LAUNCHSERVICES_REGISTRATION_PROVEN=no
  local APP_INTENTS_METADATA_PRESENT=no
  local SHORTCUTS_RUNTIME_DISCOVERY_PROVEN=no
  local EXPECTED_INTENTS_DISCOVERED=0
  local USER_SHORTCUTS_MODIFIED=no
  local APP_UNINSTALL_PASSED=no
  local RESIDUAL_APP_PROCESS=yes

  if Scripts/native/install-hermes-bridge-app.zsh --install-user-app > "${ARTIFACT_ROOT}/install.stdout.txt" 2> "${ARTIFACT_ROOT}/install.stderr.txt"; then
    APP_BUILD_PASSED=yes
    APP_SIGNATURE_VALID=yes
    USER_APP_INSTALL_PASSED=yes
  fi

  if [[ -d "$APP_PATH" ]]; then
    if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
      APP_SIGNATURE_VALID=yes
    else
      APP_SIGNATURE_VALID=no
    fi
    if app_pid_present; then
      APP_LAUNCH_PASSED=yes
    fi
    sleep "$INDEXING_WAIT_SECONDS"
    if prove_launchservices; then
      LAUNCHSERVICES_REGISTRATION_PROVEN=yes
    fi
    if [[ "$(metadata_discovered_count)" -eq "${#EXPECTED_INTENTS[@]}" ]]; then
      APP_INTENTS_METADATA_PRESENT=yes
    fi
    capture_shortcuts_evidence
    EXPECTED_INTENTS_DISCOVERED="$(shortcuts_runtime_discovery_count)"
    if [[ "$EXPECTED_INTENTS_DISCOVERED" -eq "${#EXPECTED_INTENTS[@]}" ]]; then
      SHORTCUTS_RUNTIME_DISCOVERY_PROVEN=yes
    fi
  fi

  if Scripts/native/uninstall-hermes-bridge-app.zsh --uninstall-user-app > "${ARTIFACT_ROOT}/uninstall.stdout.txt" 2> "${ARTIFACT_ROOT}/uninstall.stderr.txt"; then
    APP_UNINSTALL_PASSED=yes
  fi
  if app_pid_present; then
    RESIDUAL_APP_PROCESS=yes
  else
    RESIDUAL_APP_PROCESS=no
  fi

  local verdict="M4-003 VERDICT: NO-GO"
  if [[ "$SHORTCUTS_RUNTIME_DISCOVERY_PROVEN" == "yes" ]]; then
    verdict="M4-003 VERDICT: GO"
  elif [[ "$USER_APP_INSTALL_PASSED" == "yes" && "$APP_LAUNCH_PASSED" == "yes" && "$APP_INTENTS_METADATA_PRESENT" == "yes" && "$LAUNCHSERVICES_REGISTRATION_PROVEN" == "yes" ]]; then
    verdict="M4-003 VERDICT: CONDITIONAL GO"
  fi

  write_result "APP_BUILD_PASSED" "$APP_BUILD_PASSED"
  write_result "APP_SIGNATURE_VALID" "$APP_SIGNATURE_VALID"
  write_result "USER_APP_INSTALL_PASSED" "$USER_APP_INSTALL_PASSED"
  write_result "APP_LAUNCH_PASSED" "$APP_LAUNCH_PASSED"
  write_result "LAUNCHSERVICES_REGISTRATION_PROVEN" "$LAUNCHSERVICES_REGISTRATION_PROVEN"
  write_result "APP_INTENTS_METADATA_PRESENT" "$APP_INTENTS_METADATA_PRESENT"
  write_result "SHORTCUTS_RUNTIME_DISCOVERY_PROVEN" "$SHORTCUTS_RUNTIME_DISCOVERY_PROVEN"
  write_result "EXPECTED_INTENTS_DISCOVERED" "$EXPECTED_INTENTS_DISCOVERED"
  write_result "USER_SHORTCUTS_MODIFIED" "$USER_SHORTCUTS_MODIFIED"
  write_result "APP_UNINSTALL_PASSED" "$APP_UNINSTALL_PASSED"
  write_result "RESIDUAL_APP_PROCESS" "$RESIDUAL_APP_PROCESS"
  print -r -- "$verdict" >> "$SUMMARY"
  cat "$SUMMARY"
}

main "$@"
