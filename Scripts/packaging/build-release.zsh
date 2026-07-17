#!/bin/zsh
set -euo pipefail

usage() {
  print -u2 "usage: build-release.zsh --output-dir <artifacts-dir> --signing-mode <adhoc|developer-id> [--identity <Developer ID Application identity>]"
}

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$repo_root"

output_dir=""
signing_mode=""
identity=""
release_mode="local-artifact"

while (( $# > 0 )); do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      output_dir="$2"
      shift 2
      ;;
    --signing-mode)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      signing_mode="$2"
      shift 2
      ;;
    --identity)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      identity="$2"
      shift 2
      ;;
    --release-mode)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      release_mode="$2"
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

[[ -n "$output_dir" && -n "$signing_mode" ]] || { usage; exit 64; }
[[ "$release_mode" == "local-artifact" ]] || { print -u2 "unsupported release mode: $release_mode"; exit 64; }

case "$signing_mode" in
  adhoc)
    [[ -z "$identity" ]] || { print -u2 "adhoc signing does not accept an identity"; exit 64; }
    ;;
  developer-id)
    [[ -n "$identity" ]] || { print -u2 "developer-id signing requires --identity"; exit 64; }
    [[ "$identity" == Developer\ ID\ Application:* ]] || { print -u2 "identity must be a Developer ID Application identity"; exit 65; }
    if ! security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$identity\"" >/dev/null; then
      print -u2 "Developer ID identity is unavailable"
      exit 65
    fi
    ;;
  *)
    print -u2 "unknown signing mode: $signing_mode"
    exit 64
    ;;
esac

if [[ "$output_dir" != /* ]]; then
  output_dir="$repo_root/$output_dir"
fi
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd -P)"
artifacts_root="$repo_root/artifacts"
if [[ "$output_dir" != "$artifacts_root" && "$output_dir" != "$artifacts_root/"* ]]; then
  print -u2 "output directory must be under artifacts/"
  exit 66
fi

release_dir="$output_dir/HermesBridgeRelease"
payload_dir="$release_dir/Payload"
metadata_dir="$release_dir/Metadata"
archive_path="$output_dir/HermesBridgeRelease.zip"
entitlements="$repo_root/Packaging/Entitlements/HermesBridgeService.entitlements"
layout_manifest="$repo_root/Packaging/Release/release-layout.json"

rm -rf "$release_dir" "$archive_path"
mkdir -p "$payload_dir" "$metadata_dir"

swift build --configuration release --product HermesBridgeService
bin_dir="$(swift build --configuration release --show-bin-path)"
service_product="$bin_dir/HermesBridgeService"

if [[ ! -f "$service_product" || ! -x "$service_product" ]]; then
  print -u2 "HermesBridgeService product was not produced"
  exit 67
fi
if [[ -L "$service_product" ]]; then
  print -u2 "refusing symlinked service product"
  exit 67
fi
if [[ "$(basename "$service_product")" != "HermesBridgeService" ]]; then
  print -u2 "unexpected service product name"
  exit 67
fi
matches=("${(@f)$(find "$bin_dir" -maxdepth 1 -type f -perm -111 -name 'HermesBridgeService' -print)}")
if (( ${#matches[@]} != 1 )); then
  print -u2 "expected exactly one HermesBridgeService executable product"
  exit 67
fi

payload_binary="$payload_dir/HermesBridgeService"
payload_plist="$payload_dir/com.hermes.bridge.plist"
cp "$service_product" "$payload_binary"
chmod 755 "$payload_binary"
if [[ -L "$payload_binary" || "$(basename "$payload_binary")" != "HermesBridgeService" ]]; then
  print -u2 "invalid staged service binary"
  exit 67
fi

HERMES_LAUNCHAGENT_ARTIFACT_ROOT="$output_dir" \
  "$repo_root/Scripts/packaging/generate-launchagent-plist.zsh" "$payload_plist" "$payload_binary" >/dev/null
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 /Library/Application Support/HermesBridge/Current/HermesBridgeService" "$payload_plist"
/usr/libexec/PlistBuddy -c "Delete :StandardOutPath" "$payload_plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :StandardErrorPath" "$payload_plist" 2>/dev/null || true
rm -rf "$payload_dir/logs"
plutil -lint "$payload_plist" >/dev/null

if [[ "$signing_mode" == "adhoc" ]]; then
  codesign --force --sign - --options runtime --entitlements "$entitlements" "$payload_binary" >/dev/null
else
  codesign --force --sign "$identity" --timestamp --options runtime --entitlements "$entitlements" "$payload_binary" >/dev/null
fi
codesign --verify --strict --verbose=2 "$payload_binary" >/dev/null

binary_checksum="$(shasum -a 256 "$payload_binary" | awk '{print $1}')"
plist_checksum="$(shasum -a 256 "$payload_plist" | awk '{print $1}')"
git_commit="$(git rev-parse HEAD)"
git_state="$(git diff --quiet && git diff --cached --quiet && print clean || print dirty)"
arch="$(file -b "$payload_binary" | sed 's/"/\\"/g')"
minimum_macos="13.0"
protocol_version="1.0"
build_epoch="${SOURCE_DATE_EPOCH:-$(date -u +%s)}"
build_timestamp="$(date -u -r "$build_epoch" '+%Y-%m-%dT%H:%M:%SZ')"
certificate_common_name=""
if [[ "$signing_mode" == "developer-id" ]]; then
  certificate_common_name="$identity"
fi

cat > "$metadata_dir/release-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "project": "HermesMacOSNativeBridge",
  "version": "m3-002",
  "gitCommit": "$git_commit",
  "gitStatus": "$git_state",
  "buildTimestamp": "$build_timestamp",
  "architecture": "$arch",
  "minimumMacOSVersion": "$minimum_macos",
  "signingMode": "$signing_mode",
  "certificateCommonName": "$certificate_common_name",
  "binaryChecksumSHA256": "$binary_checksum",
  "plistChecksumSHA256": "$plist_checksum",
  "protocolVersion": "$protocol_version",
  "launchdLabel": "com.hermes.bridge",
  "machServiceName": "com.hermes.bridge.xpc"
}
EOF

cat > "$metadata_dir/build-info.json" <<EOF
{
  "schemaVersion": 1,
  "buildTool": "Scripts/packaging/build-release.zsh",
  "releaseLayout": "Packaging/Release/release-layout.json",
  "sourceDateEpoch": "$build_epoch",
  "swiftConfiguration": "release",
  "product": "HermesBridgeService"
}
EOF

(
  cd "$release_dir"
  find Payload Metadata -type f ! -path 'Metadata/checksums.sha256' | sort | while read -r item; do
    shasum -a 256 "$item"
  done > "$metadata_dir/checksums.sha256"
)

if [[ ! -f "$layout_manifest" ]]; then
  print -u2 "release layout manifest missing"
  exit 68
fi

find "$release_dir" -exec touch -h -t 198001010000 {} +
(
  cd "$output_dir"
  COPYFILE_DISABLE=1 zip -X -q -r "HermesBridgeRelease.zip" "HermesBridgeRelease" \
    -x "HermesBridgeRelease/logs/*"
)

"$repo_root/Scripts/packaging/verify-release.zsh" --release-dir "$release_dir" --archive "$archive_path" >/dev/null
print "release_dir=$release_dir"
print "archive=$archive_path"
