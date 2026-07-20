#!/bin/zsh
set -euo pipefail

usage() {
  print -u2 "usage: notarize-release.zsh --archive <archive> --staging-root <root> --mode <production|rc>"
}

die() {
  print -u2 "error: $*"
  exit 1
}

archive=""
staging_root=""
mode=""

while (( $# > 0 )); do
  case "$1" in
    --archive)
      [[ $# -ge 2 ]] || { usage; exit 64; }
      archive="$2"
      shift 2
      ;;
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

[[ -n "$archive" && -n "$staging_root" && -n "$mode" ]] || { usage; exit 64; }
[[ "$archive" == /* ]] || archive="$PWD/$archive"
[[ "$staging_root" == /* ]] || staging_root="$PWD/$staging_root"
[[ -f "$archive" && ! -L "$archive" ]] || die "archive missing or symlinked"

report="$staging_root/ReleaseEvidence/notarization-report.env"
app_bundle="$staging_root/Payload/Hermes Bridge.app"
log_root="$staging_root:h/logs"
mkdir -p "$log_root"
tmp_key=""
notary_archive="$archive"
cleanup() {
  [[ -n "$tmp_key" ]] && rm -f "$tmp_key"
  [[ "$notary_archive" != "$archive" && -f "$notary_archive" ]] && rm -f "$notary_archive"
}
trap cleanup EXIT

if [[ "$mode" != "production" ]]; then
  {
    print "NOTARIZATION_ACCEPTED=no"
    print "STAPLE_VERIFIED=no"
    print "GATEKEEPER_VERIFIED=no"
    print "NOTARIZATION_BLOCKER=release-candidate-without-production-notarization"
  } > "$report"
  exit 0
fi

codesign --verify --deep --strict "$app_bundle" >/dev/null
details="$(codesign -dv --verbose=4 "$app_bundle" 2>&1)"
print -- "$details" | grep -q '^Authority=Developer ID Application:' || die "production release is not Developer ID signed"

case "$archive" in
  *.zip|*.dmg|*.pkg)
    notary_archive="$archive"
    ;;
  *)
    notary_archive="$staging_root:h/HermesBridge-notarization.zip"
    rm -f "$notary_archive"
    ditto -c -k --keepParent "$app_bundle" "$notary_archive"
    ;;
esac

if [[ -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" && -n "${APPLE_API_PRIVATE_KEY_BASE64:-}" ]]; then
  tmp_key="$RUNNER_TEMP/AuthKey_${APPLE_API_KEY_ID}.p8"
  print -r -- "$APPLE_API_PRIVATE_KEY_BASE64" | base64 --decode > "$tmp_key"
  chmod 600 "$tmp_key"
  xcrun notarytool submit "$notary_archive" --key "$tmp_key" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" --wait > "$log_root/notarytool.log"
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  xcrun notarytool submit "$notary_archive" --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait > "$log_root/notarytool.log"
else
  die "notarization credentials are unavailable"
fi

grep -E 'status:[[:space:]]+Accepted|Accepted' "$log_root/notarytool.log" >/dev/null || die "notarization was not accepted"
xcrun stapler staple "$app_bundle" > "$log_root/stapler.log"
xcrun stapler validate "$app_bundle" >> "$log_root/stapler.log"
spctl --assess --type execute --verbose "$app_bundle" > "$log_root/gatekeeper.log" 2>&1

{
  print "NOTARIZATION_ACCEPTED=yes"
  print "STAPLE_VERIFIED=yes"
  print "GATEKEEPER_VERIFIED=yes"
  print "NOTARIZATION_BLOCKER="
} > "$report"
