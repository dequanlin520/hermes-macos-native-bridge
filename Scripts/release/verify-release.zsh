#!/bin/zsh
set -euo pipefail

usage() {
  print -u2 "usage: verify-release.zsh --staging-root <root> --archive <archive> --mode <rc|production>"
}

die() {
  print -u2 "error: $*"
  exit 1
}

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
staging_root=""
archive=""
mode=""

while (( $# > 0 )); do
  case "$1" in
    --staging-root)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      staging_root="$2"
      shift 2
      ;;
    --archive)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      archive="$2"
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      mode="$2"
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

[[ -n "$staging_root" && -n "$archive" && -n "$mode" ]] || { usage; exit 64; }
[[ "$staging_root" == /* ]] || staging_root="$PWD/$staging_root"
[[ "$archive" == /* ]] || archive="$PWD/$archive"
staging_root="$(cd "$staging_root" && pwd -P)"
[[ "$staging_root" == "$repo_root/artifacts/"* ]] || die "staging root must be artifact-owned"
[[ -f "$archive" && ! -L "$archive" ]] || die "archive missing or symlinked"

required=(
  "Payload/Hermes Bridge.app/Contents/Info.plist"
  "Payload/Hermes Bridge.app/Contents/MacOS/HermesBridgeApp"
  "Payload/bin/HermesBridgeService"
  "Payload/bin/HermesBridgeControl"
  "Payload/Scripts/install-hermes-bridge-app.zsh"
  "Payload/Scripts/uninstall-hermes-bridge-app.zsh"
  "Payload/LICENSE"
  "Payload/SECURITY.md"
  "Payload/Docs/README.md"
  "Payload/Docs/SigningAndNotarization.md"
  "Payload/Docs/ReleasePipeline.md"
  "Payload/Docs/ReleaseRunbook.md"
  "ReleaseEvidence/sbom.spdx.json"
  "ReleaseEvidence/checksums.sha256"
  "ReleaseEvidence/release-manifest.json"
  "ReleaseEvidence/release-gate-summary.env"
)

for item in "${required[@]}"; do
  [[ -e "$staging_root/$item" && ! -L "$staging_root/$item" ]] || die "missing or symlinked release file: $item"
done

if find "$staging_root" \( -name .git -o -name .build -o -name DerivedData -o -name '*.keychain' -o -name '*.keychain-db' -o -name '*.prompt' \) | grep -q .; then
  die "release contains excluded paths"
fi

if grep -R -I -n -E 'BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY|APPLE_APP_SPECIFIC_PASSWORD=.*[^}]|APPLE_DEVELOPER_ID_APPLICATION_PASSWORD=.*[^}]|APPLE_API_PRIVATE_KEY_BASE64=.*[^}]|/Users/|/private/|/var/folders' "$staging_root" >/dev/null; then
  die "release contains a secret or private path marker"
fi

codesign --verify --deep --strict "$staging_root/Payload/Hermes Bridge.app" >/dev/null
codesign --verify --strict "$staging_root/Payload/bin/HermesBridgeService" >/dev/null
codesign --verify --strict "$staging_root/Payload/bin/HermesBridgeControl" >/dev/null
app_codesign_details="$(codesign -dv --verbose=4 "$staging_root/Payload/Hermes Bridge.app" 2>&1)"
service_codesign_details="$(codesign -dv --verbose=4 "$staging_root/Payload/bin/HermesBridgeService" 2>&1)"
print -- "$app_codesign_details" | grep -q '^Runtime Version=' || die "app hardened runtime missing"
print -- "$service_codesign_details" | grep -q '^Runtime Version=' || die "service hardened runtime missing"

plutil -lint "$staging_root/Payload/Hermes Bridge.app/Contents/Info.plist" >/dev/null
plutil -p "$staging_root/ReleaseEvidence/release-manifest.json" >/dev/null
plutil -p "$staging_root/ReleaseEvidence/sbom.spdx.json" >/dev/null
grep -q '"spdxVersion": "SPDX-2.3"' "$staging_root/ReleaseEvidence/sbom.spdx.json" || die "SBOM is not SPDX 2.3 JSON"

(
  cd "$staging_root"
  shasum -a 256 -c "ReleaseEvidence/checksums.sha256" >/dev/null
)
shasum -a 256 -c "$archive.sha256" >/dev/null

summary="$staging_root/ReleaseEvidence/release-gate-summary.env"
for key in CI_BUILD_PASSED CI_TESTS_PASSED XCODE_BUILD_PASSED M8_001_ACCEPTANCE_PASSED RC_PACKAGE_CREATED SBOM_GENERATED CHECKSUMS_GENERATED MANIFEST_GENERATED DEVELOPER_ID_SIGNED NOTARIZATION_ACCEPTED STAPLE_VERIFIED GATEKEEPER_VERIFIED SECRETS_EXPOSED PRIVATE_PATH_EXPOSED RESIDUAL_KEYCHAIN M8_002_RESULT; do
  grep -q "^${key}=" "$summary" || die "missing gate summary key: $key"
done

result="$(sed -n 's/^M8_002_RESULT=//p' "$summary" | tail -n 1)"
case "$mode" in
  rc)
    [[ "$result" == "PASS" || "$result" == "CONDITIONAL" ]] || die "RC result must pass or be conditional"
    ;;
  production)
    [[ "$result" == "PASS" ]] || die "production release must pass"
    grep -q '^DEVELOPER_ID_SIGNED=yes$' "$summary" || die "production unsigned release rejected"
    grep -q '^NOTARIZATION_ACCEPTED=yes$' "$summary" || die "notarization failure rejected"
    grep -q '^STAPLE_VERIFIED=yes$' "$summary" || die "staple verification required"
    grep -q '^GATEKEEPER_VERIFIED=yes$' "$summary" || die "Gatekeeper verification required"
    ;;
  *)
    die "invalid mode"
    ;;
esac

print "release verification passed"
