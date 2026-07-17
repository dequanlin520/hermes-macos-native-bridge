#!/bin/zsh
set -euo pipefail

usage() {
  print -u2 "usage: verify-release.zsh --release-dir <HermesBridgeRelease> [--archive <HermesBridgeRelease.zip>]"
}

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
release_dir=""
archive_path=""
expect_failure_archive=""

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
    --expect-failure-archive)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      expect_failure_archive="$2"
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

[[ -n "$release_dir" ]] || { usage; exit 64; }
[[ "$release_dir" == /* ]] || release_dir="$PWD/$release_dir"
release_dir="$(cd "$release_dir" && pwd -P)"
[[ "$(basename "$release_dir")" == "HermesBridgeRelease" ]] || { print -u2 "release dir must be named HermesBridgeRelease"; exit 65; }

payload_binary="$release_dir/Payload/HermesBridgeService"
payload_plist="$release_dir/Payload/com.hermes.bridge.plist"
manifest="$release_dir/Metadata/release-manifest.json"
checksums="$release_dir/Metadata/checksums.sha256"
build_info="$release_dir/Metadata/build-info.json"
entitlements="$repo_root/Packaging/Entitlements/HermesBridgeService.entitlements"

expected=(
  "Payload/HermesBridgeService"
  "Payload/com.hermes.bridge.plist"
  "Metadata/release-manifest.json"
  "Metadata/checksums.sha256"
  "Metadata/build-info.json"
)
actual=("${(@f)$(cd "$release_dir" && find . -type f | sed 's#^\./##' | sort)}")
expected_sorted=("${(@f)$(printf '%s\n' "${expected[@]}" | sort)}")
if [[ "$(printf '%s\n' "${actual[@]}")" != "$(printf '%s\n' "${expected_sorted[@]}")" ]]; then
  print -u2 "release contains unexpected files"
  printf '%s\n' "${actual[@]}" >&2
  exit 66
fi

for item in "$payload_binary" "$payload_plist" "$manifest" "$checksums" "$build_info"; do
  [[ -f "$item" ]] || { print -u2 "missing release file: $item"; exit 66; }
  [[ ! -L "$item" ]] || { print -u2 "symlink not allowed: $item"; exit 66; }
done

[[ -x "$payload_binary" ]] || { print -u2 "service binary is not executable"; exit 67; }
file "$payload_binary" | grep -Eq 'Mach-O .*executable' || { print -u2 "service binary is not a Mach-O executable"; exit 67; }

plutil -lint "$payload_plist" >/dev/null
label="$(plutil -extract Label raw -o - "$payload_plist")"
mach="$(/usr/libexec/PlistBuddy -c "Print :MachServices:com.hermes.bridge.xpc" "$payload_plist")"
[[ "$label" == "com.hermes.bridge" ]] || { print -u2 "unexpected LaunchAgent Label"; exit 68; }
[[ "$mach" == "1" || "$mach" == "true" ]] || { print -u2 "missing fixed Mach service"; exit 68; }

codesign --verify --strict --verbose=2 "$payload_binary" >/dev/null
codesign_details="$(codesign -dv --verbose=4 "$payload_binary" 2>&1)"
print -- "$codesign_details" | sed -n '/^Authority=/p;/^TeamIdentifier=/p;/^Runtime Version=/p;/^Identifier=/p'
if ! print -- "$codesign_details" | grep -q '^Runtime Version='; then
  print -u2 "hardened runtime is not enabled"
  exit 69
fi

tmp_entitlements="$(mktemp -t hermes-entitlements.XXXXXX)"
tmp_policy="$(mktemp -t hermes-entitlements-policy.XXXXXX)"
trap 'rm -f "$tmp_entitlements" "$tmp_policy"; [[ -n "${tmp_extract:-}" ]] && rm -rf "$tmp_extract"' EXIT
codesign -d --entitlements :- "$payload_binary" > "$tmp_entitlements" 2>/dev/null
plutil -convert xml1 -o "$tmp_entitlements" "$tmp_entitlements"
plutil -convert xml1 -o "$tmp_policy" "$entitlements"
cmp -s "$tmp_entitlements" "$tmp_policy" || { print -u2 "signed entitlements do not match policy"; exit 70; }

plutil -p "$manifest" >/dev/null
plutil -p "$build_info" >/dev/null
manifest_binary_checksum="$(plutil -extract binaryChecksumSHA256 raw -o - "$manifest")"
manifest_plist_checksum="$(plutil -extract plistChecksumSHA256 raw -o - "$manifest")"
[[ "$manifest_binary_checksum" == "$(shasum -a 256 "$payload_binary" | awk '{print $1}')" ]] || { print -u2 "manifest binary checksum mismatch"; exit 71; }
[[ "$manifest_plist_checksum" == "$(shasum -a 256 "$payload_plist" | awk '{print $1}')" ]] || { print -u2 "manifest plist checksum mismatch"; exit 71; }
[[ "$(plutil -extract launchdLabel raw -o - "$manifest")" == "com.hermes.bridge" ]] || { print -u2 "manifest label mismatch"; exit 71; }
[[ "$(plutil -extract machServiceName raw -o - "$manifest")" == "com.hermes.bridge.xpc" ]] || { print -u2 "manifest Mach service mismatch"; exit 71; }

(
  cd "$release_dir"
  shasum -a 256 -c "$checksums" >/dev/null
)

if grep -R -I -n -E 'HERMES_DASHBOARD_SESSION_TOKEN|backend token|Prompt|prompt|State|Runtime|Logs|/Users/|/private/|/var/folders|BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY|APPLE_ID|APP_SPECIFIC_PASSWORD|ASC_KEY' "$release_dir"/Metadata "$release_dir"/Payload/com.hermes.bridge.plist >/dev/null; then
  print -u2 "release metadata or plist contains forbidden private, token, prompt, or state marker"
  exit 72
fi

if [[ -n "$archive_path" ]]; then
  [[ "$archive_path" == /* ]] || archive_path="$PWD/$archive_path"
  [[ -f "$archive_path" && ! -L "$archive_path" ]] || { print -u2 "archive missing or symlinked"; exit 73; }
  unzip -Z1 "$archive_path" | sort > "${tmp_policy}.ziplist"
  expected_zip=(
    "HermesBridgeRelease/"
    "HermesBridgeRelease/Metadata/"
    "HermesBridgeRelease/Metadata/build-info.json"
    "HermesBridgeRelease/Metadata/checksums.sha256"
    "HermesBridgeRelease/Metadata/release-manifest.json"
    "HermesBridgeRelease/Payload/"
    "HermesBridgeRelease/Payload/HermesBridgeService"
    "HermesBridgeRelease/Payload/com.hermes.bridge.plist"
  )
  if [[ "$(cat "${tmp_policy}.ziplist")" != "$(printf '%s\n' "${expected_zip[@]}" | sort)" ]]; then
    print -u2 "archive contains unexpected entries"
    cat "${tmp_policy}.ziplist" >&2
    exit 73
  fi
  tmp_extract="$(mktemp -d -t hermes-release-extract.XXXXXX)"
  unzip -q "$archive_path" -d "$tmp_extract"
  "$0" --release-dir "$tmp_extract/HermesBridgeRelease" >/dev/null
fi

if [[ -n "$expect_failure_archive" ]]; then
  if "$0" --release-dir "$release_dir" --archive "$expect_failure_archive" >/dev/null 2>&1; then
    print -u2 "expected tampered archive verification to fail"
    exit 74
  fi
fi

print "release verification passed"
