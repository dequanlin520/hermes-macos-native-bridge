#!/bin/zsh
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
artifact_root="$repo_root/artifacts/m8-002"
version="local-rc"
safe_version="local-rc"
rc_root="$artifact_root/release-candidates/HermesBridge-$safe_version"
staging_root="$rc_root/staging"
payload_root="$staging_root/Payload"
evidence_root="$staging_root/ReleaseEvidence"
archive="$rc_root/HermesBridge-$safe_version-unsigned-rc.tar.gz"
archive_checksum="$archive.sha256"
result_file="$artifact_root/result.txt"
validation_report="$artifact_root/local-validation-report.md"
m8_001_result="$repo_root/artifacts/m8-001/result.txt"

ci_workflow_yaml_passed="no"
release_candidate_workflow_yaml_passed="no"
release_workflow_yaml_passed="no"
release_script_syntax_passed="no"
m8_001_evidence_reused="no"
rc_package_created="no"
rc_archive_checksum_valid="no"
sbom_generated="no"
checksums_generated="no"
manifest_generated="no"
gate_summary_generated="no"
unsigned_rc_conditional="no"
release_verification_passed="no"
production_unsigned_release_rejected="no"
secrets_exposed="yes"
private_path_exposed="yes"
residual_keychain="yes"
residual_process="yes"
m8_002_result="FAIL"

mkdir -p "$artifact_root"

write_result() {
  {
    print "CI_WORKFLOW_YAML_PASSED=$ci_workflow_yaml_passed"
    print "RELEASE_CANDIDATE_WORKFLOW_YAML_PASSED=$release_candidate_workflow_yaml_passed"
    print "RELEASE_WORKFLOW_YAML_PASSED=$release_workflow_yaml_passed"
    print "RELEASE_SCRIPT_SYNTAX_PASSED=$release_script_syntax_passed"
    print "M8_001_EVIDENCE_REUSED=$m8_001_evidence_reused"
    print "RC_PACKAGE_CREATED=$rc_package_created"
    print "RC_ARCHIVE_CHECKSUM_VALID=$rc_archive_checksum_valid"
    print "SBOM_GENERATED=$sbom_generated"
    print "CHECKSUMS_GENERATED=$checksums_generated"
    print "MANIFEST_GENERATED=$manifest_generated"
    print "GATE_SUMMARY_GENERATED=$gate_summary_generated"
    print "UNSIGNED_RC_CONDITIONAL=$unsigned_rc_conditional"
    print "RELEASE_VERIFICATION_PASSED=$release_verification_passed"
    print "PRODUCTION_UNSIGNED_RELEASE_REJECTED=$production_unsigned_release_rejected"
    print "SECRETS_EXPOSED=$secrets_exposed"
    print "PRIVATE_PATH_EXPOSED=$private_path_exposed"
    print "RESIDUAL_KEYCHAIN=$residual_keychain"
    print "RESIDUAL_PROCESS=$residual_process"
    print "M8_002_RESULT=$m8_002_result"
  } > "$result_file"
}

write_report() {
  {
    print "# M8-002 Local Validation Report"
    print
    print -- "- staging: artifacts/m8-002/release-candidates/HermesBridge-$safe_version/staging"
    print -- "- archive: artifacts/m8-002/release-candidates/HermesBridge-$safe_version/HermesBridge-$safe_version-unsigned-rc.tar.gz"
    print -- "- archiveChecksum: artifacts/m8-002/release-candidates/HermesBridge-$safe_version/HermesBridge-$safe_version-unsigned-rc.tar.gz.sha256"
    print -- "- manifest: artifacts/m8-002/release-candidates/HermesBridge-$safe_version/staging/ReleaseEvidence/release-manifest.json"
    print -- "- sbom: artifacts/m8-002/release-candidates/HermesBridge-$safe_version/staging/ReleaseEvidence/sbom.spdx.json"
    print -- "- checksums: artifacts/m8-002/release-candidates/HermesBridge-$safe_version/staging/ReleaseEvidence/checksums.sha256"
    print -- "- gateSummary: artifacts/m8-002/release-candidates/HermesBridge-$safe_version/staging/ReleaseEvidence/release-gate-summary.env"
    print -- "- reusedM8_001: artifacts/m8-001/result.txt"
    print -- "- result: $m8_002_result"
  } > "$validation_report"
}

mark_generated_files() {
  [[ -f "$archive" ]] && rc_package_created="yes"
  if [[ -f "$archive_checksum" ]]; then
    (cd "$rc_root" && shasum -a 256 -c "$(basename "$archive_checksum")" >/dev/null 2>&1) && rc_archive_checksum_valid="yes"
  fi
  [[ -f "$evidence_root/sbom.spdx.json" ]] && sbom_generated="yes"
  [[ -f "$evidence_root/checksums.sha256" ]] && checksums_generated="yes"
  [[ -f "$evidence_root/release-manifest.json" ]] && manifest_generated="yes"
  [[ -f "$evidence_root/release-gate-summary.env" ]] && gate_summary_generated="yes"
}

normalize_archive_checksum() {
  [[ -f "$archive" ]] || return 1
  (cd "$rc_root" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive_checksum")")
}

cleanup_prior_m8_002_evidence() {
  rm -rf "$artifact_root/release-candidates" \
    "$artifact_root/logs" \
    "$artifact_root/toolchain.txt" \
    "$artifact_root/local-validation-report.md" \
    "$artifact_root/result.txt"
}

parse_workflows() {
  /usr/bin/ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ci.yml')" >/dev/null 2>&1 && ci_workflow_yaml_passed="yes"
  /usr/bin/ruby -e "require 'yaml'; YAML.load_file('.github/workflows/release-candidate.yml')" >/dev/null 2>&1 && release_candidate_workflow_yaml_passed="yes"
  /usr/bin/ruby -e "require 'yaml'; YAML.load_file('.github/workflows/release.yml')" >/dev/null 2>&1 && release_workflow_yaml_passed="yes"
}

check_shell_syntax() {
  local scripts=(
    "Scripts/release/build-release-candidate.zsh"
    "Scripts/release/package-release.zsh"
    "Scripts/release/generate-release-manifest.zsh"
    "Scripts/release/sign-release.zsh"
    "Scripts/release/notarize-release.zsh"
    "Scripts/release/verify-release.zsh"
    "Scripts/integration/m8-002-ci-release-pipeline.zsh"
  )
  local ok="yes"
  local script
  for script in "${scripts[@]}"; do
    zsh -n "$script" >/dev/null 2>&1 || ok="no"
  done
  release_script_syntax_passed="$ok"
}

stage_from_existing_build_outputs() {
  local app_binary="$repo_root/.build/out/Products/Debug/HermesBridgeApp"
  local service_binary="$repo_root/.build/out/Products/Release/HermesBridgeService"
  local control_binary="$repo_root/.build/out/Products/Release/HermesBridgeControl"
  local app_bundle="$payload_root/Hermes Bridge.app"

  [[ -x "$app_binary" && ! -L "$app_binary" ]] || return 1
  [[ -x "$service_binary" && ! -L "$service_binary" ]] || return 1
  [[ -x "$control_binary" && ! -L "$control_binary" ]] || return 1

  mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources" \
    "$payload_root/bin" "$payload_root/Docs" "$payload_root/Scripts" "$evidence_root"

  cp "$app_binary" "$app_bundle/Contents/MacOS/HermesBridgeApp" || return 1
  cp "$repo_root/Packaging/HermesBridgeApp/Info.plist" "$app_bundle/Contents/Info.plist" || return 1
  chmod 755 "$app_bundle/Contents/MacOS/HermesBridgeApp" || return 1

  cp "$service_binary" "$payload_root/bin/HermesBridgeService" || return 1
  cp "$control_binary" "$payload_root/bin/HermesBridgeControl" || return 1
  chmod 755 "$payload_root/bin/HermesBridgeService" "$payload_root/bin/HermesBridgeControl" || return 1

  cp "$repo_root/Scripts/native/install-hermes-bridge-app.zsh" "$payload_root/Scripts/install-hermes-bridge-app.zsh" || return 1
  cp "$repo_root/Scripts/native/uninstall-hermes-bridge-app.zsh" "$payload_root/Scripts/uninstall-hermes-bridge-app.zsh" || return 1
  chmod 755 "$payload_root/Scripts"/*.zsh || return 1

  cp "$repo_root/LICENSE" "$payload_root/LICENSE" || return 1
  cp "$repo_root/SECURITY.md" "$payload_root/SECURITY.md" || return 1
  cp "$repo_root/README.md" "$payload_root/Docs/README.md" || return 1
  cp "$repo_root/Docs/Packaging/SigningAndNotarization.md" "$payload_root/Docs/SigningAndNotarization.md" || return 1
  cp "$repo_root/Docs/Release/ReleasePipeline.md" "$payload_root/Docs/ReleasePipeline.md" || return 1
  cp "$repo_root/Docs/Release/ReleaseRunbook.md" "$payload_root/Docs/ReleaseRunbook.md" || return 1

  {
    print "{"
    print '  "schemaVersion": 1,'
    print '  "project": "HermesMacOSNativeBridge",'
    print '  "version": "local-rc",'
    print '  "signingMode": "adhoc",'
    print '  "sourceBuild": "existing-local-products",'
    print "  \"gitCommit\": \"$(git rev-parse HEAD)\""
    print "}"
  } > "$evidence_root/build-info.json"

  {
    xcodebuild -version
    swift --version
    sw_vers
    uname -a
  } > "$evidence_root/toolchain.txt" 2>/dev/null
}

scan_generated_evidence() {
  local secret_scan_root="$rc_root"
  local private_scan_root="$rc_root"

  secrets_exposed="no"
  private_path_exposed="no"

  if grep -R -I -n -E 'BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY|APPLE_APP_SPECIFIC_PASSWORD=.*[^}]|APPLE_DEVELOPER_ID_APPLICATION_PASSWORD=.*[^}]|APPLE_API_PRIVATE_KEY_BASE64=.*[^}]' "$secret_scan_root" "$validation_report" "$result_file" >/dev/null 2>&1; then
    secrets_exposed="yes"
  fi
  if grep -R -I -n -E '/Users/|/private/|/var/folders' "$private_scan_root" "$validation_report" "$result_file" >/dev/null 2>&1; then
    private_path_exposed="yes"
  fi
}

check_residual_resources() {
  residual_keychain="no"
  residual_process="no"

  if find "$artifact_root" \( -name '*.keychain' -o -name '*.keychain-db' \) -print | grep -q .; then
    residual_keychain="yes"
  fi
  if command -v security >/dev/null 2>&1 && security list-keychains -d user 2>/dev/null | grep -q 'hermes-release-signing-'; then
    residual_keychain="yes"
  fi
  if pgrep -f 'HermesBridge(Service|Control|App)' >/dev/null 2>&1; then
    residual_process="yes"
  fi
}

finalize_result() {
  local gate_result=""
  if [[ -f "$evidence_root/release-gate-summary.env" ]]; then
    gate_result="$(sed -n 's/^M8_002_RESULT=//p' "$evidence_root/release-gate-summary.env" | tail -n 1)"
  fi

  if [[ "$gate_result" == "CONDITIONAL" ]] &&
    [[ -f "$evidence_root/signing-report.env" ]] &&
    grep -q '^DEVELOPER_ID_SIGNED=no$' "$evidence_root/signing-report.env" &&
    grep -q '^SIGNING_MODE=adhoc$' "$evidence_root/signing-report.env"; then
    unsigned_rc_conditional="yes"
  fi

  if [[ "$ci_workflow_yaml_passed" == "yes" &&
    "$release_candidate_workflow_yaml_passed" == "yes" &&
    "$release_workflow_yaml_passed" == "yes" &&
    "$release_script_syntax_passed" == "yes" &&
    "$m8_001_evidence_reused" == "yes" &&
    "$rc_package_created" == "yes" &&
    "$rc_archive_checksum_valid" == "yes" &&
    "$sbom_generated" == "yes" &&
    "$checksums_generated" == "yes" &&
    "$manifest_generated" == "yes" &&
    "$gate_summary_generated" == "yes" &&
    "$unsigned_rc_conditional" == "yes" &&
    "$release_verification_passed" == "yes" &&
    "$production_unsigned_release_rejected" == "yes" &&
    "$secrets_exposed" == "no" &&
    "$private_path_exposed" == "no" &&
    "$residual_keychain" == "no" &&
    "$residual_process" == "no" ]]; then
    m8_002_result="CONDITIONAL"
  else
    m8_002_result="FAIL"
  fi
}

cd "$repo_root" || exit 1
cleanup_prior_m8_002_evidence
mkdir -p "$artifact_root"

parse_workflows
check_shell_syntax

if [[ -f "$m8_001_result" ]] && grep -q '^M8_001_RESULT=\(PASS\|CONDITIONAL\)$' "$m8_001_result"; then
  m8_001_evidence_reused="yes"
fi

if [[ "$m8_001_evidence_reused" == "yes" ]] && stage_from_existing_build_outputs; then
  Scripts/release/sign-release.zsh --staging-root "$staging_root" --mode adhoc >/dev/null 2>&1
  Scripts/release/package-release.zsh --staging-root "$staging_root" --version "$version" --mode adhoc >/dev/null 2>&1
  normalize_archive_checksum
  Scripts/release/notarize-release.zsh --archive "$archive" --staging-root "$staging_root" --mode rc >/dev/null 2>&1
  Scripts/release/generate-release-manifest.zsh --staging-root "$staging_root" --mode rc --acceptance-result "$m8_001_result" >/dev/null 2>&1
  Scripts/release/package-release.zsh --staging-root "$staging_root" --version "$version" --mode adhoc >/dev/null 2>&1
  normalize_archive_checksum

  if (cd "$rc_root" && "$repo_root/Scripts/release/verify-release.zsh" --staging-root "$staging_root" --archive "$archive" --mode rc >/dev/null 2>&1); then
    release_verification_passed="yes"
  fi
  if ! (cd "$rc_root" && "$repo_root/Scripts/release/verify-release.zsh" --staging-root "$staging_root" --archive "$archive" --mode production >/dev/null 2>&1); then
    production_unsigned_release_rejected="yes"
  fi
fi

mark_generated_files
write_report
write_result
scan_generated_evidence
check_residual_resources
finalize_result
write_report
write_result

case "$m8_002_result" in
  PASS|CONDITIONAL)
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
