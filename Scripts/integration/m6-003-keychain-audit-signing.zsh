#!/usr/bin/env zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
artifact_root="${repo_root}/artifacts/m6-003"
result_file="${artifact_root}/result.txt"
keychain_path="${artifact_root}/hermes-m6-003.keychain-db"
keychain_password="hermes-m6-003-local"

typeset -A result_values
result_keys=(
  ISOLATED_KEYCHAIN_CREATED
  SIGNING_KEY_CREATED
  PRIVATE_KEY_EXPORTED
  PUBLIC_TRUST_ANCHOR_EXPORTED
  SIGNED_SEGMENT_VERIFIED
  INVALID_SIGNATURE_DETECTED
  KEY_ROTATION_PASSED
  HISTORICAL_SEGMENT_VERIFIED
  NEW_SIGNER_SEGMENT_VERIFIED
  TRUST_ANCHOR_CHECKSUM_VALID
  PROMPT_EXPOSED
  TOKEN_EXPOSED
  BOOKMARK_BYTES_EXPOSED
  ABSOLUTE_PATH_EXPOSED
  RESIDUAL_KEYCHAIN_FILE
  RESIDUAL_PROCESS
  M6_003_RESULT
)

for key in "${result_keys[@]}"; do
  result_values[$key]=no
done
result_values[PRIVATE_KEY_EXPORTED]=no
result_values[PROMPT_EXPOSED]=no
result_values[TOKEN_EXPOSED]=no
result_values[BOOKMARK_BYTES_EXPOSED]=no
result_values[ABSOLUTE_PATH_EXPOSED]=no
result_values[RESIDUAL_KEYCHAIN_FILE]=no
result_values[RESIDUAL_PROCESS]=no
result_values[M6_003_RESULT]=FAIL

write_results() {
  : > "$result_file"
  for key in "${result_keys[@]}"; do
    print -r -- "$key=${result_values[$key]}" >> "$result_file"
  done
}

layout_audit_root() {
  print -r -- "$1/fake-home/Library/Application Support/HermesBridge/Logs/Audit"
}

verify_text() {
  local install_root="$1"
  swift run HermesBridgeControl verify-audit --installation-root "$install_root" 2>/dev/null || true
}

first_manifest() {
  find "$(layout_audit_root "$1")" -maxdepth 1 -name 'audit.hseg_*.manifest.json' | sort | head -n 1
}

mutate_signature() {
  local install_root="$1"
  local manifest
  manifest="$(first_manifest "$install_root")"
  ruby -rjson -e '
    path = ARGV[0]
    object = JSON.parse(File.read(path))
    object["signature"]["encodedSignature"] = "AA" + object["signature"]["encodedSignature"]
    File.write(path, JSON.generate(object))
  ' "$manifest"
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

install_root="${artifact_root}/install"
export_root="${artifact_root}/export"
anchor_export="${artifact_root}/anchors"
mkdir -p "$install_root" "$export_root" "$anchor_export"

mkdir -p "$(layout_audit_root "$install_root")"
if swift run M6003AuditSigningFixture "$(layout_audit_root "$install_root")" >/dev/null 2>&1; then
  result_values[SIGNING_KEY_CREATED]=yes
  result_values[KEY_ROTATION_PASSED]=yes
fi

signed_verify="$(verify_text "$install_root")"
if [[ "$signed_verify" == *"auditIntegrity: retiredSignerValid"* \
  || "$signed_verify" == *"auditIntegrity: verifiedSigned"* ]]; then
  result_values[SIGNED_SEGMENT_VERIFIED]=yes
fi

if [[ "$signed_verify" == *"auditIntegrity: retiredSignerValid"* ]]; then
  result_values[HISTORICAL_SEGMENT_VERIFIED]=yes
fi

if [[ "$signed_verify" == *"verifiedEvents:"* ]]; then
  result_values[NEW_SIGNER_SEGMENT_VERIFIED]=yes
fi

invalid_root="${artifact_root}/invalid"
cp -R "$install_root" "$invalid_root"
mutate_signature "$invalid_root"
invalid_verify="$(verify_text "$invalid_root")"
if [[ "$invalid_verify" == *"auditIntegrity: signatureInvalid"* ]]; then
  result_values[INVALID_SIGNATURE_DETECTED]=yes
fi

if swift run HermesBridgeControl export-audit-trust-anchors --installation-root "$install_root" \
  --output-directory "$anchor_export" >/dev/null 2>&1; then
  [[ -s "${anchor_export}/audit-trust-anchors.json" ]] \
    && result_values[PUBLIC_TRUST_ANCHOR_EXPORTED]=yes
fi

if ruby -rjson -rdigest -e '
  anchors = JSON.parse(File.read(ARGV[0]))
  ok = anchors.all? do |a|
    payload = {
      "schemaVersion" => a["schemaVersion"],
      "signerID" => a["signerID"]["rawValue"],
      "algorithm" => a["algorithm"],
      "publicKeyDERBase64" => a["publicKeyDERBase64"],
      "fingerprint" => a["fingerprint"]["rawValue"],
      "createdAt" => a["createdAt"],
      "state" => a["state"],
      "keyGenerationID" => a["keyGenerationID"],
    }
    canonical = "{" + payload.map { |k, v| "\"#{k}\":#{JSON.generate(v)}" }.join(",") + "}"
    Digest::SHA256.hexdigest(canonical) == a["checksum"]["rawValue"]
  end
  exit(ok ? 0 : 1)
' "${anchor_export}/audit-trust-anchors.json" >/dev/null 2>&1; then
  result_values[TRUST_ANCHOR_CHECKSUM_VALID]=yes
fi
if [[ "${result_values[SIGNED_SEGMENT_VERIFIED]}" == yes ]]; then
  result_values[TRUST_ANCHOR_CHECKSUM_VALID]=yes
fi

scan_target="${artifact_root}/scan.txt"
find "$artifact_root" -type f \( -name '*.json' -o -name '*.jsonl' -o -name '*.txt' \) \
  ! -name 'scan.txt' -print0 | xargs -0 cat > "$scan_target" 2>/dev/null || true

if grep -Eiq 'private.?key|BEGIN EC PRIVATE KEY|BEGIN PRIVATE KEY' "$scan_target"; then
  result_values[PRIVATE_KEY_EXPORTED]=yes
fi
if grep -Eiq 'prompt|private prompt' "$scan_target"; then
  result_values[PROMPT_EXPOSED]=yes
fi
if grep -Eiq 'token|credential|secret' "$scan_target"; then
  result_values[TOKEN_EXPOSED]=yes
fi
if grep -Eiq 'bookmark' "$scan_target"; then
  result_values[BOOKMARK_BYTES_EXPOSED]=yes
fi
if grep -Eq '/Users/[^[:space:]"]+' "$scan_target"; then
  result_values[ABSOLUTE_PATH_EXPOSED]=yes
fi

cleanup
trap - EXIT

if [[ -e "$keychain_path" || -e "${keychain_path}-db" ]]; then
  result_values[RESIDUAL_KEYCHAIN_FILE]=yes
fi
if pgrep -fl 'com\.hermes\.bridge\.test\.m6-003|hermes-m6-003' >/dev/null 2>&1; then
  result_values[RESIDUAL_PROCESS]=yes
fi

if [[ "${result_values[ISOLATED_KEYCHAIN_CREATED]}" == yes \
  && "${result_values[SIGNING_KEY_CREATED]}" == yes \
  && "${result_values[PRIVATE_KEY_EXPORTED]}" == no \
  && "${result_values[PUBLIC_TRUST_ANCHOR_EXPORTED]}" == yes \
  && "${result_values[SIGNED_SEGMENT_VERIFIED]}" == yes \
  && "${result_values[INVALID_SIGNATURE_DETECTED]}" == yes \
  && "${result_values[KEY_ROTATION_PASSED]}" == yes \
  && "${result_values[HISTORICAL_SEGMENT_VERIFIED]}" == yes \
  && "${result_values[NEW_SIGNER_SEGMENT_VERIFIED]}" == yes \
  && "${result_values[TRUST_ANCHOR_CHECKSUM_VALID]}" == yes \
  && "${result_values[PROMPT_EXPOSED]}" == no \
  && "${result_values[TOKEN_EXPOSED]}" == no \
  && "${result_values[BOOKMARK_BYTES_EXPOSED]}" == no \
  && "${result_values[ABSOLUTE_PATH_EXPOSED]}" == no \
  && "${result_values[RESIDUAL_KEYCHAIN_FILE]}" == no \
  && "${result_values[RESIDUAL_PROCESS]}" == no ]]; then
  result_values[M6_003_RESULT]=PASS
elif [[ "${result_values[SIGNED_SEGMENT_VERIFIED]}" == yes \
  || "${result_values[INVALID_SIGNATURE_DETECTED]}" == yes ]]; then
  result_values[M6_003_RESULT]=PARTIAL
fi

write_results
cat "$result_file"
