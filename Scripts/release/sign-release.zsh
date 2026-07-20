#!/bin/zsh
set -euo pipefail

usage() {
  print -u2 "usage: sign-release.zsh (--staging-root <root> --mode <adhoc|developer-id>|--mode production --require-credentials)"
}

die() {
  print -u2 "error: $*"
  exit 1
}

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
staging_root=""
mode=""
require_credentials="no"

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
    --require-credentials)
      require_credentials="yes"
      shift
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

[[ -n "$mode" ]] || { usage; exit 64; }

has_developer_id_credentials() {
  [[ -n "${APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64:-}" ]] &&
    [[ -n "${APPLE_DEVELOPER_ID_APPLICATION_PASSWORD:-}" ]] &&
    [[ -n "${APPLE_SIGNING_IDENTITY:-}" ]] &&
    [[ "${APPLE_SIGNING_IDENTITY:-}" == Developer\ ID\ Application:* ]]
}

has_notary_credentials() {
  { [[ -n "${APPLE_API_KEY_ID:-}" ]] && [[ -n "${APPLE_API_ISSUER_ID:-}" ]] && [[ -n "${APPLE_API_PRIVATE_KEY_BASE64:-}" ]]; } ||
    { [[ -n "${APPLE_ID:-}" ]] && [[ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]] && [[ -n "${APPLE_TEAM_ID:-}" ]]; }
}

if [[ "$require_credentials" == "yes" ]]; then
  has_developer_id_credentials || die "Developer ID signing secrets are unavailable"
  has_notary_credentials || die "notarization secrets are unavailable"
  print "SIGNING_CREDENTIALS_AVAILABLE=yes"
  print "NOTARIZATION_CREDENTIALS_AVAILABLE=yes"
  exit 0
fi

[[ -n "$staging_root" ]] || { usage; exit 64; }
[[ "$staging_root" == /* ]] || staging_root="$PWD/$staging_root"
staging_root="$(cd "$staging_root" && pwd -P)"
[[ "$staging_root" == "$repo_root/artifacts/"* ]] || die "staging root must be artifact-owned"

app_bundle="$staging_root/Payload/Hermes Bridge.app"
service_binary="$staging_root/Payload/bin/HermesBridgeService"
control_binary="$staging_root/Payload/bin/HermesBridgeControl"
app_entitlements="$repo_root/Packaging/Entitlements/HermesBridgeApp.entitlements"
service_entitlements="$repo_root/Packaging/Entitlements/HermesBridgeService.entitlements"
signing_report="$staging_root/ReleaseEvidence/signing-report.env"
mkdir -p "$staging_root/ReleaseEvidence"

keychain_path=""
keychain_password=""
cleanup() {
  if [[ -n "$keychain_path" ]]; then
    security list-keychains -d user -s login.keychain-db >/dev/null 2>&1 || true
    security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

case "$mode" in
  adhoc)
    codesign --force --sign - --options runtime --entitlements "$service_entitlements" "$service_binary" >/dev/null
    codesign --force --sign - --options runtime --entitlements "$service_entitlements" "$control_binary" >/dev/null
    codesign --force --deep --sign - --options runtime --entitlements "$app_entitlements" "$app_bundle" >/dev/null
    {
      print "DEVELOPER_ID_SIGNED=no"
      print "HARDENED_RUNTIME_ENABLED=yes"
      print "SIGNING_MODE=adhoc"
      print "SIGNING_BLOCKER=missing-developer-id-credentials"
    } > "$signing_report"
    ;;
  developer-id)
    has_developer_id_credentials || die "Developer ID signing secrets are unavailable"
    keychain_path="$RUNNER_TEMP/hermes-release-signing-${RANDOM}-${RANDOM}.keychain-db"
    keychain_password="$(uuidgen)"
    certificate_path="$RUNNER_TEMP/hermes-developer-id.p12"
    print -r -- "$APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64" | base64 --decode > "$certificate_path"
    chmod 600 "$certificate_path"
    security create-keychain -p "$keychain_password" "$keychain_path" >/dev/null
    security set-keychain-settings -lut 21600 "$keychain_path" >/dev/null
    security unlock-keychain -p "$keychain_password" "$keychain_path" >/dev/null
    security import "$certificate_path" -k "$keychain_path" -P "$APPLE_DEVELOPER_ID_APPLICATION_PASSWORD" -T /usr/bin/codesign >/dev/null
    rm -f "$certificate_path"
    security list-keychains -d user -s "$keychain_path" >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain_path" >/dev/null
    codesign --force --sign "$APPLE_SIGNING_IDENTITY" --timestamp --options runtime --entitlements "$service_entitlements" "$service_binary" >/dev/null
    codesign --force --sign "$APPLE_SIGNING_IDENTITY" --timestamp --options runtime --entitlements "$service_entitlements" "$control_binary" >/dev/null
    codesign --force --deep --sign "$APPLE_SIGNING_IDENTITY" --timestamp --options runtime --entitlements "$app_entitlements" "$app_bundle" >/dev/null
    {
      print "DEVELOPER_ID_SIGNED=yes"
      print "HARDENED_RUNTIME_ENABLED=yes"
      print "SIGNING_MODE=developer-id"
      print "SIGNING_BLOCKER="
    } > "$signing_report"
    ;;
  *)
    die "invalid signing mode"
    ;;
esac

codesign --verify --deep --strict "$app_bundle" >/dev/null
codesign --verify --strict "$service_binary" >/dev/null
codesign --verify --strict "$control_binary" >/dev/null
print "signing_report=$signing_report"

