#!/bin/zsh
set -euo pipefail

APP_NAME="Hermes Bridge.app"
EXPECTED_BUNDLE_ID="com.hermes.bridge.app"
EXECUTABLE_NAME="HermesBridgeApp"
SCRIPT_DIR="${0:A:h}"

usage() {
  print -u2 "usage: $0 --uninstall-user-app"
}

die() {
  print -u2 "error: $*"
  exit 1
}

require_flag() {
  if [[ $# -ne 1 || "$1" != "--uninstall-user-app" ]]; then
    usage
    exit 2
  fi
}

repo_root() {
  local root
  root="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
  print -r -- "$root"
}

artifact_root() {
  print -r -- "$(repo_root)/artifacts/m4-003"
}

user_app_root() {
  print -r -- "${HOME}/Applications"
}

installed_app_path() {
  print -r -- "$(user_app_root)/${APP_NAME}"
}

bundle_id_for_app() {
  local app="$1"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app}/Contents/Info.plist" 2>/dev/null || true
}

pid_for_exact_app() {
  local app="$1"
  [[ -d "$app" ]] || return 0
  local app_real line pid proc_path
  app_real="$(cd "$app" && pwd -P)"
  while IFS= read -r line; do
    pid="${line%% *}"
    [[ -n "$pid" ]] || continue
    proc_path="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    if [[ "$proc_path" == "${app_real}/Contents/MacOS/${EXECUTABLE_NAME}" ]]; then
      print -r -- "$pid"
    fi
  done < <(pgrep -fl "${app_real}/Contents/MacOS/${EXECUTABLE_NAME}" 2>/dev/null || true)
}

terminate_exact_app() {
  local app="$1"
  [[ -d "$app" ]] || return 0
  local bundle_id
  bundle_id="$(bundle_id_for_app "$app")"
  [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || die "refusing to terminate unexpected bundle identifier: ${bundle_id}"
  /usr/bin/osascript -e "tell application id \"${EXPECTED_BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
  local deadline=$(( $(date +%s) + 10 ))
  while [[ -n "$(pid_for_exact_app "$app")" && $(date +%s) -lt $deadline ]]; do
    sleep 0.5
  done
  local pids
  pids=("${(@f)$(pid_for_exact_app "$app" || true)}")
  if (( ${#pids[@]} > 0 )); then
    kill -TERM -- "${pids[@]}" 2>/dev/null || true
  fi
}

restore_backup_if_available() {
  local dest="$1"
  local artifact="$2"
  local manifest="${artifact}/last-backup-path.txt"
  [[ -f "$manifest" ]] || return 0
  local backup
  backup="$(cat "$manifest")"
  [[ -n "$backup" && -d "$backup" ]] || return 0
  [[ ! -e "$dest" ]] || die "cannot restore backup while destination still exists: ${dest}"
  mv "$backup" "$dest"
  : > "$manifest"
}

main() {
  require_flag "$@"
  local root dest artifact
  root="$(user_app_root)"
  dest="$(installed_app_path)"
  artifact="$(artifact_root)"
  [[ "$root" == "${HOME}/Applications" ]] || die "destination root is not fixed to current-user Applications"
  [[ "$root" != "/Applications" ]] || die "system Applications destination is forbidden"
  [[ ! -L "$root" ]] || die "destination root must not be a symlink: ${root}"

  if [[ -e "$dest" ]]; then
    [[ -d "$dest" && ! -L "$dest" ]] || die "refusing to remove non-directory or symlink at ${dest}"
    local bundle_id
    bundle_id="$(bundle_id_for_app "$dest")"
    [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || die "refusing to remove unexpected bundle identifier: ${bundle_id}"
    terminate_exact_app "$dest"
    rm -rf "$dest"
  fi

  restore_backup_if_available "$dest" "$artifact"

  local residual="no"
  if [[ -d "$dest" && "$(bundle_id_for_app "$dest")" == "$EXPECTED_BUNDLE_ID" && -n "$(pid_for_exact_app "$dest")" ]]; then
    residual="yes"
  fi

  print -r -- "APP_UNINSTALL_PASSED=yes"
  print -r -- "RESIDUAL_APP_PROCESS=${residual}"
}

main "$@"
