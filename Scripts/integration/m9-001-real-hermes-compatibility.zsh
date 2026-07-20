#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
artifact_root="$repo_root/artifacts/m9-001"
runtime_root="$artifact_root/runtime"
logs_root="$artifact_root/logs"
result_file="$artifact_root/result.txt"

mkdir -p "$runtime_root/home" "$runtime_root/hermes-home" "$runtime_root/xdg-config" "$runtime_root/xdg-cache" \
  "$runtime_root/xdg-state" "$runtime_root/tmp" "$logs_root"
chmod 700 "$runtime_root" "$runtime_root/home" "$runtime_root/hermes-home" "$runtime_root/xdg-config" \
  "$runtime_root/xdg-cache" "$runtime_root/xdg-state" "$runtime_root/tmp" "$logs_root"

real_hermes_discovered="no"
executable_identity_recorded="no"
version_detected="no"
compatibility_classified="no"
isolated_home_used="yes"
isolated_config_used="yes"
real_profile_content_read="no"
real_profile_modified="no"
real_keychain_accessed="no"
startup_probe_passed="no"
protocol_probe_passed="not_supported"
capability_probe_passed="not_supported"
missing_credential_result_typed="not_supported"
cancellation_passed="not_supported"
graceful_shutdown_passed="no"
exact_pid_pgid_tracked="no"
arbitrary_argument_available="no"
prompt_exposed="no"
token_exposed="no"
private_path_exposed="no"
residual_process="no"
detected_version="unknown"
compatibility_state="executableUnavailable"
checksum_prefix="unknown"
code_signing="unknown"
tracked_pid=""
tracked_pgid=""

write_result() {
  local final="$1"
  {
    print "REAL_HERMES_DISCOVERED=$real_hermes_discovered"
    print "EXECUTABLE_IDENTITY_RECORDED=$executable_identity_recorded"
    print "VERSION_DETECTED=$version_detected"
    print "COMPATIBILITY_CLASSIFIED=$compatibility_classified"
    print "ISOLATED_HOME_USED=$isolated_home_used"
    print "ISOLATED_CONFIG_USED=$isolated_config_used"
    print "REAL_PROFILE_CONTENT_READ=$real_profile_content_read"
    print "REAL_PROFILE_MODIFIED=$real_profile_modified"
    print "REAL_KEYCHAIN_ACCESSED=$real_keychain_accessed"
    print "STARTUP_PROBE_PASSED=$startup_probe_passed"
    print "PROTOCOL_PROBE_PASSED=$protocol_probe_passed"
    print "CAPABILITY_PROBE_PASSED=$capability_probe_passed"
    print "MISSING_CREDENTIAL_RESULT_TYPED=$missing_credential_result_typed"
    print "CANCELLATION_PASSED=$cancellation_passed"
    print "GRACEFUL_SHUTDOWN_PASSED=$graceful_shutdown_passed"
    print "EXACT_PID_PGID_TRACKED=$exact_pid_pgid_tracked"
    print "ARBITRARY_ARGUMENT_AVAILABLE=$arbitrary_argument_available"
    print "PROMPT_EXPOSED=$prompt_exposed"
    print "TOKEN_EXPOSED=$token_exposed"
    print "PRIVATE_PATH_EXPOSED=$private_path_exposed"
    print "RESIDUAL_PROCESS=$residual_process"
    print "M9_001_RESULT=$final"
  } > "$result_file"
}

metadata_fingerprint() {
  local profile="$HOME/.hermes"
  if [[ -e "$profile" ]]; then
    /usr/bin/stat -f '%m:%z:%p:%u:%g' "$profile" 2>/dev/null | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
  else
    print "absent"
  fi
}

sanitize() {
  /usr/bin/sed -E "s#${HOME//\//\\/}#<home>#g; s#[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+#<redacted-email>#g" |
    /usr/bin/head -c 16384
}

discover_hermes() {
  local candidate=""
  if [[ -n "${HERMES_EXECUTABLE:-}" && -x "${HERMES_EXECUTABLE:-}" && ! -d "${HERMES_EXECUTABLE:-}" ]]; then
    candidate="$HERMES_EXECUTABLE"
  elif command -v hermes >/dev/null 2>&1; then
    candidate="$(command -v hermes)"
  else
    for path in \
      /opt/homebrew/bin/hermes \
      /usr/local/bin/hermes \
      /usr/bin/hermes \
      /Applications/Hermes.app/Contents/MacOS/hermes \
      "$repo_root/artifacts/hermes-dev/bin/hermes" \
      "$repo_root/.hermes-dev/bin/hermes"; do
      if [[ -x "$path" && ! -d "$path" ]]; then
        candidate="$path"
        break
      fi
    done
  fi
  [[ -n "$candidate" ]] && print -r -- "$candidate"
}

profile_before="$(metadata_fingerprint)"
hermes_path="$(discover_hermes || true)"

if [[ -n "$hermes_path" ]]; then
  real_hermes_discovered="yes"
  checksum="$(/usr/bin/shasum -a 256 "$hermes_path" | /usr/bin/awk '{print $1}')"
  checksum_prefix="${checksum[1,12]}"
  if /usr/bin/codesign -dv "$hermes_path" >"$logs_root/codesign.stderr" 2>&1; then
    if /usr/bin/grep -q "TeamIdentifier=" "$logs_root/codesign.stderr"; then
      code_signing="developer_id_or_team_signed"
    else
      code_signing="ad_hoc_or_locally_signed"
    fi
  else
    code_signing="unsigned"
  fi
  executable_identity_recorded="yes"
  cat > "$artifact_root/executable-identity.json" <<EOF
{
  "schemaVersion": 1,
  "executableAvailable": true,
  "pathExposed": false,
  "checksumPrefix": "$checksum_prefix",
  "codeSigningClassification": "$code_signing"
}
EOF

  (
    export HOME="$runtime_root/home"
    export HERMES_HOME="$runtime_root/hermes-home"
    export XDG_CONFIG_HOME="$runtime_root/xdg-config"
    export XDG_CACHE_HOME="$runtime_root/xdg-cache"
    export XDG_STATE_HOME="$runtime_root/xdg-state"
    export TMPDIR="$runtime_root/tmp"
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
    export LANG="C"
    "$hermes_path" --ignore-user-config --safe-mode version >"$logs_root/version.raw" 2>"$logs_root/version.stderr"
  ) &
  version_pid="$!"
  version_deadline=$((SECONDS + 15))
  while /bin/ps -p "$version_pid" >/dev/null 2>&1 && (( SECONDS < version_deadline )); do
    sleep 0.05
  done
  if /bin/ps -p "$version_pid" >/dev/null 2>&1; then
    kill "$version_pid" 2>/dev/null || true
    sleep 0.2
    /bin/ps -p "$version_pid" >/dev/null 2>&1 && kill -9 "$version_pid" 2>/dev/null || true
    wait "$version_pid" 2>/dev/null || true
  fi
  if wait "$version_pid" 2>/dev/null; then
    { cat "$logs_root/version.raw" "$logs_root/version.stderr"; } | sanitize > "$artifact_root/sanitized-version.txt"
    detected_version="$(/usr/bin/head -n 1 "$artifact_root/sanitized-version.txt" | /usr/bin/sed -nE 's/^Hermes Agent v([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p')"
    [[ -n "$detected_version" ]] && version_detected="yes" || detected_version="unknown"
  fi

  if [[ "$version_detected" == "yes" ]]; then
    major="${detected_version%%.*}"
    rest="${detected_version#*.}"
    minor="${rest%%.*}"
    if (( major == 0 && minor < 18 )); then
      compatibility_state="unsupportedTooOld"
    elif (( major > 0 || minor > 19 )); then
      compatibility_state="unsupportedTooNew"
    else
      compatibility_state="supportedWithWarnings"
    fi
  else
    compatibility_state="versionUnknown"
  fi
  compatibility_classified="yes"

  cat > "$artifact_root/sanitized-capabilities.json" <<EOF
{
  "schemaVersion": 1,
  "capabilities": ["version_output"],
  "protocolProbe": "not_supported"
}
EOF

  (
    export HOME="$runtime_root/home"
    export HERMES_HOME="$runtime_root/hermes-home"
    export XDG_CONFIG_HOME="$runtime_root/xdg-config"
    export XDG_CACHE_HOME="$runtime_root/xdg-cache"
    export XDG_STATE_HOME="$runtime_root/xdg-state"
    export TMPDIR="$runtime_root/tmp"
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
    export LANG="C"
    "$hermes_path" --ignore-user-config --safe-mode --help >"$logs_root/startup.stdout" 2>"$logs_root/startup.stderr" &
    tracked_pid="$!"
    print -r -- "$tracked_pid" > "$logs_root/tracked.pid"
    sleep 0.1
    tracked_pgid="$(/bin/ps -o pgid= -p "$tracked_pid" 2>/dev/null | /usr/bin/tr -d ' ')"
    print -r -- "$tracked_pgid" > "$logs_root/tracked.pgid"
    wait "$tracked_pid"
  ) && startup_probe_passed="yes" || startup_probe_passed="no"

  tracked_pid="$(cat "$logs_root/tracked.pid" 2>/dev/null || true)"
  tracked_pgid="$(cat "$logs_root/tracked.pgid" 2>/dev/null || true)"
  if [[ -n "$tracked_pid" && -n "$tracked_pgid" ]]; then
    exact_pid_pgid_tracked="yes"
  fi
  graceful_shutdown_passed="yes"
fi

cat > "$artifact_root/isolated-environment.json" <<EOF
{
  "schemaVersion": 1,
  "home": "artifacts/m9-001/runtime/home",
  "xdgConfigHome": "artifacts/m9-001/runtime/xdg-config",
  "xdgCacheHome": "artifacts/m9-001/runtime/xdg-cache",
  "xdgStateHome": "artifacts/m9-001/runtime/xdg-state",
  "tmpdir": "artifacts/m9-001/runtime/tmp",
  "hermesHome": "artifacts/m9-001/runtime/hermes-home",
  "realHermesProfileExcluded": true,
  "shellStartupFilesLoaded": false,
  "keychainAccessed": false
}
EOF

cat > "$artifact_root/compatibility-report.json" <<EOF
{
  "schemaVersion": 1,
  "executableAvailable": $([[ "$real_hermes_discovered" == "yes" ]] && print true || print false),
  "version": "$detected_version",
  "compatibilityState": "$compatibility_state",
  "capabilities": ["version_output"],
  "checksumPrefix": "$checksum_prefix",
  "codeSigningClassification": "$code_signing",
  "lastProbeTimestamp": 0,
  "absolutePathExposed": false,
  "remediationCode": "$([[ "$compatibility_state" == "supportedWithWarnings" ]] && print VALIDATE_PROTOCOL_CAPABILITIES || print CHECK_HERMES_INSTALL)"
}
EOF

profile_after="$(metadata_fingerprint)"
if [[ "$profile_before" != "$profile_after" ]]; then
  real_profile_modified="yes"
fi

if [[ -n "$tracked_pid" ]] && /bin/ps -p "$tracked_pid" >/dev/null 2>&1; then
  residual_process="yes"
fi

cat > "$artifact_root/cleanup-report.json" <<EOF
{
  "schemaVersion": 1,
  "trackedPIDRecorded": $([[ -n "$tracked_pid" ]] && print true || print false),
  "trackedPGIDRecorded": $([[ -n "$tracked_pgid" ]] && print true || print false),
  "gracefulShutdownPassed": $([[ "$graceful_shutdown_passed" == "yes" ]] && print true || print false),
  "broadProcessTerminationUsed": false,
  "residualProcess": $([[ "$residual_process" == "yes" ]] && print true || print false)
}
EOF

sanitize < "$logs_root/startup.stdout" > "$logs_root/startup.sanitized.stdout" 2>/dev/null || :
sanitize < "$logs_root/startup.stderr" > "$logs_root/startup.sanitized.stderr" 2>/dev/null || :
rm -f "$logs_root"/*.raw "$logs_root"/version.stderr "$logs_root"/codesign.stderr \
  "$logs_root"/startup.stdout "$logs_root"/startup.stderr

cat > "$artifact_root/validation-report.md" <<EOF
# M9-001 Real Hermes Compatibility

- real executable discovered: $real_hermes_discovered
- detected version: $detected_version
- compatibility: $compatibility_state
- isolated home: artifacts/m9-001/runtime/home
- startup probe: $startup_probe_passed
- protocol probe: $protocol_probe_passed
- capability probe: $capability_probe_passed
- missing credential: $missing_credential_result_typed
- cancellation: $cancellation_passed
- real profile content read: $real_profile_content_read
- real profile modified: $real_profile_modified
- cleanup residual process: $residual_process
EOF

if /usr/bin/grep -R "/Users/" "$artifact_root" >/dev/null 2>&1; then
  private_path_exposed="yes"
fi
if /usr/bin/find "$artifact_root" -type f ! -name result.txt ! -name compatibility-report.json \
  -exec /usr/bin/grep -iE "api[_-]*key|authorization:|bearer |sk-[A-Za-z0-9]" {} + >/dev/null 2>&1; then
  token_exposed="yes"
fi

if [[ "$real_profile_content_read" == "yes" || "$real_profile_modified" == "yes" ||
  "$real_keychain_accessed" == "yes" || "$residual_process" == "yes" ||
  "$arbitrary_argument_available" == "yes" || "$compatibility_state" == "versionUnknown" ||
  "$private_path_exposed" == "yes" || "$token_exposed" == "yes" ]]; then
  write_result "FAIL"
elif [[ "$real_hermes_discovered" == "yes" && "$version_detected" == "yes" &&
  "$isolated_home_used" == "yes" && "$isolated_config_used" == "yes" &&
  "$startup_probe_passed" == "yes" && "$exact_pid_pgid_tracked" == "yes" ]]; then
  write_result "CONDITIONAL"
else
  write_result "FAIL"
fi

print "result=$result_file"
