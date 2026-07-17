#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$repo_root"

artifact_root="$repo_root/artifacts/m3-002"
release_output="$artifact_root/release-a"
release_output_b="$artifact_root/release-b"
real_plist="$HOME/Library/LaunchAgents/com.hermes.bridge.plist"
real_plist_mtime_before="$(stat -f %m "$real_plist" 2>/dev/null || true)"

rm -rf "$artifact_root"
mkdir -p "$artifact_root"

SOURCE_DATE_EPOCH=0 "$repo_root/Scripts/packaging/build-release.zsh" \
  --output-dir "$release_output" \
  --signing-mode adhoc >/dev/null

"$repo_root/Scripts/packaging/verify-release.zsh" \
  --release-dir "$release_output/HermesBridgeRelease" \
  --archive "$release_output/HermesBridgeRelease.zip" >/dev/null

tamper_root="$artifact_root/tampered"
cp -R "$release_output" "$tamper_root"
printf 'tamper' >> "$tamper_root/HermesBridgeRelease/Payload/HermesBridgeService"
if "$repo_root/Scripts/packaging/verify-release.zsh" \
  --release-dir "$tamper_root/HermesBridgeRelease" \
  --archive "$tamper_root/HermesBridgeRelease.zip" >/dev/null 2>&1; then
  print -u2 "tampered release unexpectedly verified"
  exit 1
fi

preflight_output="$("$repo_root/Scripts/packaging/notarization-preflight.zsh" \
  --release-dir "$release_output/HermesBridgeRelease" \
  --archive "$release_output/HermesBridgeRelease.zip")"
print -- "$preflight_output" > "$artifact_root/notarization-preflight.txt"
if ! print -- "$preflight_output" | grep -q '^NOTARIZATION_READY=no$'; then
  print -u2 "ad-hoc release should not be notarization-ready"
  exit 1
fi
if ! print -- "$preflight_output" | grep -q '^DEVELOPER_ID_SIGNED=no$'; then
  print -u2 "ad-hoc release should not report Developer ID signing"
  exit 1
fi

if "$repo_root/Scripts/packaging/submit-notarization.zsh" \
  --archive "$release_output/HermesBridgeRelease.zip" \
  --keychain-profile "m3-002-test-profile" >/dev/null 2>&1; then
  print -u2 "submission script did not refuse missing --submit"
  exit 1
fi

if "$repo_root/Scripts/packaging/submit-notarization.zsh" \
  --archive "$release_output/HermesBridgeRelease.zip" \
  --submit \
  --keychain-profile "m3-002-test-profile" >/dev/null 2>&1; then
  print -u2 "submission script did not refuse ad-hoc archive"
  exit 1
fi

if "$repo_root/Scripts/packaging/build-release.zsh" \
  --output-dir "$repo_root/tmp/m3-002" \
  --signing-mode adhoc >/dev/null 2>&1; then
  print -u2 "unsafe output path unexpectedly accepted"
  exit 1
fi

if "$repo_root/Scripts/packaging/build-release.zsh" \
  --output-dir "$artifact_root/unknown-signing" \
  --signing-mode unknown >/dev/null 2>&1; then
  print -u2 "unknown signing mode unexpectedly accepted"
  exit 1
fi

if "$repo_root/Scripts/packaging/build-release.zsh" \
  --output-dir "$artifact_root/invalid-identity" \
  --signing-mode developer-id \
  --identity "Apple Development: Invalid" >/dev/null 2>&1; then
  print -u2 "invalid Developer ID identity unexpectedly accepted"
  exit 1
fi

if "$repo_root/Scripts/packaging/build-release.zsh" \
  --output-dir "$artifact_root/missing-identity" \
  --signing-mode developer-id \
  --identity "Developer ID Application: M3 002 Missing Identity (TEAMID)" >/dev/null 2>&1; then
  print -u2 "missing Developer ID identity unexpectedly accepted"
  exit 1
fi

SOURCE_DATE_EPOCH=0 "$repo_root/Scripts/packaging/build-release.zsh" \
  --output-dir "$release_output_b" \
  --signing-mode adhoc >/dev/null
if ! cmp -s "$release_output/HermesBridgeRelease.zip" "$release_output_b/HermesBridgeRelease.zip"; then
  print -u2 "deterministic second build comparison failed"
  exit 1
fi

real_plist_mtime_after="$(stat -f %m "$real_plist" 2>/dev/null || true)"
if [[ "$real_plist_mtime_before" != "$real_plist_mtime_after" ]]; then
  print -u2 "real LaunchAgent was modified: $real_plist"
  exit 1
fi

if pgrep -fl 'HermesBridgeService' >/dev/null 2>&1; then
  print -u2 "residual HermesBridgeService process found"
  exit 1
fi

find "$artifact_root" -type d -name 'hermes-release-extract.*' -prune -print | grep -q . && {
  print -u2 "temporary extraction directory was not cleaned"
  exit 1
}

if grep -R -I -n -E 'HERMES_DASHBOARD_SESSION_TOKEN|backend token|Prompt|prompt|State|Runtime|Logs|/Users/|/private/|/var/folders|BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY|APPLE_ID|APP_SPECIFIC_PASSWORD|ASC_KEY' \
  "$release_output/HermesBridgeRelease/Metadata" "$release_output/HermesBridgeRelease/Payload/com.hermes.bridge.plist" >/dev/null; then
  print -u2 "forbidden private, token, prompt, or state marker found in release"
  exit 1
fi

print "m3-002 integration passed"
