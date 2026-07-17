#!/bin/zsh
set -euo pipefail

APP_NAME="Hermes Bridge.app"
EXPECTED_BUNDLE_ID="com.hermes.bridge.app"
EXECUTABLE_NAME="HermesBridgeApp"
INDEXING_WAIT_SECONDS_DEFAULT=20
SCRIPT_DIR="${0:A:h}"

usage() {
  print -u2 "usage: $0 --install-user-app"
}

die() {
  print -u2 "error: $*"
  exit 1
}

require_flag() {
  if [[ $# -ne 1 || "$1" != "--install-user-app" ]]; then
    usage
    exit 2
  fi
}

repo_root() {
  local root
  root="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
  print -r -- "$root"
}

user_app_root() {
  print -r -- "${HOME}/Applications"
}

installed_app_path() {
  print -r -- "$(user_app_root)/${APP_NAME}"
}

artifact_root() {
  print -r -- "$(repo_root)/artifacts/m4-003"
}

built_app_path() {
  print -r -- "$(artifact_root)/build/${APP_NAME}"
}

metadata_present() {
  local app="$1"
  [[ -d "${app}/Contents/Resources" ]] || return 1
  find "${app}/Contents/Resources" -path '*/Metadata.appintents/*' -type f -print -quit | grep -q .
}

validate_expected_metadata() {
  local app="$1"
  local metadata_root="${app}/Contents/Resources"
  local expected=(
    "Submit Hermes Request"
    "Check Hermes Request Status"
    "Cancel Hermes Request"
    "Respond to Hermes Approval"
    "Check Hermes Bridge Health"
  )
  metadata_present "$app" || die "missing App Intents metadata in ${app}"
  local title
  for title in "${expected[@]}"; do
    if ! grep -R -I -F "$title" "$metadata_root" >/dev/null; then
      die "missing App Intents metadata title: ${title}"
    fi
  done
}

validate_bundle_id() {
  local app="$1"
  local plist="${app}/Contents/Info.plist"
  [[ -f "$plist" ]] || die "missing Info.plist: ${plist}"
  plutil -lint "$plist" >/dev/null || die "invalid Info.plist: ${plist}"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
  [[ "$actual" == "$EXPECTED_BUNDLE_ID" ]] || die "wrong bundle identifier: ${actual}"
}

verify_signature() {
  local app="$1"
  codesign --verify --deep --strict "$app" >/dev/null 2>&1 || die "invalid code signature: ${app}"
}

sign_app() {
  local app="$1"
  codesign --force --deep --sign - "$app" >/dev/null || die "failed to ad-hoc sign ${app}"
}

assert_user_app_destination() {
  local root
  root="$(user_app_root)"
  [[ "$root" == "${HOME}/Applications" ]] || die "destination root is not fixed to current-user Applications"
  [[ "$root" != "/Applications" ]] || die "system Applications destination is forbidden"
  if [[ -L "$root" ]]; then
    die "destination root must not be a symlink: ${root}"
  fi
  if [[ -e "$root" && ! -d "$root" ]]; then
    die "destination root is not a directory: ${root}"
  fi
  mkdir -p "$root"
  [[ -d "$root" ]] || die "failed to create destination root: ${root}"
  [[ ! -L "$root" ]] || die "destination root must not be a symlink: ${root}"
}

copy_metadata_from_derived_data() {
  local app="$1"
  local resources="${app}/Contents/Resources"
  local candidates
  mkdir -p "$resources"
  candidates=("${(@f)$(find "${HOME}/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug/*.appintents' -type d 2>/dev/null | sort || true)}")
  local candidate base
  for candidate in "${candidates[@]}"; do
    [[ "${candidate:t}" != "Metadata.appintents" ]] || continue
    if [[ -n "$(find "$candidate" -path '*/Metadata.appintents/*' -type f -print -quit 2>/dev/null)" ]]; then
      base="${candidate:t}"
      rm -rf "${resources}/${base}"
      cp -R "$candidate" "${resources}/${base}"
    fi
  done
}

build_app_bundle() {
  local root artifact app binary
  root="$(repo_root)"
  artifact="$(artifact_root)"
  app="$(built_app_path)"
  binary="${root}/.build/debug/${EXECUTABLE_NAME}"

  cd "$root"
  rm -rf "${artifact}/build"
  mkdir -p "${app}/Contents/MacOS" "${app}/Contents/Resources"

  xcodebuild -scheme HermesBridgeApp -destination 'platform=macOS' build > "${artifact}/xcodebuild.log"
  swift build --product HermesBridgeApp > "${artifact}/swift-build-app.log"

  [[ -x "$binary" ]] || die "missing built executable: ${binary}"
  cp "$binary" "${app}/Contents/MacOS/${EXECUTABLE_NAME}"
  cp "${root}/Packaging/HermesBridgeApp/Info.plist" "${app}/Contents/Info.plist"
  chmod 755 "${app}/Contents/MacOS/${EXECUTABLE_NAME}"

  copy_metadata_from_derived_data "$app"
  validate_bundle_id "$app"
  validate_expected_metadata "$app"
  sign_app "$app"
  verify_signature "$app"
}

backup_existing_app() {
  local dest="$1"
  local artifact="$2"
  local backup_root="${artifact}/backups"
  local manifest="${artifact}/last-backup-path.txt"
  : > "$manifest"
  if [[ -e "$dest" ]]; then
    [[ -d "$dest" && ! -L "$dest" ]] || die "refusing to replace non-directory or symlink at ${dest}"
    mkdir -p "$backup_root"
    local backup="${backup_root}/${APP_NAME%.app}.$(date -u +%Y%m%dT%H%M%SZ).app"
    mv "$dest" "$backup"
    print -r -- "$backup" > "$manifest"
    local old_backups
    old_backups=("${(@f)$(find "$backup_root" -maxdepth 1 -name "${APP_NAME%.app}.*.app" -type d | sort | head -n -3 || true)}")
    if (( ${#old_backups[@]} > 0 )); then
      rm -rf -- "${old_backups[@]}"
    fi
  fi
}

install_atomically() {
  local src="$1"
  local dest="$2"
  local root tmp
  root="$(user_app_root)"
  tmp="${root}/.${APP_NAME}.install.$$"
  rm -rf "$tmp"
  cp -R "$src" "$tmp"
  validate_bundle_id "$tmp"
  validate_expected_metadata "$tmp"
  verify_signature "$tmp"
  mv "$tmp" "$dest"
}

launch_installed_app() {
  local app="$1"
  open -n "$app" || die "failed to launch installed app: ${app}"
}

record_pid() {
  local app="$1"
  local artifact="$2"
  local app_real pid line
  app_real="$(cd "$app" && pwd -P)"
  : > "${artifact}/installed-app-pid.txt"
  sleep 2
  while IFS= read -r line; do
    pid="${line%% *}"
    if [[ -n "$pid" ]]; then
      local proc_path
      proc_path="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
      if [[ "$proc_path" == "${app_real}/Contents/MacOS/${EXECUTABLE_NAME}" ]]; then
        print -r -- "$pid" > "${artifact}/installed-app-pid.txt"
        return 0
      fi
    fi
  done < <(pgrep -fl "${app_real}/Contents/MacOS/${EXECUTABLE_NAME}" 2>/dev/null || true)
}

main() {
  require_flag "$@"
  local artifact app dest
  artifact="$(artifact_root)"
  app="$(built_app_path)"
  dest="$(installed_app_path)"
  mkdir -p "$artifact"

  assert_user_app_destination
  build_app_bundle
  backup_existing_app "$dest" "$artifact"
  install_atomically "$app" "$dest"
  verify_signature "$dest"
  launch_installed_app "$dest"
  record_pid "$dest" "$artifact"

  print -r -- "$dest" > "${artifact}/installed-app-path.txt"
  print -r -- "APP_BUILD_PASSED=yes"
  print -r -- "APP_SIGNATURE_VALID=yes"
  print -r -- "USER_APP_INSTALL_PASSED=yes"
  print -r -- "APP_LAUNCH_REQUESTED=yes"
  print -r -- "INSTALLED_APP_PATH=${dest}"
}

main "$@"
