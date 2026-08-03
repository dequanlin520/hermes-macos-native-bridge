#!/bin/zsh
set -euo pipefail

APP_NAME="Hermes macOS Native Bridge.app"
EXPECTED_BUNDLE_ID="com.hermes.bridge.app"
EXPECTED_VERSION="0.1.0-rc.1"
APP_EXECUTABLE_NAME="HermesBridgeApp"
LABEL="com.hermes.bridge"
MACH_SERVICE="com.hermes.bridge.xpc"
SCRIPT_DIR="${0:A:h}"
STAGING_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

STAGED_APP="$STAGING_ROOT/$APP_NAME"
STAGED_CONTROL="$STAGING_ROOT/bin/HermesBridgeControl"
STAGED_LIFECYCLE="$STAGING_ROOT/bin/HermesBridgeServiceLifecycle"
STAGED_SERVICE="$STAGED_APP/Contents/Library/XPCServices/HermesBridgeService.xpc/Contents/MacOS/HermesBridgeService"
STAGED_LAUNCH_AGENT="$STAGING_ROOT/Library/LaunchAgents/$LABEL.plist"

APP_TARGET="$HOME/Applications/$APP_NAME"
BRIDGE_SUPPORT="$HOME/Library/Application Support/HermesBridge"
SERVICE_TARGET="$BRIDGE_SUPPORT/HermesBridgeService"
CONTROL_TARGET="$BRIDGE_SUPPORT/HermesBridgeControl"
LIFECYCLE_TARGET="$BRIDGE_SUPPORT/HermesBridgeServiceLifecycle"
LAUNCH_AGENT_TARGET="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGS_ROOT="$HOME/Library/Logs/HermesBridge"
RUNTIME_ROOT="$HOME/Library/Application Support/HermesBridge/Runtime"
SERVICE_DOMAIN="gui/$(id -u)"
FIXTURE_MODE="${HERMES_INSTALLER_FIXTURE_MODE:-NO}"

usage() {
  print -u2 "usage: $0 --install-user-app"
}

die() {
  local code="${2:-1}"
  print -u2 "error: $1"
  exit "$code"
}

require_flag() {
  if [[ $# -ne 1 || "$1" != "--install-user-app" ]]; then
    usage
    exit 2
  fi
}

assert_user_scope() {
  case "$APP_TARGET" in
    "$HOME/Applications/"*) ;;
    *) die "app destination is outside current HOME: $APP_TARGET" 70 ;;
  esac
  case "$LAUNCH_AGENT_TARGET" in
    "$HOME/Library/LaunchAgents/"*) ;;
    *) die "LaunchAgent destination is outside current HOME: $LAUNCH_AGENT_TARGET" 70 ;;
  esac
  case "$BRIDGE_SUPPORT" in
    "$HOME/Library/Application Support/HermesBridge") ;;
    *) die "helper destination is outside current HOME: $BRIDGE_SUPPORT" 70 ;;
  esac
  [[ "$APP_TARGET" != /Applications/* ]] || die "system Applications destination is forbidden" 70
  [[ "$LAUNCH_AGENT_TARGET" != /Library/LaunchAgents/* ]] || die "system LaunchAgents destination is forbidden" 70
  [[ "$BRIDGE_SUPPORT" != /usr/local/* && "$BRIDGE_SUPPORT" != /opt/homebrew/* ]] || die "system helper destination is forbidden" 70
}

assert_staged_assets() {
  [[ -d "$STAGED_APP" ]] || die "missing staged app: $STAGED_APP" 66
  [[ -x "$STAGED_APP/Contents/MacOS/$APP_EXECUTABLE_NAME" ]] || die "missing staged app executable: $STAGED_APP/Contents/MacOS/$APP_EXECUTABLE_NAME" 66
  [[ -x "$STAGED_SERVICE" ]] || die "missing staged service executable: $STAGED_SERVICE" 66
  [[ -x "$STAGED_CONTROL" ]] || die "missing staged control executable: $STAGED_CONTROL" 66
  [[ -x "$STAGED_LIFECYCLE" ]] || die "missing staged lifecycle executable: $STAGED_LIFECYCLE" 66
  [[ -f "$STAGED_LAUNCH_AGENT" ]] || die "missing staged LaunchAgent: $STAGED_LAUNCH_AGENT" 66
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

validate_staged_app() {
  local plist="$STAGED_APP/Contents/Info.plist"
  [[ -f "$plist" ]] || die "missing staged Info.plist: $plist" 66
  /usr/bin/plutil -lint "$plist" >/dev/null || die "invalid staged Info.plist: $plist" 66
  [[ "$(plist_value "$plist" CFBundleIdentifier)" == "$EXPECTED_BUNDLE_ID" ]] || die "unexpected bundle identifier in staged app" 66
  [[ "$(plist_value "$plist" CFBundleShortVersionString)" == "$EXPECTED_VERSION" ]] || die "unexpected staged app version: $(plist_value "$plist" CFBundleShortVersionString)" 66
}

prepare_directories() {
  for directory in \
    "$HOME/Applications" \
    "$HOME/Library/LaunchAgents" \
    "$BRIDGE_SUPPORT" \
    "$LOGS_ROOT" \
    "$RUNTIME_ROOT"; do
    if [[ -L "$directory" ]]; then
      die "refusing to use symlinked directory: $directory" 73
    fi
    mkdir -p "$directory"
  done
}

replace_directory_with_ditto() {
  local src="$1"
  local dest="$2"
  local tmp="${dest}.install.$$"
  rm -rf "$tmp"
  /usr/bin/ditto "$src" "$tmp"
  rm -rf "$dest"
  mv "$tmp" "$dest"
}

copy_helpers() {
  /usr/bin/ditto "$STAGED_SERVICE" "$SERVICE_TARGET"
  /usr/bin/ditto "$STAGED_CONTROL" "$CONTROL_TARGET"
  /usr/bin/ditto "$STAGED_LIFECYCLE" "$LIFECYCLE_TARGET"
  chmod 755 "$SERVICE_TARGET" "$CONTROL_TARGET" "$LIFECYCLE_TARGET"
}

write_launch_agent() {
  /usr/bin/python3 - "$STAGED_LAUNCH_AGENT" "$LAUNCH_AGENT_TARGET" "$SERVICE_TARGET" "$LOGS_ROOT" "$RUNTIME_ROOT" <<'PY'
import plistlib
import sys
from pathlib import Path

source, target, service, logs, runtime = map(Path, sys.argv[1:])
data = plistlib.loads(source.read_bytes())
data["Label"] = "com.hermes.bridge"
data["MachServices"] = {"com.hermes.bridge.xpc": True}
data["ProgramArguments"] = [str(service)]
data["StandardOutPath"] = str(logs / "service.stdout.log")
data["StandardErrorPath"] = str(logs / "service.stderr.log")
env = dict(data.get("EnvironmentVariables", {}))
env["HERMES_BRIDGE_RUNTIME_ROOT"] = str(runtime)
data["EnvironmentVariables"] = env
target.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=True))
PY
  chmod 600 "$LAUNCH_AGENT_TARGET"
  /usr/bin/plutil -lint "$LAUNCH_AGENT_TARGET" >/dev/null || die "invalid installed LaunchAgent: $LAUNCH_AGENT_TARGET" 65
}

validate_installed_app() {
  local plist="$APP_TARGET/Contents/Info.plist"
  [[ -d "$APP_TARGET" ]] || die "installed app is missing: $APP_TARGET" 65
  [[ -x "$APP_TARGET/Contents/MacOS/$APP_EXECUTABLE_NAME" ]] || die "installed app executable is missing or not executable" 65
  /usr/bin/plutil -lint "$plist" >/dev/null || die "invalid installed Info.plist: $plist" 65
  [[ "$(plist_value "$plist" CFBundleShortVersionString)" == "$EXPECTED_VERSION" ]] || die "unexpected installed app version" 65
}

validate_installed_launch_agent() {
  local program label
  label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$LAUNCH_AGENT_TARGET")"
  program="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$LAUNCH_AGENT_TARGET")"
  [[ "$label" == "$LABEL" ]] || die "installed LaunchAgent has unexpected label: $label" 65
  [[ "$program" == "$SERVICE_TARGET" ]] || die "installed LaunchAgent points at wrong service: $program" 65
  [[ "$program" != "$STAGING_ROOT"* ]] || die "installed LaunchAgent points into staging" 65
  [[ "$program" != /Applications/* && "$program" != /Library/* && "$program" != /usr/local/* && "$program" != /opt/homebrew/* ]] || die "installed LaunchAgent points at system path" 65
  if /usr/bin/grep -R -I -F "$STAGING_ROOT" "$LAUNCH_AGENT_TARGET" >/dev/null; then
    die "installed LaunchAgent contains developer or source-tree path" 65
  fi
}

launchctl_available_for_gui_domain() {
  [[ "$FIXTURE_MODE" != "YES" ]] || return 1
  /bin/launchctl print "$SERVICE_DOMAIN" >/dev/null 2>&1
}

unload_existing_launch_agent() {
  if ! launchctl_available_for_gui_domain; then
    return 0
  fi

  if /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1; then
    /bin/launchctl bootout "$SERVICE_DOMAIN/$LABEL" >/dev/null 2>&1 || true
  fi
}

bootstrap_launch_agent() {
  if ! launchctl_available_for_gui_domain; then
    print -r -- "LAUNCH_AGENT_BOOTSTRAP_SKIPPED=yes"
    return 0
  fi

  /bin/launchctl bootstrap "$SERVICE_DOMAIN" "$LAUNCH_AGENT_TARGET" >/dev/null
  /bin/launchctl print "$SERVICE_DOMAIN/$LABEL" >/dev/null
  print -r -- "LAUNCH_AGENT_BOOTSTRAPPED=yes"
}

main() {
  require_flag "$@"
  assert_user_scope
  assert_staged_assets
  validate_staged_app
  prepare_directories
  unload_existing_launch_agent
  replace_directory_with_ditto "$STAGED_APP" "$APP_TARGET"
  copy_helpers
  write_launch_agent
  validate_installed_app
  validate_installed_launch_agent
  bootstrap_launch_agent

  print -r -- "STAGING_ROOT=$STAGING_ROOT"
  print -r -- "APP_INSTALLED=yes"
  print -r -- "HELPERS_INSTALLED=yes"
  print -r -- "LAUNCH_AGENT_INSTALLED=yes"
  print -r -- "INSTALLED_APP_PATH=$APP_TARGET"
  print -r -- "INSTALLED_SERVICE_PATH=$SERVICE_TARGET"
}

main "$@"
