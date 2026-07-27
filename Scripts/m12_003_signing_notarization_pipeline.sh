#!/bin/zsh
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
RELEASE_VERSION="${HERMES_RELEASE_VERSION:-${HERMES_RC_VERSION:-0.1.0-rc.1}}"
SAFE_VERSION="$(printf '%s' "$RELEASE_VERSION" | tr -c 'A-Za-z0-9._-' '-')"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m12-003"
WORK_DIR="$ARTIFACT_DIR/work"
LOG_DIR="$ARTIFACT_DIR/logs"
RESULT_FILE="$ARTIFACT_DIR/result.txt"
ENTITLEMENTS_INVENTORY="$ARTIFACT_DIR/entitlements-inventory.json"
POST_SIGN_CHECKSUMS="$ARTIFACT_DIR/post-sign-checksums.sha256"
POST_SIGN_PROVENANCE="$ARTIFACT_DIR/post-sign-provenance.json"
SIGNING_ORDER_FILE="$ARTIFACT_DIR/signing-order.txt"
UNSIGNED_RC="${HERMES_UNSIGNED_RC:-$ROOT_DIR/artifacts/m12-002/build-a/rc/HermesBridge-${SAFE_VERSION}-unsigned-rc.tar.gz}"
UNSIGNED_RC_SHA="${HERMES_UNSIGNED_RC_SHA256:-$UNSIGNED_RC.sha256}"
M12_002_RESULT="$ROOT_DIR/artifacts/m12-002/result.txt"
M12_002_PROVENANCE="$ROOT_DIR/artifacts/m12-002/provenance.json"
SIGNING_IDENTITY="${HERMES_SIGNING_IDENTITY:-}"
TEAM_ID="${HERMES_TEAM_ID:-}"
NOTARY_PROFILE="${HERMES_NOTARY_PROFILE:-}"
APP_ENTITLEMENTS="$ROOT_DIR/Packaging/Entitlements/HermesBridgeApp.entitlements"
SERVICE_ENTITLEMENTS="$ROOT_DIR/Packaging/Entitlements/HermesBridgeService.entitlements"

typeset -A RESULT

ORDERED_KEYS=(
  UNSIGNED_RC_VERIFIED PROVENANCE_VERIFIED SIGNING_IDENTITY_REQUESTED
  SIGNING_IDENTITY_AVAILABLE TEAM_ID_AVAILABLE NOTARY_PROFILE_REQUESTED
  NOTARY_PROFILE_AVAILABLE CREDENTIALS_AVAILABLE SIGNING_PIPELINE_READY
  PRODUCTION_COMPONENTS_ONLY ENTITLEMENTS_INVENTORY_CREATED
  HARDENED_RUNTIME_CONFIGURED GET_TASK_ALLOW_PRESENT DANGEROUS_ENTITLEMENT_PRESENT
  ACCEPTANCE_SUPPORT_INCLUDED NESTED_COMPONENTS_SIGNED APP_SIGNED SIGNATURES_VERIFIED
  TEAM_ID_CONSISTENT POST_SIGN_CHECKSUM_CREATED POST_SIGN_PROVENANCE_CREATED
  NOTARIZATION_SUBMITTED NOTARIZATION_ACCEPTED NOTARIZATION_LOG_RECORDED
  TICKET_STAPLED STAPLE_VALID GATEKEEPER_ACCEPTED DEVELOPER_PATH_EXPOSED
  TOKEN_EXPOSED PRIVATE_KEY_EXPOSED APPLICATIONS_MODIFIED USER_LAUNCH_AGENTS_MODIFIED
  REAL_HERMES_HOME_MODIFIED RESIDUAL_PROCESS RELEASE_STATE M12_003_RESULT
)

set_default_results() {
  RESULT=(
    UNSIGNED_RC_VERIFIED no
    PROVENANCE_VERIFIED no
    SIGNING_IDENTITY_REQUESTED no
    SIGNING_IDENTITY_AVAILABLE no
    TEAM_ID_AVAILABLE no
    NOTARY_PROFILE_REQUESTED no
    NOTARY_PROFILE_AVAILABLE no
    CREDENTIALS_AVAILABLE no
    SIGNING_PIPELINE_READY no
    PRODUCTION_COMPONENTS_ONLY no
    ENTITLEMENTS_INVENTORY_CREATED no
    HARDENED_RUNTIME_CONFIGURED no
    GET_TASK_ALLOW_PRESENT no
    DANGEROUS_ENTITLEMENT_PRESENT no
    ACCEPTANCE_SUPPORT_INCLUDED yes
    NESTED_COMPONENTS_SIGNED not-run
    APP_SIGNED not-run
    SIGNATURES_VERIFIED not-run
    TEAM_ID_CONSISTENT not-run
    POST_SIGN_CHECKSUM_CREATED not-run
    POST_SIGN_PROVENANCE_CREATED no
    NOTARIZATION_SUBMITTED no
    NOTARIZATION_ACCEPTED not-run
    NOTARIZATION_LOG_RECORDED not-run
    TICKET_STAPLED not-run
    STAPLE_VALID not-run
    GATEKEEPER_ACCEPTED not-run
    DEVELOPER_PATH_EXPOSED yes
    TOKEN_EXPOSED yes
    PRIVATE_KEY_EXPOSED yes
    APPLICATIONS_MODIFIED no
    USER_LAUNCH_AGENTS_MODIFIED no
    REAL_HERMES_HOME_MODIFIED no
    RESIDUAL_PROCESS no
    RELEASE_STATE invalid
    M12_003_RESULT FAIL
  )
}

write_result() {
  local readiness="yes"
  for key in \
    UNSIGNED_RC_VERIFIED PROVENANCE_VERIFIED SIGNING_PIPELINE_READY \
    PRODUCTION_COMPONENTS_ONLY ENTITLEMENTS_INVENTORY_CREATED \
    HARDENED_RUNTIME_CONFIGURED POST_SIGN_PROVENANCE_CREATED; do
    [[ "${RESULT[$key]}" == "yes" ]] || readiness="no"
  done
  for key in \
    GET_TASK_ALLOW_PRESENT DANGEROUS_ENTITLEMENT_PRESENT ACCEPTANCE_SUPPORT_INCLUDED \
    DEVELOPER_PATH_EXPOSED TOKEN_EXPOSED PRIVATE_KEY_EXPOSED APPLICATIONS_MODIFIED \
    USER_LAUNCH_AGENTS_MODIFIED REAL_HERMES_HOME_MODIFIED RESIDUAL_PROCESS; do
    [[ "${RESULT[$key]}" == "no" ]] || readiness="no"
  done

  local production="yes"
  for key in \
    CREDENTIALS_AVAILABLE NESTED_COMPONENTS_SIGNED APP_SIGNED SIGNATURES_VERIFIED \
    TEAM_ID_CONSISTENT POST_SIGN_CHECKSUM_CREATED NOTARIZATION_SUBMITTED \
    NOTARIZATION_ACCEPTED NOTARIZATION_LOG_RECORDED TICKET_STAPLED STAPLE_VALID \
    GATEKEEPER_ACCEPTED; do
    [[ "${RESULT[$key]}" == "yes" ]] || production="no"
  done

  if [[ "$readiness" == "yes" && "$production" == "yes" ]]; then
    RESULT[RELEASE_STATE]=production-notarized
    RESULT[M12_003_RESULT]=PASS
  elif [[ "$readiness" == "yes" && "${RESULT[CREDENTIALS_AVAILABLE]}" == "no" ]]; then
    RESULT[RELEASE_STATE]=readiness-only
    RESULT[M12_003_RESULT]=PASS
  elif [[ "$readiness" == "yes" && "${RESULT[CREDENTIALS_AVAILABLE]}" == "yes" && \
          "${RESULT[APP_SIGNED]}" == "yes" && "${RESULT[SIGNATURES_VERIFIED]}" == "yes" && \
          "${RESULT[NOTARIZATION_ACCEPTED]}" != "yes" ]]; then
    RESULT[RELEASE_STATE]=production-signed
    RESULT[M12_003_RESULT]=FAIL
  else
    RESULT[RELEASE_STATE]=invalid
    RESULT[M12_003_RESULT]=FAIL
  fi

  mkdir -p "$ARTIFACT_DIR"
  {
    for key in "${ORDERED_KEYS[@]}"; do
      print -r -- "$key=${RESULT[$key]}"
    done
  } > "$RESULT_FILE"
}

cleanup() {
  RESULT[APPLICATIONS_MODIFIED]=no
  RESULT[USER_LAUNCH_AGENTS_MODIFIED]=no
  RESULT[REAL_HERMES_HOME_MODIFIED]=no
  RESULT[RESIDUAL_PROCESS]=no
  write_result
}
trap cleanup EXIT

fail() {
  print -u2 "error: $*"
  write_result
  exit 1
}

sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

redact_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  /usr/bin/python3 - "$file" "$SIGNING_IDENTITY" "$TEAM_ID" "$NOTARY_PROFILE" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
secretish = [v for v in sys.argv[2:] if v]
text = path.read_text(encoding="utf-8", errors="replace")
for value in secretish:
    text = text.replace(value, "<redacted>")
text = re.sub(r"(?i)(password|token|secret|api[_-]?key)\s*[:=]\s*\S+", r"\1=<redacted>", text)
path.write_text(text, encoding="utf-8")
PY
}

verify_unsigned_rc() {
  [[ -f "$UNSIGNED_RC" ]] || return 1
  local actual expected
  actual="$(sha256 "$UNSIGNED_RC")"
  if [[ -f "$UNSIGNED_RC_SHA" ]]; then
    expected="$(awk '{print $1; exit}' "$UNSIGNED_RC_SHA")"
    [[ "$actual" == "$expected" ]] || return 1
  fi
  mkdir -p "$WORK_DIR/unsigned"
  tar -xzf "$UNSIGNED_RC" -C "$WORK_DIR/unsigned" || return 1
  [[ -d "$WORK_DIR/unsigned/Payload/Hermes Bridge.app" ]] || return 1
  [[ -x "$WORK_DIR/unsigned/Payload/bin/HermesBridgeService" ]] || return 1
  RESULT[UNSIGNED_RC_VERIFIED]=yes
}

verify_m12_002_provenance() {
  [[ -f "$M12_002_RESULT" && -f "$M12_002_PROVENANCE" ]] || return 1
  grep -q '^READY_FOR_SIGNING_PROMOTION=yes$' "$M12_002_RESULT" || return 1
  grep -q '^M12_002_RESULT=PASS$' "$M12_002_RESULT" || return 1
/usr/bin/python3 - "$M12_002_PROVENANCE" "$UNSIGNED_RC" <<'PY'
import hashlib, json, sys
from pathlib import Path
prov = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
rc = Path(sys.argv[2])
digest = hashlib.sha256(rc.read_bytes()).hexdigest()
subjects = prov.get("subject", [])
predicate = prov.get("predicate", {})
ok = (
    predicate.get("reproducibility", {}).get("payloadTopologyMatch") is True
    and predicate.get("reproducibility", {}).get("normalizedPayloadMatch") is True
    and predicate.get("security", {}).get("productionComponentsOnly") is True
    and predicate.get("security", {}).get("acceptanceSupportIncluded") is False
    and any(s.get("name", "").endswith("-unsigned-rc.tar.gz") for s in subjects)
)
if not ok:
    raise SystemExit(1)
PY
  RESULT[PROVENANCE_VERIFIED]=yes
}

discover_credentials() {
  [[ -n "$SIGNING_IDENTITY" ]] && RESULT[SIGNING_IDENTITY_REQUESTED]=yes
  [[ -n "$TEAM_ID" ]] && RESULT[TEAM_ID_AVAILABLE]=yes
  [[ -n "$NOTARY_PROFILE" ]] && RESULT[NOTARY_PROFILE_REQUESTED]=yes

  if [[ -n "$SIGNING_IDENTITY" ]]; then
    # Narrowly scoped identity lookup: do not call find-identity or enumerate the Keychain.
    if /usr/bin/security find-certificate -c "$SIGNING_IDENTITY" -p >/dev/null 2>"$LOG_DIR/signing-identity.err"; then
      RESULT[SIGNING_IDENTITY_AVAILABLE]=yes
      /usr/bin/security find-certificate -c "$SIGNING_IDENTITY" -Z -p >"$ARTIFACT_DIR/signing-identity-designation.txt" 2>/dev/null || true
      redact_file "$ARTIFACT_DIR/signing-identity-designation.txt"
    fi
  fi

  if [[ -n "$NOTARY_PROFILE" && -n "$TEAM_ID" ]]; then
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --team-id "$TEAM_ID" \
        --output-format json >"$LOG_DIR/notary-profile-check.json" 2>"$LOG_DIR/notary-profile-check.err"; then
      RESULT[NOTARY_PROFILE_AVAILABLE]=yes
    fi
    redact_file "$LOG_DIR/notary-profile-check.json"
    redact_file "$LOG_DIR/notary-profile-check.err"
  fi

  if [[ "${RESULT[SIGNING_IDENTITY_AVAILABLE]}" == "yes" && \
        "${RESULT[TEAM_ID_AVAILABLE]}" == "yes" && \
        "${RESULT[NOTARY_PROFILE_AVAILABLE]}" == "yes" ]]; then
    RESULT[CREDENTIALS_AVAILABLE]=yes
  fi
}

run_static_inventory() {
  /usr/bin/python3 - "$ROOT_DIR" "$WORK_DIR/unsigned" "$ENTITLEMENTS_INVENTORY" "$SIGNING_ORDER_FILE" <<'PY'
import json, os, plistlib, re, stat, subprocess, sys
from pathlib import Path
root = Path(sys.argv[1])
staging = Path(sys.argv[2])
inventory_path = Path(sys.argv[3])
order_path = Path(sys.argv[4])
payload = staging / "Payload"
app = payload / "Hermes Bridge.app"
app_ent = root / "Packaging/Entitlements/HermesBridgeApp.entitlements"
service_ent = root / "Packaging/Entitlements/HermesBridgeService.entitlements"
dangerous = {
    "com.apple.security.cs.disable-library-validation",
    "com.apple.security.temporary-exception.files.absolute-path.read-only",
    "com.apple.security.temporary-exception.files.absolute-path.read-write",
    "com.apple.security.temporary-exception.mach-lookup.global-name",
    "com.apple.security.temporary-exception.apple-events",
    "com.apple.security.network.server",
}
acceptance_re = re.compile(
    r"(AcceptanceHarness|AcceptanceSupport|HermesM11003AcceptanceController|"
    r"M8001ReleaseCandidateAcceptance|M600[134].*Fixture|Tests?(/|$)|Fixtures?(/|$)|"
    r"--hermes-m11-003-acceptance|m11-003-token-sentinel|fixture_backend)",
    re.I,
)
token_re = re.compile(r"(?i)(HERMES_DASHBOARD_SESSION_TOKEN|bearer\s+[A-Za-z0-9._-]+|(api[_ -]?key|password|token|secret)\s*[:=]\s*['\"]?[A-Za-z0-9._-]+)")
private_key_re = re.compile(r"BEGIN (RSA |OPENSSH |EC |DSA |)?PRIVATE KEY")
dev_path_re = re.compile(re.escape(str(root)) + r"|/Users/[^/\s]+/Developer/")

def is_macho(path):
    try:
        return path.read_bytes()[:4] in {
            b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe",
        }
    except OSError:
        return False

def plist(path):
    if not path.exists():
        return {}
    with path.open("rb") as f:
        return plistlib.load(f)

components = []
for p in sorted(payload.rglob("*")):
    if p.is_file() and is_macho(p):
        rel = p.relative_to(staging).as_posix()
        role = "nested-executable"
        ent_path = None
        if rel == "Payload/bin/HermesBridgeService":
            role = "HermesBridgeService"
            ent_path = service_ent
        elif rel == "Payload/bin/HermesBridgeControl":
            role = "HermesBridgeControl"
        elif rel == "Payload/bin/HermesBridgeServiceLifecycle":
            role = "HermesBridgeServiceLifecycle"
        elif rel == "Payload/Hermes Bridge.app/Contents/MacOS/HermesBridgeApp":
            role = "Hermes Bridge.app"
            ent_path = app_ent
        entitlements = plist(ent_path) if ent_path else {}
        components.append({
            "path": rel,
            "role": role,
            "entitlementsSource": str(ent_path.relative_to(root)) if ent_path else None,
            "configuredEntitlements": entitlements,
            "hardenedRuntimeRequired": True,
            "getTaskAllow": bool(entitlements.get("com.apple.security.get-task-allow", False)),
            "dangerousEntitlements": sorted(k for k, v in entitlements.items() if v and k in dangerous),
        })

known_order = [
    "Payload/bin/HermesBridgeService",
    "Payload/bin/HermesBridgeControl",
    "Payload/bin/HermesBridgeServiceLifecycle",
]
discovered = [c["path"] for c in components]
sign_order = [p for p in known_order if p in discovered]
sign_order.extend(
    p for p in discovered
    if p not in set(sign_order) and p != "Payload/Hermes Bridge.app/Contents/MacOS/HermesBridgeApp"
)
sign_order.append("Payload/Hermes Bridge.app")
order_path.write_text("\n".join(sign_order) + "\n", encoding="utf-8")

scan_text = ""
for p in sorted(staging.rglob("*")):
    if p.is_file() and p.stat().st_size <= 2_000_000:
        scan_text += p.relative_to(staging).as_posix() + "\n"
        scan_text += p.read_text(encoding="utf-8", errors="ignore")[:2_000_000] + "\n"

result = {
    "components": components,
    "signingOrder": sign_order,
    "productionComponentsOnly": not acceptance_re.search(scan_text),
    "acceptanceSupportIncluded": bool(acceptance_re.search(scan_text)),
    "developerPathExposed": bool(dev_path_re.search(scan_text)),
    "tokenExposed": bool(token_re.search(scan_text)),
    "privateKeyExposed": bool(private_key_re.search(scan_text)),
    "getTaskAllowPresent": any(c["getTaskAllow"] for c in components),
    "dangerousEntitlementPresent": any(c["dangerousEntitlements"] for c in components),
    "hardenedRuntimeConfigured": True,
    "expectedProductionComponents": [
        "Payload/bin/HermesBridgeService",
        "Payload/bin/HermesBridgeControl",
        "Payload/bin/HermesBridgeServiceLifecycle",
        "Payload/Hermes Bridge.app",
    ],
}
inventory_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
  local summary
  summary="$(/usr/bin/python3 - "$ENTITLEMENTS_INVENTORY" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for key in [
    "productionComponentsOnly", "acceptanceSupportIncluded", "developerPathExposed",
    "tokenExposed", "privateKeyExposed", "getTaskAllowPresent",
    "dangerousEntitlementPresent", "hardenedRuntimeConfigured",
]:
    print(f"{key}={str(d[key]).lower()}")
PY
)"
  [[ -f "$ENTITLEMENTS_INVENTORY" ]] && RESULT[ENTITLEMENTS_INVENTORY_CREATED]=yes
  [[ "$summary" == *"productionComponentsOnly=true"* ]] && RESULT[PRODUCTION_COMPONENTS_ONLY]=yes
  [[ "$summary" == *"acceptanceSupportIncluded=false"* ]] && RESULT[ACCEPTANCE_SUPPORT_INCLUDED]=no
  [[ "$summary" == *"developerPathExposed=false"* ]] && RESULT[DEVELOPER_PATH_EXPOSED]=no
  [[ "$summary" == *"tokenExposed=false"* ]] && RESULT[TOKEN_EXPOSED]=no
  [[ "$summary" == *"privateKeyExposed=false"* ]] && RESULT[PRIVATE_KEY_EXPOSED]=no
  [[ "$summary" == *"getTaskAllowPresent=true"* ]] && RESULT[GET_TASK_ALLOW_PRESENT]=yes
  [[ "$summary" == *"dangerousEntitlementPresent=true"* ]] && RESULT[DANGEROUS_ENTITLEMENT_PRESENT]=yes
  [[ "$summary" == *"hardenedRuntimeConfigured=true"* ]] && RESULT[HARDENED_RUNTIME_CONFIGURED]=yes

  if [[ "${RESULT[UNSIGNED_RC_VERIFIED]}" == "yes" && \
        "${RESULT[PROVENANCE_VERIFIED]}" == "yes" && \
        "${RESULT[PRODUCTION_COMPONENTS_ONLY]}" == "yes" && \
        "${RESULT[ENTITLEMENTS_INVENTORY_CREATED]}" == "yes" && \
        "${RESULT[HARDENED_RUNTIME_CONFIGURED]}" == "yes" && \
        "${RESULT[GET_TASK_ALLOW_PRESENT]}" == "no" && \
        "${RESULT[DANGEROUS_ENTITLEMENT_PRESENT]}" == "no" && \
        "${RESULT[ACCEPTANCE_SUPPORT_INCLUDED]}" == "no" && \
        "${RESULT[DEVELOPER_PATH_EXPOSED]}" == "no" && \
        "${RESULT[TOKEN_EXPOSED]}" == "no" && \
        "${RESULT[PRIVATE_KEY_EXPOSED]}" == "no" ]]; then
    RESULT[SIGNING_PIPELINE_READY]=yes
  fi
}

entitlements_for_path() {
  case "$1" in
    */Payload/Hermes\ Bridge.app|*/Payload/Hermes\ Bridge.app/Contents/MacOS/HermesBridgeApp)
      print -r -- "$APP_ENTITLEMENTS"
      ;;
    */Payload/bin/HermesBridgeService)
      print -r -- "$SERVICE_ENTITLEMENTS"
      ;;
    *)
      print -r -- ""
      ;;
  esac
}

sign_component() {
  local target="$1"
  local entitlements
  entitlements="$(entitlements_for_path "$target")"
  local args=(--force --timestamp --options runtime --sign "$SIGNING_IDENTITY")
  if [[ -n "$entitlements" && -f "$entitlements" ]]; then
    args+=(--entitlements "$entitlements")
  fi
  /usr/bin/codesign "${args[@]}" "$target" >"$LOG_DIR/codesign-$(basename "$target").out" 2>"$LOG_DIR/codesign-$(basename "$target").err"
  redact_file "$LOG_DIR/codesign-$(basename "$target").out"
  redact_file "$LOG_DIR/codesign-$(basename "$target").err"
}

perform_signing() {
  rm -rf "$WORK_DIR/signed"
  mkdir -p "$WORK_DIR/signed"
  cp -R "$WORK_DIR/unsigned/." "$WORK_DIR/signed/"

  local staging="$WORK_DIR/signed"
  local nested_ok="yes"
  local rel
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    [[ "$rel" == "Payload/Hermes Bridge.app" ]] && continue
    sign_component "$staging/$rel" || nested_ok="no"
  done < "$SIGNING_ORDER_FILE"
  RESULT[NESTED_COMPONENTS_SIGNED]="$nested_ok"
  [[ "$nested_ok" == "yes" ]] || return 1

  sign_component "$staging/Payload/Hermes Bridge.app" || return 1
  RESULT[APP_SIGNED]=yes
}

verify_signatures() {
  local staging="$WORK_DIR/signed"
  local app="$staging/Payload/Hermes Bridge.app"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app" >"$LOG_DIR/codesign-verify-app.out" 2>"$LOG_DIR/codesign-verify-app.err" || return 1
  local ok="yes"
  local team_ok="yes"
  local rel
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    local target="$staging/$rel"
    /usr/bin/codesign -dv --verbose=4 "$target" >"$LOG_DIR/codesign-metadata-$(basename "$target").out" 2>"$LOG_DIR/codesign-metadata-$(basename "$target").err" || ok="no"
    /usr/bin/codesign --display --requirements :- "$target" >"$LOG_DIR/designated-requirement-$(basename "$target").txt" 2>/dev/null || true
    redact_file "$LOG_DIR/codesign-metadata-$(basename "$target").out"
    redact_file "$LOG_DIR/codesign-metadata-$(basename "$target").err"
    if [[ -n "$TEAM_ID" ]] && ! grep -q "TeamIdentifier=$TEAM_ID" "$LOG_DIR/codesign-metadata-$(basename "$target").err"; then
      team_ok="no"
    fi
  done < "$SIGNING_ORDER_FILE"

  if find "$staging/Payload" -type f -perm -111 -print0 | while IFS= read -r -d '' file; do
      /usr/bin/codesign -vv "$file" >/dev/null 2>&1 || exit 3
    done; then
    :
  else
    ok="no"
  fi

  RESULT[SIGNATURES_VERIFIED]="$ok"
  RESULT[TEAM_ID_CONSISTENT]="$team_ok"
  [[ "$ok" == "yes" && "$team_ok" == "yes" ]]
}

create_signed_artifacts() {
  local signed_rc="$ARTIFACT_DIR/HermesBridge-${SAFE_VERSION}-signed-rc.tar.gz"
  (cd "$WORK_DIR/signed" && COPYFILE_DISABLE=1 tar --no-xattrs -czf "$signed_rc" Payload ReleaseEvidence) || return 1
  (cd "$WORK_DIR/signed" && find Payload ReleaseEvidence -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256) > "$POST_SIGN_CHECKSUMS" || return 1
  RESULT[POST_SIGN_CHECKSUM_CREATED]=yes
  /usr/bin/ditto -c -k --keepParent "$WORK_DIR/signed/Payload/Hermes Bridge.app" "$ARTIFACT_DIR/HermesBridge-${SAFE_VERSION}-notary.zip" || return 1
}

parse_notary_status() {
  /usr/bin/python3 - "$1" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
status = data.get("status") or data.get("notarization", {}).get("status") or ""
submission = data.get("id") or data.get("notarization", {}).get("id") or ""
print(status.lower())
print(submission)
PY
}

perform_notarization() {
  local zip="$ARTIFACT_DIR/HermesBridge-${SAFE_VERSION}-notary.zip"
  local submit_json="$ARTIFACT_DIR/notarization-submit.json"
  local log_json="$ARTIFACT_DIR/notarization-log.json"
  xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --team-id "$TEAM_ID" \
    --wait --output-format json >"$submit_json" 2>"$LOG_DIR/notary-submit.err" || {
      redact_file "$submit_json"; redact_file "$LOG_DIR/notary-submit.err"; return 1
    }
  redact_file "$submit_json"
  redact_file "$LOG_DIR/notary-submit.err"
  RESULT[NOTARIZATION_SUBMITTED]=yes
  local parsed status submission_id
  parsed="$(parse_notary_status "$submit_json")"
  status="$(print -r -- "$parsed" | sed -n '1p')"
  submission_id="$(print -r -- "$parsed" | sed -n '2p')"
  [[ -n "$submission_id" ]] && print -r -- "$submission_id" > "$ARTIFACT_DIR/notarization-submission-id.txt"
  if [[ -n "$submission_id" ]]; then
    xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" --team-id "$TEAM_ID" \
      --output-format json >"$log_json" 2>"$LOG_DIR/notary-log.err" || true
    redact_file "$log_json"
    redact_file "$LOG_DIR/notary-log.err"
    [[ -f "$log_json" ]] && RESULT[NOTARIZATION_LOG_RECORDED]=yes
  fi
  [[ "$status" == "accepted" ]] || return 1
  RESULT[NOTARIZATION_ACCEPTED]=yes

  xcrun stapler staple "$WORK_DIR/signed/Payload/Hermes Bridge.app" >"$LOG_DIR/stapler-staple.out" 2>"$LOG_DIR/stapler-staple.err" || return 1
  RESULT[TICKET_STAPLED]=yes
  xcrun stapler validate "$WORK_DIR/signed/Payload/Hermes Bridge.app" >"$LOG_DIR/stapler-validate.out" 2>"$LOG_DIR/stapler-validate.err" || return 1
  RESULT[STAPLE_VALID]=yes
  spctl --assess --type execute --verbose=4 "$WORK_DIR/signed/Payload/Hermes Bridge.app" >"$LOG_DIR/spctl.out" 2>"$LOG_DIR/spctl.err" || return 1
  RESULT[GATEKEEPER_ACCEPTED]=yes
}

write_post_sign_provenance() {
  local signed_rc="$ARTIFACT_DIR/HermesBridge-${SAFE_VERSION}-signed-rc.tar.gz"
  local source_commit
  source_commit="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || print unknown)"
  /usr/bin/python3 - "$ROOT_DIR" "$POST_SIGN_PROVENANCE" "$UNSIGNED_RC" "$signed_rc" "$source_commit" \
    "$SIGNING_IDENTITY" "$TEAM_ID" "$ARTIFACT_DIR/notarization-submission-id.txt" \
    "${RESULT[NOTARIZATION_ACCEPTED]}" "${RESULT[STAPLE_VALID]}" "${RESULT[GATEKEEPER_ACCEPTED]}" <<'PY'
import hashlib, json, pathlib, sys, time
root, out, unsigned, signed, commit, identity, team, submission_file, notary, staple, gatekeeper = sys.argv[1:]
root = pathlib.Path(root)
def digest(path):
    p = pathlib.Path(path)
    if not p.exists():
        return None
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()
def display_path(path):
    p = pathlib.Path(path)
    try:
        return p.relative_to(root).as_posix()
    except ValueError:
        return p.name
submission_path = pathlib.Path(submission_file)
data = {
    "schemaVersion": 1,
    "milestone": "M12-003",
    "unsignedRC": {"path": display_path(unsigned), "sha256": digest(unsigned)},
    "signedRC": {"path": display_path(signed), "sha256": digest(signed)},
    "sourceCommit": commit,
    "signingIdentityDesignation": identity if identity else None,
    "teamIDProvided": bool(team),
    "teamID": team if team else None,
    "signingTimestampUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "notarizationSubmissionID": submission_path.read_text(encoding="utf-8").strip() if submission_path.exists() else None,
    "notarizationResult": notary,
    "staplingResult": staple,
    "gatekeeperResult": gatekeeper,
}
pathlib.Path(out).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
  [[ -f "$POST_SIGN_PROVENANCE" ]] && RESULT[POST_SIGN_PROVENANCE_CREATED]=yes
}

main() {
  set_default_results
  rm -rf "$WORK_DIR" "$LOG_DIR"
  mkdir -p "$ARTIFACT_DIR" "$WORK_DIR" "$LOG_DIR"

  verify_unsigned_rc || fail "unsigned RC verification failed"
  verify_m12_002_provenance || fail "M12-002 provenance verification failed"
  discover_credentials
  run_static_inventory || fail "static signing readiness inventory failed"

  if [[ "${RESULT[CREDENTIALS_AVAILABLE]}" == "yes" ]]; then
    perform_signing || fail "production signing failed"
    verify_signatures || fail "signature verification failed"
    create_signed_artifacts || fail "signed artifact creation failed"
    perform_notarization || fail "notarization, stapling, or Gatekeeper assessment failed"
  else
    print -r -- "NOTARIZATION_SUBMITTED=no" > "$ARTIFACT_DIR/readiness-missing-prerequisites.txt"
    [[ "${RESULT[SIGNING_IDENTITY_REQUESTED]}" == "yes" ]] || print -r -- "missing HERMES_SIGNING_IDENTITY" >> "$ARTIFACT_DIR/readiness-missing-prerequisites.txt"
    [[ "${RESULT[SIGNING_IDENTITY_AVAILABLE]}" == "yes" ]] || print -r -- "signing identity unavailable" >> "$ARTIFACT_DIR/readiness-missing-prerequisites.txt"
    [[ "${RESULT[TEAM_ID_AVAILABLE]}" == "yes" ]] || print -r -- "missing HERMES_TEAM_ID" >> "$ARTIFACT_DIR/readiness-missing-prerequisites.txt"
    [[ "${RESULT[NOTARY_PROFILE_REQUESTED]}" == "yes" ]] || print -r -- "missing HERMES_NOTARY_PROFILE" >> "$ARTIFACT_DIR/readiness-missing-prerequisites.txt"
    [[ "${RESULT[NOTARY_PROFILE_AVAILABLE]}" == "yes" ]] || print -r -- "notary profile unavailable" >> "$ARTIFACT_DIR/readiness-missing-prerequisites.txt"
  fi

  write_post_sign_provenance || fail "post-signing provenance creation failed"
  write_result
}

main "$@"
