#!/bin/zsh
set -euo pipefail

usage() {
  print -u2 "usage: build-release-candidate.zsh --version <version> --signing-mode <adhoc|developer-id>"
}

die() {
  print -u2 "error: $*"
  exit 1
}

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
version=""
signing_mode=""

while (( $# > 0 )); do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      version="$2"
      shift 2
      ;;
    --signing-mode)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      signing_mode="$2"
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

[[ -n "$version" && -n "$signing_mode" ]] || { usage; exit 64; }
[[ "$signing_mode" == "adhoc" || "$signing_mode" == "developer-id" ]] || die "invalid signing mode"

safe_version="$(printf '%s' "$version" | tr -c 'A-Za-z0-9._-' '-')"
[[ -n "$safe_version" ]] || die "invalid version"

cd "$repo_root"

build_epoch="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || date -u +%s)}"
artifact_root="$repo_root/artifacts/m8-002/release-candidates/HermesBridge-$safe_version"
staging_root="$artifact_root/staging"
payload_root="$staging_root/Payload"
evidence_root="$staging_root/ReleaseEvidence"
log_root="$artifact_root/logs"
app_bundle="$payload_root/Hermes Bridge.app"
bin_root="$payload_root/bin"
docs_root="$payload_root/Docs"
scripts_root="$payload_root/Scripts"

cleanup() {
  if [[ -n "${HERMES_RELEASE_KEYCHAIN_PATH:-}" && -f "$HERMES_RELEASE_KEYCHAIN_PATH" ]]; then
    security delete-keychain "$HERMES_RELEASE_KEYCHAIN_PATH" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

rm -rf "$artifact_root"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources" "$bin_root" "$docs_root" "$scripts_root" "$evidence_root" "$log_root"

{
  xcodebuild -version
  swift --version
  sw_vers
  uname -a
} > "$evidence_root/toolchain.txt"

xcodebuild \
  -project Packaging/HermesBridgeApp/HermesBridgeApp.xcodeproj \
  -scheme HermesBridgeApp \
  -destination 'platform=macOS' \
  -derivedDataPath "$artifact_root/DerivedData" \
  build > "$log_root/xcodebuild.log"

swift build --configuration release \
  --product HermesBridgeService \
  --product HermesBridgeControl > "$log_root/swift-build.log"
swift build --product HermesBridgeApp >> "$log_root/swift-build.log"

bin_path="$repo_root/.build/out/Products/Release"
debug_bin_path="$repo_root/.build/out/Products/Debug"
for product in HermesBridgeService HermesBridgeControl; do
  [[ -x "$bin_path/$product" && ! -L "$bin_path/$product" ]] || die "missing executable product: $product"
done
[[ -x "$debug_bin_path/HermesBridgeApp" && ! -L "$debug_bin_path/HermesBridgeApp" ]] || die "missing executable product: HermesBridgeApp"

cp "$debug_bin_path/HermesBridgeApp" "$app_bundle/Contents/MacOS/HermesBridgeApp"
cp "Packaging/HermesBridgeApp/Info.plist" "$app_bundle/Contents/Info.plist"
chmod 755 "$app_bundle/Contents/MacOS/HermesBridgeApp"

metadata_dir="$(find "$artifact_root/DerivedData" -type d -name Metadata.appintents -print -quit 2>/dev/null || true)"
if [[ -n "$metadata_dir" ]]; then
  mkdir -p "$app_bundle/Contents/Resources"
  cp -R "$metadata_dir" "$app_bundle/Contents/Resources/Metadata.appintents"
fi

cp "$bin_path/HermesBridgeService" "$bin_root/HermesBridgeService"
cp "$bin_path/HermesBridgeControl" "$bin_root/HermesBridgeControl"
chmod 755 "$bin_root/HermesBridgeService" "$bin_root/HermesBridgeControl"

cp Scripts/native/install-hermes-bridge-app.zsh "$scripts_root/install-hermes-bridge-app.zsh"
cp Scripts/native/uninstall-hermes-bridge-app.zsh "$scripts_root/uninstall-hermes-bridge-app.zsh"
chmod 755 "$scripts_root"/*.zsh

cp LICENSE "$payload_root/LICENSE"
cp SECURITY.md "$payload_root/SECURITY.md"
cp README.md "$docs_root/README.md"
cp Docs/Packaging/SigningAndNotarization.md "$docs_root/SigningAndNotarization.md"
cp Docs/Release/ReleasePipeline.md "$docs_root/ReleasePipeline.md"
cp Docs/Release/ReleaseRunbook.md "$docs_root/ReleaseRunbook.md"

cat > "$evidence_root/build-info.json" <<EOF
{
  "schemaVersion": 1,
  "project": "HermesMacOSNativeBridge",
  "version": "$safe_version",
  "sourceDateEpoch": "$build_epoch",
  "gitCommit": "$(git rev-parse HEAD)",
  "gitStatus": "$(git diff --quiet && git diff --cached --quiet && print clean || print dirty)",
  "signingMode": "$signing_mode"
}
EOF

"$repo_root/Scripts/release/sign-release.zsh" --staging-root "$staging_root" --mode "$signing_mode"
"$repo_root/Scripts/release/package-release.zsh" --staging-root "$staging_root" --version "$safe_version" --mode "$signing_mode"

print "staging_root=$staging_root"
find "$artifact_root" -maxdepth 1 -name '*.tar.gz' -print | sort | sed 's/^/archive=/'
