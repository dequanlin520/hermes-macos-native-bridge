#!/bin/zsh
set -euo pipefail

usage() {
  print -u2 "usage: notarization-preflight.zsh --release-dir <HermesBridgeRelease> --archive <HermesBridgeRelease.zip> [--keychain-profile <name>]"
}

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
release_dir=""
archive_path=""
keychain_profile=""

while (( $# > 0 )); do
  case "$1" in
    --release-dir)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      release_dir="$2"
      shift 2
      ;;
    --archive)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      archive_path="$2"
      shift 2
      ;;
    --keychain-profile)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      keychain_profile="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      print -u2 "unknown argument: $1"
      usage
      exit 64
      ;;
  esac
done

[[ -n "$release_dir" && -n "$archive_path" ]] || { usage; exit 64; }
[[ "$release_dir" == /* ]] || release_dir="$PWD/$release_dir"
[[ "$archive_path" == /* ]] || archive_path="$PWD/$archive_path"

binary="$release_dir/Payload/HermesBridgeService"
manifest="$release_dir/Metadata/release-manifest.json"
blockers=()

notarytool_available=no
developer_id_signed=no
hardened_runtime_enabled=no
archive_ready=no
notarization_ready=no
credentials_configured=no
signing_mode="unknown"

if xcode-select -p >/dev/null 2>&1; then
  print "XCODE_CLT_AVAILABLE=yes"
else
  print "XCODE_CLT_AVAILABLE=no"
  blockers+=("missing-xcode-command-line-tools")
fi

if xcrun notarytool --help >/dev/null 2>&1; then
  notarytool_available=yes
else
  blockers+=("missing-notarytool")
fi

if [[ -f "$manifest" ]]; then
  signing_mode="$(plutil -extract signingMode raw -o - "$manifest" 2>/dev/null || print unknown)"
else
  blockers+=("missing-release-manifest")
fi

if [[ -f "$binary" ]] && codesign --verify --strict --verbose=2 "$binary" >/dev/null 2>&1; then
  codesign_details="$(codesign -dv --verbose=4 "$binary" 2>&1 || true)"
  if print -- "$codesign_details" | grep -q '^Authority=Developer ID Application:'; then
    developer_id_signed=yes
  else
    blockers+=("not-developer-id-signed")
  fi
  if print -- "$codesign_details" | grep -q '^Runtime Version='; then
    hardened_runtime_enabled=yes
  else
    blockers+=("missing-hardened-runtime")
  fi
else
  blockers+=("invalid-or-missing-signature")
fi

if [[ -f "$archive_path" && "${archive_path:e}" == "zip" ]] && unzip -tq "$archive_path" >/dev/null 2>&1; then
  archive_ready=yes
else
  blockers+=("archive-not-ready")
fi

if [[ -n "$keychain_profile" ]]; then
  if xcrun notarytool history --keychain-profile "$keychain_profile" >/dev/null 2>&1; then
    credentials_configured=yes
  else
    blockers+=("keychain-profile-unavailable")
  fi
elif [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
  if [[ -f "$ASC_KEY_PATH" ]]; then
    credentials_configured=yes
  else
    blockers+=("asc-key-path-unavailable")
  fi
else
  blockers+=("missing-notarization-credentials")
fi

if [[ "$notarytool_available" == "yes" && "$developer_id_signed" == "yes" && "$hardened_runtime_enabled" == "yes" && "$archive_ready" == "yes" && "$credentials_configured" == "yes" ]]; then
  notarization_ready=yes
  blockers=()
fi

blocker_value=""
if (( ${#blockers[@]} > 0 )); then
  blocker_value="$(printf '%s\n' "${blockers[@]}" | sort -u | paste -sd, -)"
fi

print "SIGNING_MODE=$signing_mode"
print "CREDENTIALS_CONFIGURED=$credentials_configured"
print "NOTARYTOOL_AVAILABLE=$notarytool_available"
print "DEVELOPER_ID_SIGNED=$developer_id_signed"
print "HARDENED_RUNTIME_ENABLED=$hardened_runtime_enabled"
print "ARCHIVE_READY=$archive_ready"
print "NOTARIZATION_READY=$notarization_ready"
print "NOTARIZATION_BLOCKERS=$blocker_value"
