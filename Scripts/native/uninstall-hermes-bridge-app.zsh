#!/bin/zsh
set -euo pipefail

APP_NAME="Hermes macOS Native Bridge.app"
EXPECTED_BUNDLE_ID="com.hermes.bridge.app"
APP_EXECUTABLE_NAME="HermesBridgeApp"
LABEL="com.hermes.bridge"

APP_TARGET="$HOME/Applications/$APP_NAME"
BRIDGE_SUPPORT="$HOME/Library/Application Support/HermesBridge"
SERVICE_TARGET="$BRIDGE_SUPPORT/HermesBridgeService"
CONTROL_TARGET="$BRIDGE_SUPPORT/HermesBridgeControl"
LIFECYCLE_TARGET="$BRIDGE_SUPPORT/HermesBridgeServiceLifecycle"
RUNTIME_ROOT="$BRIDGE_SUPPORT/Runtime"
LAUNCH_AGENT_TARGET="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGS_ROOT="$HOME/Library/Logs/HermesBridge"
SERVICE_DOMAIN="gui/$(id -u)"
FIXTURE_MODE="${HERMES_INSTALLER_FIXTURE_MODE:-NO}"

usage() {
  print -u2 "usage: $0 --uninstall-user-app"
}

die() {
  local code="${2:-1}"
  print -u2 "error: $1"
  exit "$code"
}

require_flag() {
  if [[ $# -ne 1 || "$1" != "--uninstall-user-app" ]]; then
    usage
    exit 2
  fi
}

assert_user_scope() {
  case "$APP_TARGET" in
    "$HOME/Applications/"*) ;;
    *) die "app target is outside current HOME: $APP_TARGET" 70 ;;
  esac
  case "$LAUNCH_AGENT_TARGET" in
    "$HOME/Library/LaunchAgents/"*) ;;
    *) die "LaunchAgent target is outside current HOME: $LAUNCH_AGENT_TARGET" 70 ;;
  esac
  case "$BRIDGE_SUPPORT" in
    "$HOME/Library/Application Support/HermesBridge") ;;
    *) die "helper target is outside current HOME: $BRIDGE_SUPPORT" 70 ;;
  esac
  [[ "$APP_TARGET" != /Applications/* ]] || die "system Applications target is forbidden" 70
  [[ "$LAUNCH_AGENT_TARGET" != /Library/LaunchAgents/* ]] || die "system LaunchAgents target is forbidden" 70
}

bundle_id_for_app() {
  local app="$1"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true
}

pid_for_exact_app() {
  [[ -d "$APP_TARGET" ]] || return 0
  local expected="$APP_TARGET/Contents/MacOS/$APP_EXECUTABLE_NAME"
  ps -axo pid=,comm= | while read -r pid command; do
    [[ "$command" == "$expected" ]] && print -r -- "$pid"
  done
}

terminate_exact_app() {
  local pids
  pids=("${(@f)$(pid_for_exact_app || true)}")
  (( ${#pids[@]} == 0 )) && return 0
  kill -TERM -- "${pids[@]}" 2>/dev/null || true
}

launchctl_available_for_gui_domain() {
  [[ "$FIXTURE_MODE" != "YES" ]] || return 1
  /bin/launchctl print "$SERVICE_DOMAIN" >/dev/null 2>&1
}

unload_launch_agent() {
  if ! launchctl_available_for_gui_domain; then
    print -r -- "LAUNCH_AGENT_BOOTOUT_SKIPPED=yes"
    return 0
  fi
  if /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1; then
    /bin/launchctl bootout "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1 || true
  fi
}

remove_if_product_owned_file() {
  local target_path="$1"
  [[ -e "$target_path" || -L "$target_path" ]] || return 0
  [[ ! -L "$target_path" && -f "$target_path" ]] || die "refusing to remove non-file product target: $target_path" 73
  rm -f "$target_path"
}

remove_product_directories_if_empty() {
  rmdir "$RUNTIME_ROOT" >/dev/null 2>&1 || true
  rmdir "$BRIDGE_SUPPORT" >/dev/null 2>&1 || true
  rmdir "$LOGS_ROOT" >/dev/null 2>&1 || true
}

main() {
  require_flag "$@"
  assert_user_scope
  unload_launch_agent

  if [[ -e "$APP_TARGET" || -L "$APP_TARGET" ]]; then
    [[ -d "$APP_TARGET" && ! -L "$APP_TARGET" ]] || die "refusing to remove non-directory app target: $APP_TARGET" 73
    [[ "$(bundle_id_for_app "$APP_TARGET")" == "$EXPECTED_BUNDLE_ID" ]] || die "refusing to remove unexpected app bundle: $APP_TARGET" 73
    terminate_exact_app
    rm -rf "$APP_TARGET"
  fi

  if [[ -e "$LAUNCH_AGENT_TARGET" || -L "$LAUNCH_AGENT_TARGET" ]]; then
    [[ ! -L "$LAUNCH_AGENT_TARGET" && -f "$LAUNCH_AGENT_TARGET" ]] || die "refusing to remove non-file LaunchAgent target: $LAUNCH_AGENT_TARGET" 73
    local label
    label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$LAUNCH_AGENT_TARGET" 2>/dev/null || true)"
    [[ "$label" == "$LABEL" ]] || die "refusing to remove unexpected LaunchAgent label: $label" 73
    rm -f "$LAUNCH_AGENT_TARGET"
  fi

  remove_if_product_owned_file "$SERVICE_TARGET"
  remove_if_product_owned_file "$CONTROL_TARGET"
  remove_if_product_owned_file "$LIFECYCLE_TARGET"
  rm -rf "$RUNTIME_ROOT"
  rm -f "$LOGS_ROOT/service.stdout.log" "$LOGS_ROOT/service.stderr.log"
  remove_product_directories_if_empty

  print -r -- "APP_UNINSTALLED=yes"
  print -r -- "HELPERS_REMOVED=yes"
  print -r -- "LAUNCH_AGENT_REMOVED=yes"
}

main "$@"
