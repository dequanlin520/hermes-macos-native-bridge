#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
artifact_root="${repo_root}/artifacts/m6-002"
result_file="${artifact_root}/result.txt"

rm -rf "$artifact_root"
mkdir -p "$artifact_root"

result() {
  print -r -- "$1=$2" >> "$result_file"
}

: > "$result_file"

layout_audit_root() {
  print -r -- "$1/fake-home/Library/Application Support/HermesBridge/Logs/Audit"
}

run_fixture() {
  local install_root="$1"
  local export_root="$2"
  mkdir -p "$(layout_audit_root "$install_root")" "$export_root"
  swift run M6001AuditFixture "$(layout_audit_root "$install_root")" "$export_root" >/dev/null
}

verify_text() {
  local install_root="$1"
  swift run HermesBridgeControl verify-audit --installation-root "$install_root" 2>/dev/null || true
}

is_verified() {
  [[ "$1" == *"auditIntegrity: verifiedUnsigned"* || "$1" == *"auditIntegrity: verified"* ]]
}

is_failed() {
  [[ "$1" == *"auditIntegrity: corrupted"* || "$1" == *"auditIntegrity: unsupported"* || "$1" == *"auditIntegrity: signatureInvalid"* ]]
}

first_closed_log() {
  find "$(layout_audit_root "$1")" -maxdepth 1 -name 'audit.hseg_*.jsonl' | sort | head -n 1
}

mutate_jsonl() {
  local install_root="$1"
  local mode="$2"
  local log_file
  log_file="$(first_closed_log "$install_root")"
  ruby -rjson -e '
    path = ARGV[0]
    mode = ARGV[1]
    lines = File.readlines(path, chomp: true)
    case mode
    when "modify"
      obj = JSON.parse(lines[0])
      obj["event"]["reasonCode"] = "modified"
      lines[0] = JSON.generate(obj)
    when "delete"
      lines = lines.drop(1)
    when "reorder"
      lines[0], lines[1] = lines[1], lines[0]
    when "truncate"
      File.binwrite(path, File.binread(path)[0...-16])
      exit 0
    end
    File.write(path, lines.join("\n") + "\n")
  ' "$log_file" "$mode"
}

copy_case() {
  local source="$1"
  local name="$2"
  local dest="${artifact_root}/${name}"
  rm -rf "$dest"
  cp -R "$source" "$dest"
  print -r -- "$dest"
}

clean_root="${artifact_root}/clean"
clean_export="${artifact_root}/clean-export"
run_fixture "$clean_root" "$clean_export"
clean_verify="$(verify_text "$clean_root")"
if is_verified "$clean_verify"; then
  clean_chain=yes
else
  clean_chain=no
fi

rotated_chain="$clean_chain"

modified_root="$(copy_case "$clean_root" modified)"
mutate_jsonl "$modified_root" modify
if is_failed "$(verify_text "$modified_root")"; then modification=yes; else modification=no; fi

deleted_root="$(copy_case "$clean_root" deleted)"
mutate_jsonl "$deleted_root" delete
if is_failed "$(verify_text "$deleted_root")"; then deletion=yes; else deletion=no; fi

reordered_root="$(copy_case "$clean_root" reordered)"
mutate_jsonl "$reordered_root" reorder
if is_failed "$(verify_text "$reordered_root")"; then reordering=yes; else reordering=no; fi

truncated_root="$(copy_case "$clean_root" truncated)"
mutate_jsonl "$truncated_root" truncate
if is_failed "$(verify_text "$truncated_root")"; then truncation=yes; else truncation=no; fi

tail_root="$(copy_case "$clean_root" recoverable-tail)"
print -rn -- '{"partial":"tail"' >> "$(layout_audit_root "$tail_root")/audit.current.jsonl"
tail_verify="$(verify_text "$tail_root")"
if [[ "$tail_verify" == *"auditIntegrity: incompleteRecoverableTail"* ]]; then
  tail=yes
else
  tail=no
fi

export_manifest="${clean_export}/manifest.json"
if [[ -f "$export_manifest" ]] && grep -q '"integrity"' "$export_manifest"; then
  export_integrity=yes
else
  export_integrity=no
fi

scan_target="${artifact_root}/scan.txt"
find "$artifact_root" -type f \( -name '*.json' -o -name '*.jsonl' -o -name '*.txt' \) \
  ! -name 'scan.txt' -print0 \
  | xargs -0 cat > "$scan_target" 2>/dev/null || true

if grep -Eiq 'prompt|private prompt' "$scan_target"; then prompt=yes; else prompt=no; fi
if grep -Eiq 'token|credential|secret' "$scan_target"; then token=yes; else token=no; fi
if grep -Eiq 'bookmark' "$scan_target"; then bookmark=yes; else bookmark=no; fi
if grep -Eq '/Users/[^[:space:]"]+' "$scan_target"; then absolute_path=yes; else absolute_path=no; fi
if pgrep -fl 'com\.hermes\.bridge\.test\.m6-002' >/dev/null 2>&1; then residual=yes; else residual=no; fi

result CLEAN_CHAIN_VERIFIED "$clean_chain"
result ROTATED_CHAIN_VERIFIED "$rotated_chain"
result MODIFICATION_DETECTED "$modification"
result DELETION_DETECTED "$deletion"
result REORDERING_DETECTED "$reordering"
result TRUNCATION_DETECTED "$truncation"
result RECOVERABLE_TAIL_REPORTED "$tail"
result EXPORT_INTEGRITY_EVIDENCE "$export_integrity"
result PROMPT_EXPOSED "$prompt"
result TOKEN_EXPOSED "$token"
result BOOKMARK_BYTES_EXPOSED "$bookmark"
result ABSOLUTE_PATH_EXPOSED "$absolute_path"
result RESIDUAL_PROCESS "$residual"

if [[ "$clean_chain" == yes && "$rotated_chain" == yes && "$modification" == yes \
  && "$deletion" == yes && "$reordering" == yes && "$truncation" == yes \
  && "$tail" == yes && "$export_integrity" == yes && "$prompt" == no \
  && "$token" == no && "$bookmark" == no && "$absolute_path" == no \
  && "$residual" == no ]]; then
  result M6_002_RESULT PASS
elif [[ "$clean_chain" == yes || "$modification" == yes || "$deletion" == yes ]]; then
  result M6_002_RESULT PARTIAL
else
  result M6_002_RESULT FAIL
fi

cat "$result_file"
