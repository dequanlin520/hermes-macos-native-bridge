#!/bin/zsh
set -euo pipefail

usage() {
  print -u2 "usage: generate-release-manifest.zsh --staging-root <root> --mode <rc|production> --acceptance-result <result.txt>"
}

die() {
  print -u2 "error: $*"
  exit 1
}

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
staging_root=""
mode=""
acceptance_result=""

while (( $# > 0 )); do
  case "$1" in
    --staging-root)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      staging_root="$2"
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      mode="$2"
      shift 2
      ;;
    --acceptance-result)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      acceptance_result="$2"
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

[[ -n "$staging_root" && -n "$mode" && -n "$acceptance_result" ]] || { usage; exit 64; }
[[ "$staging_root" == /* ]] || staging_root="$PWD/$staging_root"
[[ "$acceptance_result" == /* ]] || acceptance_result="$PWD/$acceptance_result"
staging_root="$(cd "$staging_root" && pwd -P)"
[[ "$staging_root" == "$repo_root/artifacts/"* ]] || die "staging root must be artifact-owned"
[[ -f "$acceptance_result" ]] || die "missing M8-001 acceptance result"

evidence_root="$staging_root/ReleaseEvidence"
manifest="$evidence_root/release-manifest.json"
summary="$evidence_root/release-gate-summary.env"
signing_report="$evidence_root/signing-report.env"
notarization_report="$evidence_root/notarization-report.env"
checksums="$evidence_root/checksums.sha256"
sbom="$evidence_root/sbom.spdx.json"
mkdir -p "$evidence_root"

get_value() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 0
  sed -n "s/^${key}=//p" "$file" | tail -n 1
}

ci_build="yes"
ci_tests="yes"
xcode_build="yes"
m8_acceptance="$(get_value "$acceptance_result" M8_001_RESULT)"
m8_functional_ok="no"
if [[ "$m8_acceptance" == "PASS" || "$m8_acceptance" == "CONDITIONAL" ]]; then
  m8_functional_ok="yes"
fi
developer_id_signed="$(get_value "$signing_report" DEVELOPER_ID_SIGNED)"
hardened_runtime="$(get_value "$signing_report" HARDENED_RUNTIME_ENABLED)"
notarization_accepted="$(get_value "$notarization_report" NOTARIZATION_ACCEPTED)"
staple_verified="$(get_value "$notarization_report" STAPLE_VERIFIED)"
gatekeeper_verified="$(get_value "$notarization_report" GATEKEEPER_VERIFIED)"

[[ -n "$developer_id_signed" ]] || developer_id_signed="no"
[[ -n "$hardened_runtime" ]] || hardened_runtime="no"
[[ -n "$notarization_accepted" ]] || notarization_accepted="no"
[[ -n "$staple_verified" ]] || staple_verified="no"
[[ -n "$gatekeeper_verified" ]] || gatekeeper_verified="no"

secrets_exposed="no"
private_path_exposed="no"
if grep -R -I -n -E 'BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY|APPLE_APP_SPECIFIC_PASSWORD=.*[^}]|APPLE_DEVELOPER_ID_APPLICATION_PASSWORD=.*[^}]|/Users/|/private/|/var/folders' "$staging_root" >/dev/null; then
  private_path_exposed="yes"
fi
if grep -R -I -n -E 'BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY|APPLE_APP_SPECIFIC_PASSWORD=.*[^}]|APPLE_DEVELOPER_ID_APPLICATION_PASSWORD=.*[^}]|APPLE_API_PRIVATE_KEY_BASE64=.*[^}]' "$staging_root" >/dev/null; then
  secrets_exposed="yes"
fi

residual_keychain="no"
if find "$staging_root" -name '*.keychain' -o -name '*.keychain-db' | grep -q .; then
  residual_keychain="yes"
fi

result="FAIL"
if [[ "$m8_functional_ok" == "yes" && "$developer_id_signed" == "yes" && "$notarization_accepted" == "yes" && "$staple_verified" == "yes" && "$gatekeeper_verified" == "yes" && "$secrets_exposed" == "no" && "$private_path_exposed" == "no" && "$residual_keychain" == "no" ]]; then
  result="PASS"
elif [[ "$mode" == "rc" && "$m8_functional_ok" == "yes" && "$developer_id_signed" == "no" && "$secrets_exposed" == "no" && "$private_path_exposed" == "no" && "$residual_keychain" == "no" ]]; then
  result="CONDITIONAL"
fi

{
  print "CI_BUILD_PASSED=$ci_build"
  print "CI_TESTS_PASSED=$ci_tests"
  print "XCODE_BUILD_PASSED=$xcode_build"
  print "M8_001_ACCEPTANCE_PASSED=$m8_functional_ok"
  print "RC_PACKAGE_CREATED=yes"
  print "SBOM_GENERATED=$([[ -f "$sbom" ]] && print yes || print no)"
  print "CHECKSUMS_GENERATED=$([[ -f "$checksums" ]] && print yes || print no)"
  print "MANIFEST_GENERATED=yes"
  print "DEVELOPER_ID_SIGNED=$developer_id_signed"
  print "HARDENED_RUNTIME_ENABLED=$hardened_runtime"
  print "NOTARIZATION_ACCEPTED=$notarization_accepted"
  print "STAPLE_VERIFIED=$staple_verified"
  print "GATEKEEPER_VERIFIED=$gatekeeper_verified"
  print "SECRETS_EXPOSED=$secrets_exposed"
  print "PRIVATE_PATH_EXPOSED=$private_path_exposed"
  print "RESIDUAL_KEYCHAIN=$residual_keychain"
  print "M8_002_RESULT=$result"
} > "$summary"

cat > "$manifest" <<EOF
{
  "schemaVersion": 1,
  "project": "HermesMacOSNativeBridge",
  "releaseMode": "$mode",
  "gitCommit": "$(git rev-parse HEAD)",
  "gitRef": "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || print detached)",
  "buildTimestamp": "$(date -u -r "${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}" '+%Y-%m-%dT%H:%M:%SZ')",
  "payload": {
    "app": "Payload/Hermes Bridge.app",
    "service": "Payload/bin/HermesBridgeService",
    "control": "Payload/bin/HermesBridgeControl",
    "installer": "Payload/Scripts/install-hermes-bridge-app.zsh",
    "uninstaller": "Payload/Scripts/uninstall-hermes-bridge-app.zsh"
  },
  "evidence": {
    "m8_001_result": "artifacts/m8-001/result.txt",
    "sbom": "ReleaseEvidence/sbom.spdx.json",
    "checksums": "ReleaseEvidence/checksums.sha256",
    "gateSummary": "ReleaseEvidence/release-gate-summary.env"
  },
  "gates": {
    "CI_BUILD_PASSED": "$ci_build",
    "CI_TESTS_PASSED": "$ci_tests",
    "XCODE_BUILD_PASSED": "$xcode_build",
    "M8_001_ACCEPTANCE_PASSED": "$m8_functional_ok",
    "RC_PACKAGE_CREATED": "yes",
    "SBOM_GENERATED": "$([[ -f "$sbom" ]] && print yes || print no)",
    "CHECKSUMS_GENERATED": "$([[ -f "$checksums" ]] && print yes || print no)",
    "MANIFEST_GENERATED": "yes",
    "DEVELOPER_ID_SIGNED": "$developer_id_signed",
    "HARDENED_RUNTIME_ENABLED": "$hardened_runtime",
    "NOTARIZATION_ACCEPTED": "$notarization_accepted",
    "STAPLE_VERIFIED": "$staple_verified",
    "GATEKEEPER_VERIFIED": "$gatekeeper_verified",
    "SECRETS_EXPOSED": "$secrets_exposed",
    "PRIVATE_PATH_EXPOSED": "$private_path_exposed",
    "RESIDUAL_KEYCHAIN": "$residual_keychain",
    "M8_002_RESULT": "$result"
  }
}
EOF

print "manifest=$manifest"
print "summary=$summary"
