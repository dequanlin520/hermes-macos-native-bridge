#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
artifact_root="${repo_root}/artifacts/m6-004"
result_file="${artifact_root}/result.txt"
keychain_path="${artifact_root}/hermes-m6-004.keychain-db"
keychain_password="hermes-m6-004-local"

typeset -A result_values
result_keys=(
  ISOLATED_KEYCHAIN_CREATED
  EXPLICIT_ACCESS_SETUP_PASSED
  FIRST_SIGNATURE_PASSED
  SECOND_SIGNATURE_NONINTERACTIVE
  RESTART_SIGNATURE_NONINTERACTIVE
  LOCKED_KEYCHAIN_DETECTED
  UNLOCK_RECOVERY_PASSED
  INTERRUPTED_ROTATION_DETECTED
  ROTATION_RESUME_PASSED
  TRUST_ANCHOR_RECOVERY_PASSED
  PRIVATE_KEY_EXPORTED
  RELEASE_IDENTITY_VALIDATION_PASSED
  DEVELOPER_ID_AVAILABLE
  AUTHORIZATION_PROMPT_AFTER_SETUP
  PROMPT_EXPOSED
  TOKEN_EXPOSED
  ABSOLUTE_PATH_EXPOSED
  RESIDUAL_KEYCHAIN_FILE
  RESIDUAL_PROCESS
  M6_004_RESULT
)

for key in "${result_keys[@]}"; do
  result_values[$key]=no
done
result_values[PRIVATE_KEY_EXPORTED]=no
result_values[AUTHORIZATION_PROMPT_AFTER_SETUP]=no
result_values[PROMPT_EXPOSED]=no
result_values[TOKEN_EXPOSED]=no
result_values[ABSOLUTE_PATH_EXPOSED]=no
result_values[RESIDUAL_KEYCHAIN_FILE]=no
result_values[RESIDUAL_PROCESS]=no
result_values[M6_004_RESULT]=FAIL

write_results() {
  : > "$result_file"
  for key in "${result_keys[@]}"; do
    print -r -- "$key=${result_values[$key]}" >> "$result_file"
  done
}

original_keychains=("${(@f)$(security list-keychains -d user 2>/dev/null | sed 's/^ *"//;s/"$//')}")
original_default="$(security default-keychain -d user 2>/dev/null | sed 's/^ *"//;s/"$//' || true)"

cleanup() {
  if [[ -n "${original_default:-}" ]]; then
    security default-keychain -d user -s "$original_default" >/dev/null 2>&1 || true
  fi
  if (( ${#original_keychains[@]} > 0 )); then
    security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1 || true
  fi
  security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
  rm -f "$keychain_path" "${keychain_path}-db" >/dev/null 2>&1 || true
}
trap cleanup EXIT

rm -rf "$artifact_root"
mkdir -p "$artifact_root"

if security create-keychain -p "$keychain_password" "$keychain_path" >/dev/null 2>&1; then
  security set-keychain-settings -lut 21600 "$keychain_path" >/dev/null 2>&1 || true
  security unlock-keychain -p "$keychain_password" "$keychain_path" >/dev/null 2>&1
  security list-keychains -d user -s "$keychain_path" >/dev/null 2>&1
  security default-keychain -d user -s "$keychain_path" >/dev/null 2>&1
  result_values[ISOLATED_KEYCHAIN_CREATED]=yes
fi

swift build --product M6004AuditSigningOperationsFixture >/dev/null
fixture="${repo_root}/.build/debug/M6004AuditSigningOperationsFixture"
codesign --force --sign - --options runtime "$fixture" >/dev/null 2>&1 || true

audit_root="${artifact_root}/audit"
anchor_export="${artifact_root}/anchors"
mkdir -p "$audit_root" "$anchor_export"

if "$fixture" setup "$audit_root" >"${artifact_root}/setup.out" 2>"${artifact_root}/setup.err"; then
  grep -q '^SETUP=yes' "${artifact_root}/setup.out" \
    && result_values[EXPLICIT_ACCESS_SETUP_PASSED]=yes
fi

if "$fixture" sign "$audit_root" >"${artifact_root}/first.out" 2>"${artifact_root}/first.err"; then
  grep -q '^SIGNATURE=yes' "${artifact_root}/first.out" \
    && result_values[FIRST_SIGNATURE_PASSED]=yes
fi

if "$fixture" sign "$audit_root" >"${artifact_root}/second.out" 2>"${artifact_root}/second.err"; then
  grep -q '^SIGNATURE=yes' "${artifact_root}/second.out" \
    && result_values[SECOND_SIGNATURE_NONINTERACTIVE]=yes
fi

if "$fixture" sign "$audit_root" >"${artifact_root}/restart.out" 2>"${artifact_root}/restart.err"; then
  grep -q '^SIGNATURE=yes' "${artifact_root}/restart.out" \
    && result_values[RESTART_SIGNATURE_NONINTERACTIVE]=yes
fi

security lock-keychain "$keychain_path" >/dev/null 2>&1 || true
if ! "$fixture" sign "$audit_root" >"${artifact_root}/locked.out" 2>"${artifact_root}/locked.err"; then
  result_values[LOCKED_KEYCHAIN_DETECTED]=yes
fi
if "$fixture" status "$audit_root" >"${artifact_root}/locked-status.out" 2>/dev/null; then
  grep -q '^ACCESS_POLICY=locked' "${artifact_root}/locked-status.out" \
    && result_values[LOCKED_KEYCHAIN_DETECTED]=yes
fi

security unlock-keychain -p "$keychain_password" "$keychain_path" >/dev/null 2>&1 || true
if "$fixture" sign "$audit_root" >"${artifact_root}/unlock.out" 2>"${artifact_root}/unlock.err"; then
  grep -q '^SIGNATURE=yes' "${artifact_root}/unlock.out" \
    && result_values[UNLOCK_RECOVERY_PASSED]=yes
fi

if "$fixture" interrupt-rotation "$audit_root" >"${artifact_root}/interrupt.out" 2>&1; then
  grep -q '^INTERRUPTED=yes' "${artifact_root}/interrupt.out" \
    && result_values[INTERRUPTED_ROTATION_DETECTED]=yes
fi

if "$fixture" resume-rotation "$audit_root" >"${artifact_root}/resume.out" 2>&1; then
  grep -q '^ROTATION_RESUMED=yes' "${artifact_root}/resume.out" \
    && result_values[ROTATION_RESUME_PASSED]=yes
fi

if "$fixture" export-anchors "$audit_root" "$anchor_export" >"${artifact_root}/export.out" 2>&1; then
  [[ -s "${anchor_export}/audit-trust-anchors.json" ]] \
    && result_values[TRUST_ANCHOR_RECOVERY_PASSED]=yes
fi
import_root="${artifact_root}/imported-audit"
mkdir -p "$import_root"
if "$fixture" import-anchors "$import_root" "${anchor_export}/audit-trust-anchors.json" \
  >"${artifact_root}/import.out" 2>&1; then
  result_values[TRUST_ANCHOR_RECOVERY_PASSED]=yes
fi

if security export -k "$keychain_path" -t privKeys -o "${artifact_root}/private-key-export.bin" \
  >/dev/null 2>&1; then
  result_values[PRIVATE_KEY_EXPORTED]=yes
else
  rm -f "${artifact_root}/private-key-export.bin"
fi

if "$fixture" status "$audit_root" >"${artifact_root}/status.out" 2>&1; then
  grep -q '^RELEASE_VALIDATION=yes' "${artifact_root}/status.out" \
    && result_values[RELEASE_IDENTITY_VALIDATION_PASSED]=yes
  grep -q '^DEVELOPER_ID=yes' "${artifact_root}/status.out" \
    && result_values[DEVELOPER_ID_AVAILABLE]=yes
fi

scan_target="${artifact_root}/scan.txt"
find "$artifact_root" -type f \( -name '*.json' -o -name '*.jsonl' -o -name '*.txt' -o -name '*.out' -o -name '*.err' \) \
  ! -name 'scan.txt' ! -name 'result.txt' -print0 | xargs -0 cat > "$scan_target" 2>/dev/null || true

if grep -Eiq 'prompt|private prompt' "$scan_target"; then
  result_values[PROMPT_EXPOSED]=yes
fi
if grep -Eiq 'token|credential|secret' "$scan_target"; then
  result_values[TOKEN_EXPOSED]=yes
fi
if grep -Eq '/Users/[^[:space:]"]+' "$scan_target"; then
  result_values[ABSOLUTE_PATH_EXPOSED]=yes
fi

cleanup
trap - EXIT

if [[ -e "$keychain_path" || -e "${keychain_path}-db" ]]; then
  result_values[RESIDUAL_KEYCHAIN_FILE]=yes
fi
if pgrep -fl 'M6004AuditSigningOperationsFixture' >/dev/null 2>&1; then
  result_values[RESIDUAL_PROCESS]=yes
fi

operational_pass=no
if [[ "${result_values[ISOLATED_KEYCHAIN_CREATED]}" == yes \
  && "${result_values[EXPLICIT_ACCESS_SETUP_PASSED]}" == yes \
  && "${result_values[FIRST_SIGNATURE_PASSED]}" == yes \
  && "${result_values[SECOND_SIGNATURE_NONINTERACTIVE]}" == yes \
  && "${result_values[RESTART_SIGNATURE_NONINTERACTIVE]}" == yes \
  && "${result_values[LOCKED_KEYCHAIN_DETECTED]}" == yes \
  && "${result_values[UNLOCK_RECOVERY_PASSED]}" == yes \
  && "${result_values[INTERRUPTED_ROTATION_DETECTED]}" == yes \
  && "${result_values[ROTATION_RESUME_PASSED]}" == yes \
  && "${result_values[TRUST_ANCHOR_RECOVERY_PASSED]}" == yes \
  && "${result_values[PRIVATE_KEY_EXPORTED]}" == no \
  && "${result_values[AUTHORIZATION_PROMPT_AFTER_SETUP]}" == no \
  && "${result_values[PROMPT_EXPOSED]}" == no \
  && "${result_values[TOKEN_EXPOSED]}" == no \
  && "${result_values[ABSOLUTE_PATH_EXPOSED]}" == no \
  && "${result_values[RESIDUAL_KEYCHAIN_FILE]}" == no \
  && "${result_values[RESIDUAL_PROCESS]}" == no ]]; then
  operational_pass=yes
fi

if [[ "$operational_pass" == yes && "${result_values[RELEASE_IDENTITY_VALIDATION_PASSED]}" == yes ]]; then
  result_values[M6_004_RESULT]=PASS
elif [[ "$operational_pass" == yes && "${result_values[DEVELOPER_ID_AVAILABLE]}" == no ]]; then
  result_values[M6_004_RESULT]=PARTIAL
fi

write_results
cat "$result_file"
