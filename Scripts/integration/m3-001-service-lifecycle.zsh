#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$repo_root"

artifact_root="$repo_root/artifacts/m3-001"
fake_home="$artifact_root/fake-home"
fake_launchctl_log="$artifact_root/fake-launchctl.log"
real_plist="$HOME/Library/LaunchAgents/com.hermes.bridge.plist"
real_plist_mtime_before="$(stat -f %m "$real_plist" 2>/dev/null || true)"

rm -rf "$artifact_root"
mkdir -p "$artifact_root"

swift build --product HermesBridgeService
swift build --product HermesBridgeServiceLifecycle

service_binary="$repo_root/.build/debug/HermesBridgeService"
cli="$repo_root/.build/debug/HermesBridgeServiceLifecycle"
upgrade_source="$artifact_root/upgrade-source/HermesBridgeService"

mkdir -p "$(dirname "$upgrade_source")"
cp "$service_binary" "$upgrade_source"
chmod 500 "$upgrade_source"

"$cli" plan \
  --artifact-root "$artifact_root" \
  --fake-launchctl \
  --fake-launchctl-log "$fake_launchctl_log" \
  --service-binary "$service_binary" \
  --version "m3-001-a" >/dev/null

"$cli" install \
  --artifact-root "$artifact_root" \
  --fake-launchctl \
  --fake-launchctl-log "$fake_launchctl_log" \
  --service-binary "$service_binary" \
  --version "m3-001-a" \
  --bootstrap >/dev/null

"$cli" validate \
  --artifact-root "$artifact_root" \
  --fake-launchctl \
  --fake-launchctl-log "$fake_launchctl_log" >/dev/null

service_status="$("$cli" status --artifact-root "$artifact_root" --fake-launchctl --fake-launchctl-log "$fake_launchctl_log")"
if [[ "$service_status" != "runningHealthy" ]]; then
  print -u2 "expected runningHealthy, got $service_status"
  exit 1
fi

"$cli" restart \
  --artifact-root "$artifact_root" \
  --fake-launchctl \
  --fake-launchctl-log "$fake_launchctl_log" >/dev/null

"$cli" upgrade \
  --artifact-root "$artifact_root" \
  --fake-launchctl \
  --fake-launchctl-log "$fake_launchctl_log" \
  --service-binary "$upgrade_source" \
  --version "m3-001-b" \
  --bootstrap >/dev/null

"$cli" rollback \
  --artifact-root "$artifact_root" \
  --fake-launchctl \
  --fake-launchctl-log "$fake_launchctl_log" >/dev/null

"$cli" stop \
  --artifact-root "$artifact_root" \
  --fake-launchctl \
  --fake-launchctl-log "$fake_launchctl_log" >/dev/null

"$cli" uninstall \
  --artifact-root "$artifact_root" \
  --fake-launchctl \
  --fake-launchctl-log "$fake_launchctl_log" >/dev/null

if [[ -e "$fake_home/Library/LaunchAgents/com.hermes.bridge.test.m3-001.plist" ]]; then
  print -u2 "temporary LaunchAgent plist was not removed"
  exit 1
fi

real_plist_mtime_after="$(stat -f %m "$real_plist" 2>/dev/null || true)"
if [[ "$real_plist_mtime_before" != "$real_plist_mtime_after" ]]; then
  print -u2 "real LaunchAgent was modified: $real_plist"
  exit 1
fi

if pgrep -fl 'com.hermes.bridge.test.m3-001' >/dev/null 2>&1; then
  print -u2 "residual temporary service process found"
  exit 1
fi

scan_output="$(find "$fake_home" -type f \( -name '*.plist' -o -name '*.json' -o -name '*.log' \) 2>/dev/null || true)"
if [[ -n "$scan_output" ]]; then
  scan_files=("${(@f)scan_output}")
else
  scan_files=()
fi
if (( ${#scan_files[@]} > 0 )) && grep -Iq . "${scan_files[@]}" \
  && grep -iqE 'token|prompt|HERMES_DASHBOARD_SESSION_TOKEN' "${scan_files[@]}"; then
  print -u2 "secret or prompt marker found in artifacts"
  exit 1
fi

print "m3-001 integration passed"
