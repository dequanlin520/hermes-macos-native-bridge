#!/bin/zsh
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
artifact_root="$repo_root/artifacts/m8-003"
download_root="$artifact_root/downloaded-artifacts"
result_file="$artifact_root/result.txt"
validation_report="$artifact_root/validation-report.md"
artifact_inventory="$artifact_root/artifact-inventory.txt"
workflow_discovery="$artifact_root/workflow-discovery.json"
ci_run_json="$artifact_root/ci-run.json"
rc_run_json="$artifact_root/rc-run.json"
ci_run_url_file="$artifact_root/ci-run-url.txt"
rc_run_url_file="$artifact_root/rc-run-url.txt"

expected_repo="dequanlin520/hermes-macos-native-bridge"
branch="feature/m8-003-github-actions-rehearsal"
ci_workflow_path=".github/workflows/ci.yml"
rc_workflow_path=".github/workflows/release-candidate.yml"
ci_workflow_file="ci.yml"
rc_workflow_file="release-candidate.yml"
timeout_seconds="${M8_003_TIMEOUT_SECONDS:-5400}"
poll_seconds="${M8_003_POLL_SECONDS:-20}"

gh_authenticated="no"
repository_verified="no"
ci_workflow_triggered="no"
ci_run_completed="no"
ci_run_success="no"
rc_workflow_triggered="no"
rc_run_completed="no"
rc_run_success="no"
rc_artifact_downloaded="no"
rc_archive_present="no"
rc_archive_checksum_valid="no"
rc_manifest_valid="no"
rc_sbom_valid="no"
rc_gate_summary_valid="no"
unsigned_rc_conditional="no"
developer_id_falsely_passed="no"
notarization_falsely_passed="no"
github_release_published="no"
token_exposed="yes"
private_path_exposed="yes"
residual_gh_process="yes"
m8_003_result="FAIL"

ci_run_id=""
rc_run_id=""
ci_run_url=""
rc_run_url=""
release_before_file="$artifact_root/github-releases-before.json"
release_after_file="$artifact_root/github-releases-after.json"

usage() {
  print -u2 "usage: m8-003-github-actions-rehearsal.zsh"
}

log() {
  print -- "m8-003: $*"
}

now_seconds() {
  date -u +%s
}

write_result() {
  {
    print "GH_AUTHENTICATED=$gh_authenticated"
    print "REPOSITORY_VERIFIED=$repository_verified"
    print "CI_WORKFLOW_TRIGGERED=$ci_workflow_triggered"
    print "CI_RUN_COMPLETED=$ci_run_completed"
    print "CI_RUN_SUCCESS=$ci_run_success"
    print "RC_WORKFLOW_TRIGGERED=$rc_workflow_triggered"
    print "RC_RUN_COMPLETED=$rc_run_completed"
    print "RC_RUN_SUCCESS=$rc_run_success"
    print "RC_ARTIFACT_DOWNLOADED=$rc_artifact_downloaded"
    print "RC_ARCHIVE_PRESENT=$rc_archive_present"
    print "RC_ARCHIVE_CHECKSUM_VALID=$rc_archive_checksum_valid"
    print "RC_MANIFEST_VALID=$rc_manifest_valid"
    print "RC_SBOM_VALID=$rc_sbom_valid"
    print "RC_GATE_SUMMARY_VALID=$rc_gate_summary_valid"
    print "UNSIGNED_RC_CONDITIONAL=$unsigned_rc_conditional"
    print "DEVELOPER_ID_FALSELY_PASSED=$developer_id_falsely_passed"
    print "NOTARIZATION_FALSELY_PASSED=$notarization_falsely_passed"
    print "GITHUB_RELEASE_PUBLISHED=$github_release_published"
    print "TOKEN_EXPOSED=$token_exposed"
    print "PRIVATE_PATH_EXPOSED=$private_path_exposed"
    print "RESIDUAL_GH_PROCESS=$residual_gh_process"
    print "M8_003_RESULT=$m8_003_result"
  } > "$result_file"
}

sanitize_file() {
  local input="$1"
  local output="$2"
  sed -E \
    -e 's/(gh[opusr]_|github_pat_)[A-Za-z0-9_]+/<redacted-token>/g' \
    -e 's/[Bb]earer[[:space:]]+[A-Za-z0-9._~+\/=-]+/Bearer <redacted-token>/g' \
    -e 's#/Users/[^[:space:]"'\''`<>]+#<redacted-path>#g' \
    -e 's#/private/[^[:space:]"'\''`<>]+#<redacted-path>#g' \
    -e 's#/var/folders/[^[:space:]"'\''`<>]+#<redacted-path>#g' \
    "$input" > "$output"
}

record_failure_log() {
  local run_id="$1"
  local output="$2"
  local tmp="$artifact_root/.failed-log.$run_id.tmp"

  gh run view "$run_id" --repo "$expected_repo" --log-failed > "$tmp" 2>&1 || true
  sanitize_file "$tmp" "$output"
  rm -f "$tmp"
}

json_value() {
  local file="$1"
  local key="$2"
  ruby -rjson -e 'j=JSON.parse(File.read(ARGV[0])); v=j[ARGV[1]]; puts(v.nil? ? "" : v)' "$file" "$key"
}

discover_workflows() {
  ruby -ryaml -rjson -e '
    paths = ARGV
    out = paths.map do |path|
      raw = YAML.load_file(path)
      on = raw["on"] || raw[true] || {}
      has_dispatch = on.is_a?(Hash) && on.key?("workflow_dispatch")
      dispatch = has_dispatch ? on["workflow_dispatch"] : nil
      inputs = dispatch.is_a?(Hash) ? (dispatch["inputs"] || {}) : {}
      {
        path: path,
        name: raw["name"],
        workflow_dispatch: has_dispatch,
        workflow_dispatch_inputs: inputs.keys.sort
      }
    end
    puts JSON.pretty_generate(out)
  ' "$ci_workflow_path" "$rc_workflow_path" ".github/workflows/release.yml" > "$workflow_discovery" || return 1

  ruby -rjson -e '
    data = JSON.parse(File.read(ARGV[0]))
    missing = data.select { |w| [".github/workflows/ci.yml", ".github/workflows/release-candidate.yml"].include?(w["path"]) && !w["workflow_dispatch"] }
    exit(missing.empty? ? 0 : 1)
  ' "$workflow_discovery"
}

capture_release_list() {
  local output="$1"
  gh release list --repo "$expected_repo" --limit 100 --json tagName,name,isPrerelease,createdAt > "$output"
}

release_created_since_before() {
  ruby -rjson -e '
    before = JSON.parse(File.read(ARGV[0])).map { |r| r["tagName"] }.compact
    after = JSON.parse(File.read(ARGV[1])).map { |r| r["tagName"] }.compact
    exit((after - before).empty? ? 1 : 0)
  ' "$release_before_file" "$release_after_file"
}

run_ids() {
  local workflow_file="$1"
  gh run list \
    --repo "$expected_repo" \
    --workflow "$workflow_file" \
    --branch "$branch" \
    --event workflow_dispatch \
    --limit 20 \
    --json databaseId,url,status,conclusion,headBranch,headSha,createdAt
}

find_new_run_id() {
  local before_file="$1"
  local after_file="$2"
  ruby -rjson -e '
    before = JSON.parse(File.read(ARGV[0])).map { |r| r["databaseId"].to_s }
    after = JSON.parse(File.read(ARGV[1]))
    run = after.find { |r| !before.include?(r["databaseId"].to_s) }
    if run
      puts run["databaseId"]
    else
      exit 1
    end
  ' "$before_file" "$after_file"
}

capture_existing_run() {
  local run_id="$1"
  local output_json="$2"
  local url_var="$3"

  gh run view "$run_id" \
    --repo "$expected_repo" \
    --json databaseId,url,status,conclusion,workflowName,headBranch,headSha,event,createdAt,updatedAt \
    > "$output_json" || return 1
  local url
  url="$(json_value "$output_json" url)"
  typeset -g "$url_var=$url"
}

trigger_workflow() {
  local workflow_file="$1"
  local run_id_var="$2"
  local url_var="$3"
  local before_file="$artifact_root/${workflow_file%.yml}-runs-before.json"
  local after_file="$artifact_root/${workflow_file%.yml}-runs-after.json"
  local run_id=""

  run_ids "$workflow_file" > "$before_file" || return 1
  gh workflow run "$workflow_file" --repo "$expected_repo" --ref "$branch" || return 1

  local deadline=$(( $(now_seconds) + 180 ))
  while (( $(now_seconds) < deadline )); do
    sleep 5
    run_ids "$workflow_file" > "$after_file" || continue
    run_id="$(find_new_run_id "$before_file" "$after_file" 2>/dev/null || true)"
    if [[ -n "$run_id" ]]; then
      typeset -g "$run_id_var=$run_id"
      local url
      url="$(ruby -rjson -e '
        id = ARGV[1]
        run = JSON.parse(File.read(ARGV[0])).find { |r| r["databaseId"].to_s == id }
        puts(run ? run["url"] : "")
      ' "$after_file" "$run_id")"
      typeset -g "$url_var=$url"
      return 0
    fi
  done

  return 1
}

wait_for_run() {
  local run_id="$1"
  local output_json="$2"
  local completed_var="$3"
  local success_var="$4"
  local failure_log="$5"
  local deadline=$(( $(now_seconds) + timeout_seconds ))
  local run_status=""
  local conclusion=""

  while (( $(now_seconds) < deadline )); do
    gh run view "$run_id" \
      --repo "$expected_repo" \
      --json databaseId,url,status,conclusion,workflowName,headBranch,headSha,event,createdAt,updatedAt,jobs \
      > "$output_json" || return 1
    run_status="$(json_value "$output_json" status)"
    conclusion="$(json_value "$output_json" conclusion)"
    log "run $run_id status=$run_status conclusion=${conclusion:-none}"
    if [[ "$run_status" == "completed" ]]; then
      typeset -g "$completed_var=yes"
      if [[ "$conclusion" == "success" ]]; then
        typeset -g "$success_var=yes"
        return 0
      fi
      record_failure_log "$run_id" "$failure_log"
      return 1
    fi
    sleep "$poll_seconds"
  done

  gh run view "$run_id" \
    --repo "$expected_repo" \
    --json databaseId,url,status,conclusion,workflowName,headBranch,headSha,event,createdAt,updatedAt,jobs \
    > "$output_json" 2>/dev/null || true
  return 1
}

download_rc_artifacts() {
  rm -rf "$download_root"
  mkdir -p "$download_root"
  gh run download "$rc_run_id" --repo "$expected_repo" --dir "$download_root" || return 1
  find "$download_root" -type f | LC_ALL=C sort | sed "s#^$artifact_root/##" > "$artifact_inventory"
  rc_artifact_downloaded="yes"
}

validate_rc_artifacts() {
  local archives=("${(@f)$(find "$download_root" -type f -name '*unsigned-rc.tar.gz' | LC_ALL=C sort)}")
  [[ ${#archives[@]} -eq 1 ]] || return 1

  local archive="${archives[1]}"
  local checksum="$archive.sha256"
  local rc_root="${archive:h}"
  local staging="$rc_root/staging"
  local evidence="$staging/ReleaseEvidence"
  local manifest="$evidence/release-manifest.json"
  local sbom="$evidence/sbom.spdx.json"
  local gate_summary="$evidence/release-gate-summary.env"
  local expected actual gate_result

  rc_archive_present="yes"
  [[ -f "$checksum" ]] || return 1
  expected="$(awk '{print $1; exit}' "$checksum")"
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  if [[ -n "$expected" && "$expected" == "$actual" ]]; then
    rc_archive_checksum_valid="yes"
  else
    return 1
  fi

  if [[ -f "$manifest" ]] && ruby -rjson -e 'JSON.parse(File.read(ARGV[0]))' "$manifest" >/dev/null 2>&1; then
    rc_manifest_valid="yes"
  else
    return 1
  fi

  if [[ -f "$sbom" ]] && ruby -rjson -e 'JSON.parse(File.read(ARGV[0]))' "$sbom" >/dev/null 2>&1 && grep -q '"spdxVersion": "SPDX-2.3"' "$sbom"; then
    rc_sbom_valid="yes"
  else
    return 1
  fi

  if [[ -f "$gate_summary" ]] &&
    grep -q '^M8_002_RESULT=\(PASS\|CONDITIONAL\)$' "$gate_summary" &&
    grep -q '^DEVELOPER_ID_SIGNED=' "$gate_summary" &&
    grep -q '^NOTARIZATION_ACCEPTED=' "$gate_summary"; then
    rc_gate_summary_valid="yes"
  else
    return 1
  fi

  gate_result="$(sed -n 's/^M8_002_RESULT=//p' "$gate_summary" | tail -n 1)"
  if [[ "$gate_result" == "PASS" || "$gate_result" == "CONDITIONAL" ]]; then
    unsigned_rc_conditional="yes"
  fi

  if grep -q '^DEVELOPER_ID_SIGNED=yes$' "$gate_summary"; then
    developer_id_falsely_passed="yes"
  fi
  if grep -q '^NOTARIZATION_ACCEPTED=yes$' "$gate_summary"; then
    notarization_falsely_passed="yes"
  fi
}

scan_evidence() {
  token_exposed="no"
  private_path_exposed="no"

  if grep -R -I -n -E '(gh[opusr]_|github_pat_)[A-Za-z0-9_]+|[Bb]earer[[:space:]]+[A-Za-z0-9._~+/=-]+|BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY|APPLE_APP_SPECIFIC_PASSWORD=.*[^}]|APPLE_DEVELOPER_ID_APPLICATION_PASSWORD=.*[^}]|APPLE_API_PRIVATE_KEY_BASE64=.*[^}]' "$artifact_root" >/dev/null 2>&1; then
    token_exposed="yes"
  fi

  if grep -R -I -n -E '/Users/|/private/|/var/folders' "$artifact_root" >/dev/null 2>&1; then
    private_path_exposed="yes"
  fi
}

check_residual_gh_process() {
  residual_gh_process="no"
  if ps -axo comm=,args= | awk '$1 ~ /(^|\/)gh$/ && $0 ~ / run watch( |$)/ { found=1 } END { exit(found ? 0 : 1) }'; then
    residual_gh_process="yes"
  fi
}

write_report() {
  {
    print "# M8-003 GitHub-Hosted Rehearsal Validation"
    print
    print "## Workflow Runs"
    print
    print -- "- CI run: ${ci_run_id:-not-triggered}"
    print -- "- CI URL: ${ci_run_url:-not-captured}"
    print -- "- RC run: ${rc_run_id:-not-triggered}"
    print -- "- RC URL: ${rc_run_url:-not-captured}"
    print
    print "## Artifact Validation"
    print
    print -- "- RC artifact downloaded: $rc_artifact_downloaded"
    print -- "- unsigned RC archive present: $rc_archive_present"
    print -- "- archive checksum valid: $rc_archive_checksum_valid"
    print -- "- manifest valid: $rc_manifest_valid"
    print -- "- SPDX SBOM valid: $rc_sbom_valid"
    print -- "- release gate summary valid: $rc_gate_summary_valid"
    print -- "- unsigned RC gate acceptable: $unsigned_rc_conditional"
    print -- "- Developer ID falsely passed: $developer_id_falsely_passed"
    print -- "- notarization falsely passed: $notarization_falsely_passed"
    print
    print "## Publication And Cleanup"
    print
    print -- "- GitHub Release published: $github_release_published"
    print -- "- token exposed: $token_exposed"
    print -- "- private path exposed: $private_path_exposed"
    print -- "- residual gh run watch process: $residual_gh_process"
  } > "$validation_report"
}

finalize_result() {
  if [[ "$ci_run_success" == "yes" &&
    "$rc_run_success" == "yes" &&
    "$rc_artifact_downloaded" == "yes" &&
    "$rc_archive_present" == "yes" &&
    "$rc_archive_checksum_valid" == "yes" &&
    "$rc_manifest_valid" == "yes" &&
    "$rc_sbom_valid" == "yes" &&
    "$rc_gate_summary_valid" == "yes" &&
    "$unsigned_rc_conditional" == "yes" &&
    "$developer_id_falsely_passed" == "no" &&
    "$notarization_falsely_passed" == "no" &&
    "$github_release_published" == "no" &&
    "$token_exposed" == "no" &&
    "$private_path_exposed" == "no" &&
    "$residual_gh_process" == "no" ]]; then
    m8_003_result="CONDITIONAL"
  else
    m8_003_result="FAIL"
  fi
}

main() {
  if (( $# > 0 )); then
    usage
    return 64
  fi

  cd "$repo_root" || return 1
  rm -rf "$artifact_root"
  mkdir -p "$artifact_root" "$download_root"
  write_result

  if gh auth status >/dev/null 2>&1; then
    gh_authenticated="yes"
  else
    write_result
    return 1
  fi

  local repo
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  if [[ "$repo" == "$expected_repo" ]]; then
    repository_verified="yes"
  else
    write_result
    return 1
  fi

  discover_workflows || { write_result; return 1; }
  capture_release_list "$release_before_file" || { write_result; return 1; }

  if [[ -n "${M8_003_CI_RUN_ID:-}" ]]; then
    ci_run_id="$M8_003_CI_RUN_ID"
    ci_workflow_triggered="yes"
    capture_existing_run "$ci_run_id" "$ci_run_json" ci_run_url || { write_result; return 1; }
    print -- "$ci_run_url" > "$ci_run_url_file"
    log "resuming CI workflow_dispatch run $ci_run_id"
  else
    log "triggering CI workflow_dispatch on $branch"
    if trigger_workflow "$ci_workflow_file" ci_run_id ci_run_url; then
      ci_workflow_triggered="yes"
      print -- "$ci_run_url" > "$ci_run_url_file"
    else
      write_result
      return 1
    fi
  fi

  if ! wait_for_run "$ci_run_id" "$ci_run_json" ci_run_completed ci_run_success "$artifact_root/sanitized-ci-failure-log.txt"; then
    capture_release_list "$release_after_file" >/dev/null 2>&1 || true
    release_created_since_before && github_release_published="yes"
    scan_evidence
    check_residual_gh_process
    finalize_result
    write_report
    write_result
    return 1
  fi

  if [[ -n "${M8_003_RC_RUN_ID:-}" ]]; then
    rc_run_id="$M8_003_RC_RUN_ID"
    rc_workflow_triggered="yes"
    capture_existing_run "$rc_run_id" "$rc_run_json" rc_run_url || { write_result; return 1; }
    print -- "$rc_run_url" > "$rc_run_url_file"
    log "resuming RC workflow_dispatch run $rc_run_id"
  else
    log "triggering unsigned/ad-hoc RC workflow_dispatch on $branch"
    if trigger_workflow "$rc_workflow_file" rc_run_id rc_run_url; then
      rc_workflow_triggered="yes"
      print -- "$rc_run_url" > "$rc_run_url_file"
    else
      write_result
      return 1
    fi
  fi

  if ! wait_for_run "$rc_run_id" "$rc_run_json" rc_run_completed rc_run_success "$artifact_root/sanitized-rc-failure-log.txt"; then
    capture_release_list "$release_after_file" >/dev/null 2>&1 || true
    release_created_since_before && github_release_published="yes"
    scan_evidence
    check_residual_gh_process
    finalize_result
    write_report
    write_result
    return 1
  fi

  download_rc_artifacts || true
  validate_rc_artifacts || true

  capture_release_list "$release_after_file" || true
  if release_created_since_before; then
    github_release_published="yes"
  fi

  check_residual_gh_process
  scan_evidence
  finalize_result
  write_report
  write_result

  [[ "$m8_003_result" == "CONDITIONAL" || "$m8_003_result" == "PASS" ]]
}

main "$@"
