#!/bin/zsh
set -euo pipefail

usage() {
  print -u2 "usage: submit-notarization.zsh --archive <HermesBridgeRelease.zip> --submit (--keychain-profile <name> | --asc-key-id <id> --asc-issuer-id <id> --asc-key <path>) [--staple]"
}

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
archive_path=""
submit="no"
keychain_profile=""
asc_key_id="${ASC_KEY_ID:-}"
asc_issuer_id="${ASC_ISSUER_ID:-}"
asc_key_path="${ASC_KEY_PATH:-}"
staple="no"

while (( $# > 0 )); do
  case "$1" in
    --archive)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      archive_path="$2"
      shift 2
      ;;
    --submit)
      submit="yes"
      shift
      ;;
    --keychain-profile)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      keychain_profile="$2"
      shift 2
      ;;
    --asc-key-id)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      asc_key_id="$2"
      shift 2
      ;;
    --asc-issuer-id)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      asc_issuer_id="$2"
      shift 2
      ;;
    --asc-key)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      asc_key_path="$2"
      shift 2
      ;;
    --staple)
      staple="yes"
      shift
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

[[ "$submit" == "yes" ]] || { print -u2 "refusing notarization upload without --submit"; exit 64; }
[[ -n "$archive_path" ]] || { usage; exit 64; }
[[ "$archive_path" == /* ]] || archive_path="$PWD/$archive_path"
[[ -f "$archive_path" && ! -L "$archive_path" ]] || { print -u2 "archive is missing or symlinked"; exit 65; }

credential_modes=0
[[ -n "$keychain_profile" ]] && credential_modes=$((credential_modes + 1))
[[ -n "$asc_key_id" || -n "$asc_issuer_id" || -n "$asc_key_path" ]] && credential_modes=$((credential_modes + 1))
[[ "$credential_modes" -eq 1 ]] || { print -u2 "choose exactly one credential mode"; exit 64; }

tmp_extract="$(mktemp -d -t hermes-notary-submit.XXXXXX)"
trap 'rm -rf "$tmp_extract"' EXIT
unzip -q "$archive_path" -d "$tmp_extract"
binary="$tmp_extract/HermesBridgeRelease/Payload/HermesBridgeService"
[[ -f "$binary" ]] || { print -u2 "archive does not contain HermesBridgeService"; exit 66; }
codesign --verify --strict --verbose=2 "$binary" >/dev/null
codesign_details="$(codesign -dv --verbose=4 "$binary" 2>&1)"
if ! print -- "$codesign_details" | grep -q '^Authority=Developer ID Application:'; then
  print -u2 "refusing notarization submission for non-Developer ID signed artifact"
  exit 67
fi

if [[ -n "$keychain_profile" ]]; then
  xcrun notarytool submit "$archive_path" --keychain-profile "$keychain_profile" --wait
else
  [[ -n "$asc_key_id" && -n "$asc_issuer_id" && -n "$asc_key_path" ]] || { print -u2 "App Store Connect key mode requires key id, issuer id, and key path"; exit 64; }
  [[ -f "$asc_key_path" ]] || { print -u2 "App Store Connect key path is unavailable"; exit 65; }
  xcrun notarytool submit "$archive_path" --key "$asc_key_path" --key-id "$asc_key_id" --issuer "$asc_issuer_id" --wait
fi

if [[ "$staple" == "yes" ]]; then
  case "${archive_path:e}" in
    app|pkg|dmg)
      xcrun stapler staple "$archive_path"
      ;;
    *)
      print "staple_skipped=unsupported_artifact_type"
      ;;
  esac
fi
