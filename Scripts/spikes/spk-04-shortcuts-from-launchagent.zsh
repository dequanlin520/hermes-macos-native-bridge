#!/bin/zsh

set -u

readonly SCRIPT_NAME="${0:t}"
readonly FIXTURE_NAME="Hermes Bridge SPK-04 Fixture"
readonly EXPECTED_RESPONSE="SPK04_SHORTCUT_RESPONSE"
readonly OUTPUT_LIMIT_BYTES=8192
readonly PRODUCTION_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

usage() {
  cat <<'USAGE'
Usage:
  Scripts/spikes/spk-04-shortcuts-from-launchagent.zsh [--active-test]

Default mode is read-only. It gathers local CLI and launchd metadata without
enumerating personal shortcut names or bootstrapping a LaunchAgent.

Active mode creates one temporary LaunchAgent in gui/<uid>, records bounded
evidence under artifacts/spk-04/active/<label>/, optionally runs only the exact
SPK-04 fixture shortcut, then boots out and checks cleanup.
USAGE
}

die() {
  print -r -- "error: $*" >&2
  exit 2
}

repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  print -r -- "$root"
}

timestamp_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

sanitize_path_value() {
  local value="$1"
  local home="${HOME:-}"
  if [[ -n "$home" ]]; then
    value="${value//$home/<home>}"
  fi
  print -r -- "$value"
}

write_kv() {
  local file="$1"
  local key="$2"
  local value="$3"
  print -r -- "${key}=${value}" >> "$file"
}

bounded_copy() {
  local src="$1"
  local dest="$2"
  if [[ -f "$src" ]]; then
    head -c "$OUTPUT_LIMIT_BYTES" "$src" > "$dest"
  else
    : > "$dest"
  fi
}

run_bounded() {
  local timeout_seconds="$1"
  local out_file="$2"
  local err_file="$3"
  local status_file="$4"
  local duration_file="$5"
  local timeout_file="$6"
  shift 6

  local full_out="${out_file}.full"
  local full_err="${err_file}.full"
  local start_epoch end_epoch pid rc elapsed timed_out
  start_epoch="$(date +%s)"
  timed_out="no"

  ( "$@" > "$full_out" 2> "$full_err" ) &
  pid="$!"

  while kill -0 "$pid" 2>/dev/null; do
    elapsed=$(( $(date +%s) - start_epoch ))
    if (( elapsed >= timeout_seconds )); then
      timed_out="yes"
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null
      rc=124
      break
    fi
    sleep 0.2
  done

  if [[ "$timed_out" == "no" ]]; then
    wait "$pid" 2>/dev/null
    rc="$?"
  fi

  end_epoch="$(date +%s)"
  print -r -- "$rc" > "$status_file"
  print -r -- "$(( end_epoch - start_epoch ))" > "$duration_file"
  print -r -- "$timed_out" > "$timeout_file"
  bounded_copy "$full_out" "$out_file"
  bounded_copy "$full_err" "$err_file"
  rm -f "$full_out" "$full_err"
}

exact_fixture_exists() {
  /usr/bin/shortcuts list 2>/dev/null | awk -v target="$FIXTURE_NAME" '
    $0 == target { found = 1 }
    END { exit(found ? 0 : 1) }
  '
}

detect_run_command() {
  local help_text="$1"
  if grep -Eq '(^|[[:space:]])run([[:space:]]|$)' "$help_text"; then
    return 0
  fi
  /usr/bin/shortcuts run --help >/dev/null 2>&1
}

capture_subcommand_help() {
  local dest_dir="$1"
  local command_name="$2"
  local out_file="${dest_dir}/shortcuts-${command_name}-help.stdout.txt"
  local err_file="${dest_dir}/shortcuts-${command_name}-help.stderr.txt"
  local status_file="${dest_dir}/shortcuts-${command_name}-help.exit-code.txt"
  local duration_file="${dest_dir}/shortcuts-${command_name}-help.duration-seconds.txt"
  local timeout_file="${dest_dir}/shortcuts-${command_name}-help.timed-out.txt"
  run_bounded 10 "$out_file" "$err_file" "$status_file" "$duration_file" \
    "$timeout_file" /usr/bin/shortcuts "$command_name" --help
}

read_only_mode() {
  local root="$1"
  local artifact_dir="${root}/artifacts/spk-04/read-only"
  local summary="${artifact_dir}/summary.env"
  local shortcuts_available="no"
  local run_available="no"
  local gui_readable="no"
  local fixture_available="no"
  local result="FAIL"
  local uid gui_domain help_out help_err help_status

  mkdir -p "$artifact_dir"
  : > "$summary"

  uid="$(id -u)"
  gui_domain="gui/${uid}"
  help_out="${artifact_dir}/shortcuts-help.stdout.txt"
  help_err="${artifact_dir}/shortcuts-help.stderr.txt"
  help_status="${artifact_dir}/shortcuts-help.exit-code.txt"

  write_kv "$summary" "mode" "read-only"
  write_kv "$summary" "timestamp_utc" "$(timestamp_utc)"
  write_kv "$summary" "macos_product_version" "$(sw_vers -productVersion 2>/dev/null || print -r -- unavailable)"
  write_kv "$summary" "macos_build_version" "$(sw_vers -buildVersion 2>/dev/null || print -r -- unavailable)"
  write_kv "$summary" "architecture" "$(uname -m)"
  write_kv "$summary" "uid" "$uid"
  write_kv "$summary" "launchd_gui_domain" "$gui_domain"
  write_kv "$summary" "production_path_recommendation" "$PRODUCTION_PATH"
  write_kv "$summary" "launchctl_path" "$(command -v launchctl || print -r -- unavailable)"
  write_kv "$summary" "plutil_path" "$(command -v plutil || print -r -- unavailable)"
  write_kv "$summary" "man_path" "$(command -v man || print -r -- unavailable)"
  write_kv "$summary" "xcrun_path" "$(command -v xcrun || print -r -- unavailable)"
  write_kv "$summary" "swiftc_path" "$(command -v swiftc || print -r -- unavailable)"

  if [[ -x /usr/bin/shortcuts ]]; then
    shortcuts_available="yes"
    write_kv "$summary" "shortcuts_path" "/usr/bin/shortcuts"
    run_bounded 10 "$help_out" "$help_err" "$help_status" \
      "${artifact_dir}/shortcuts-help.duration-seconds.txt" \
      "${artifact_dir}/shortcuts-help.timed-out.txt" /usr/bin/shortcuts --help
    if detect_run_command "$help_out"; then
      run_available="yes"
    fi
    for subcommand in list run view sign; do
      capture_subcommand_help "$artifact_dir" "$subcommand"
    done
    MANPAGER=cat run_bounded 10 "${artifact_dir}/shortcuts-man.stdout.txt" \
      "${artifact_dir}/shortcuts-man.stderr.txt" \
      "${artifact_dir}/shortcuts-man.exit-code.txt" \
      "${artifact_dir}/shortcuts-man.duration-seconds.txt" \
      "${artifact_dir}/shortcuts-man.timed-out.txt" man shortcuts
    if exact_fixture_exists; then
      fixture_available="yes"
    fi
  else
    write_kv "$summary" "shortcuts_path" "unavailable"
    print -r -- "127" > "$help_status"
    : > "$help_out"
    : > "$help_err"
  fi

  if launchctl print "$gui_domain" > "${artifact_dir}/launchctl-gui-domain.txt" 2> "${artifact_dir}/launchctl-gui-domain.stderr.txt"; then
    gui_readable="yes"
  fi

  if [[ "$shortcuts_available" == "yes" && "$run_available" == "yes" && "$gui_readable" == "yes" ]]; then
    result="PASS"
  elif [[ "$shortcuts_available" == "yes" || "$gui_readable" == "yes" ]]; then
    result="PARTIAL"
  fi

  write_kv "$summary" "SPK04_READ_ONLY_RESULT" "$result"
  write_kv "$summary" "SHORTCUTS_CLI_AVAILABLE" "$shortcuts_available"
  write_kv "$summary" "SHORTCUTS_RUN_COMMAND_AVAILABLE" "$run_available"
  write_kv "$summary" "LAUNCHCTL_GUI_DOMAIN_READABLE" "$gui_readable"
  write_kv "$summary" "FIXTURE_AVAILABLE" "$fixture_available"

  print -r -- "SPK04_READ_ONLY_RESULT=${result}"
  print -r -- "SHORTCUTS_CLI_AVAILABLE=${shortcuts_available}"
  print -r -- "SHORTCUTS_RUN_COMMAND_AVAILABLE=${run_available}"
  print -r -- "LAUNCHCTL_GUI_DOMAIN_READABLE=${gui_readable}"
  print -r -- "FIXTURE_AVAILABLE=${fixture_available}"
  print -r -- "SPK04_READ_ONLY_ARTIFACTS=artifacts/spk-04/read-only"
}

write_helper_script() {
  local helper="$1"
  cat > "$helper" <<'HELPER'
#!/bin/zsh
set -u

readonly OUTPUT_LIMIT_BYTES=8192
readonly FIXTURE_NAME="Hermes Bridge SPK-04 Fixture"
readonly EXPECTED_RESPONSE="SPK04_SHORTCUT_RESPONSE"

bounded_copy() {
  local src="$1"
  local dest="$2"
  if [[ -f "$src" ]]; then
    head -c "$OUTPUT_LIMIT_BYTES" "$src" > "$dest"
  else
    : > "$dest"
  fi
}

sanitize_path_value() {
  local value="$1"
  local home="${HOME:-}"
  if [[ -n "$home" ]]; then
    value="${value//$home/<home>}"
  fi
  print -r -- "$value"
}

run_bounded() {
  local timeout_seconds="$1"
  local out_file="$2"
  local err_file="$3"
  local status_file="$4"
  local duration_file="$5"
  local timeout_file="$6"
  shift 6

  local full_out="${out_file}.full"
  local full_err="${err_file}.full"
  local start_epoch end_epoch pid rc elapsed timed_out
  start_epoch="$(date +%s)"
  timed_out="no"

  ( "$@" > "$full_out" 2> "$full_err" ) &
  pid="$!"

  while kill -0 "$pid" 2>/dev/null; do
    elapsed=$(( $(date +%s) - start_epoch ))
    if (( elapsed >= timeout_seconds )); then
      timed_out="yes"
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null
      rc=124
      break
    fi
    sleep 0.2
  done

  if [[ "$timed_out" == "no" ]]; then
    wait "$pid" 2>/dev/null
    rc="$?"
  fi

  end_epoch="$(date +%s)"
  print -r -- "$rc" > "$status_file"
  print -r -- "$(( end_epoch - start_epoch ))" > "$duration_file"
  print -r -- "$timed_out" > "$timeout_file"
  bounded_copy "$full_out" "$out_file"
  bounded_copy "$full_err" "$err_file"
  rm -f "$full_out" "$full_err"
}

exact_fixture_exists() {
  /usr/bin/shortcuts list 2>/dev/null | awk -v target="$FIXTURE_NAME" '
    $0 == target { found = 1 }
    END { exit(found ? 0 : 1) }
  '
}

artifact_dir="$1"
mkdir -p "$artifact_dir"

{
  print -r -- "uid=$(id -u)"
  print -r -- "home=<home>"
  print -r -- "path=${PATH:-}"
  print -r -- "tmpdir=$(sanitize_path_value "${TMPDIR:-}")"
  print -r -- "executable_path=/usr/bin/shortcuts"
  print -r -- "working_directory=$(sanitize_path_value "$PWD")"
} > "${artifact_dir}/launchagent-environment.env"

print -r -- "$$" > "${artifact_dir}/helper.pid"

run_bounded 10 \
  "${artifact_dir}/launchagent-shortcuts-help.stdout.txt" \
  "${artifact_dir}/launchagent-shortcuts-help.stderr.txt" \
  "${artifact_dir}/launchagent-shortcuts-help.exit-code.txt" \
  "${artifact_dir}/launchagent-shortcuts-help.duration-seconds.txt" \
  "${artifact_dir}/launchagent-shortcuts-help.timed-out.txt" \
  /usr/bin/shortcuts --help

if exact_fixture_exists; then
  print -r -- "yes" > "${artifact_dir}/fixture-available.txt"
  run_bounded 15 \
    "${artifact_dir}/fixture.stdout.raw.txt" \
    "${artifact_dir}/fixture.stderr.raw.txt" \
    "${artifact_dir}/fixture.exit-code.txt" \
    "${artifact_dir}/fixture.duration-seconds.txt" \
    "${artifact_dir}/fixture.timed-out.txt" \
    /usr/bin/shortcuts run "$FIXTURE_NAME"
  if grep -Fxq "$EXPECTED_RESPONSE" "${artifact_dir}/fixture.stdout.raw.txt"; then
    print -r -- "yes" > "${artifact_dir}/fixture-expected-response-received.txt"
  else
    print -r -- "no" > "${artifact_dir}/fixture-expected-response-received.txt"
  fi
  rm -f "${artifact_dir}/fixture.stdout.raw.txt" "${artifact_dir}/fixture.stderr.raw.txt"
else
  print -r -- "no" > "${artifact_dir}/fixture-available.txt"
  print -r -- "not-run" > "${artifact_dir}/fixture-expected-response-received.txt"
  print -r -- "not-run" > "${artifact_dir}/fixture.exit-code.txt"
  print -r -- "not-run" > "${artifact_dir}/fixture.duration-seconds.txt"
  print -r -- "not-run" > "${artifact_dir}/fixture.timed-out.txt"
fi

missing_name="Hermes Bridge SPK-04 Missing Fixture ${SPK04_LABEL:-unknown}"
run_bounded 10 \
  "${artifact_dir}/missing-fixture.stdout.txt" \
  "${artifact_dir}/missing-fixture.stderr.txt" \
  "${artifact_dir}/missing-fixture.exit-code.txt" \
  "${artifact_dir}/missing-fixture.duration-seconds.txt" \
  "${artifact_dir}/missing-fixture.timed-out.txt" \
  /usr/bin/shortcuts run "$missing_name"

print -r -- "done" > "${artifact_dir}/helper.done"
HELPER
  chmod 700 "$helper"
}

write_plist() {
  local plist="$1"
  local label="$2"
  local helper="$3"
  local artifact_dir="$4"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>${helper}</string>
    <string>${artifact_dir}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${PRODUCTION_PATH}</string>
    <key>SPK04_LABEL</key>
    <string>${label}</string>
  </dict>
  <key>StandardOutPath</key>
  <string>${artifact_dir}/launchagent.stdout.txt</string>
  <key>StandardErrorPath</key>
  <string>${artifact_dir}/launchagent.stderr.txt</string>
  <key>WorkingDirectory</key>
  <string>${artifact_dir}</string>
</dict>
</plist>
PLIST
}

active_mode() {
  local root="$1"
  local uid label gui_domain artifact_dir helper plist summary
  local bootstrap_rc bootout_rc cli_from_launchagent="no"
  local fixture_available="no" shortcut_execution="blocked"
  local expected_response="not-run" bootout_clean="no"
  local active_result="FAIL"
  local cleanup_done="no"

  uid="$(id -u)"
  label="com.hermes.spk04.$(date -u '+%Y%m%dT%H%M%SZ').$$"
  gui_domain="gui/${uid}"
  artifact_dir="${root}/artifacts/spk-04/active/${label}"
  helper="${artifact_dir}/launchagent-helper.zsh"
  plist="${artifact_dir}/${label}.plist"
  summary="${artifact_dir}/summary.env"

  cleanup() {
    if [[ "$cleanup_done" == "yes" ]]; then
      return
    fi
    launchctl bootout "$gui_domain" "$plist" > "${artifact_dir}/cleanup-bootout.stdout.txt" 2> "${artifact_dir}/cleanup-bootout.stderr.txt"
    cleanup_done="yes"
  }

  mkdir -p "$artifact_dir"
  : > "$summary"
  write_helper_script "$helper"
  write_plist "$plist" "$label" "$helper" "$artifact_dir"

  trap cleanup EXIT INT TERM

  if plutil -lint "$plist" > "${artifact_dir}/plist-validation.stdout.txt" 2> "${artifact_dir}/plist-validation.stderr.txt"; then
    write_kv "$summary" "plist_valid" "yes"
  else
    write_kv "$summary" "plist_valid" "no"
  fi

  write_kv "$summary" "mode" "active"
  write_kv "$summary" "timestamp_utc" "$(timestamp_utc)"
  write_kv "$summary" "label" "$label"
  write_kv "$summary" "gui_domain" "$gui_domain"
  write_kv "$summary" "shortcuts_path" "/usr/bin/shortcuts"
  write_kv "$summary" "production_path_recommendation" "$PRODUCTION_PATH"

  launchctl bootstrap "$gui_domain" "$plist" > "${artifact_dir}/bootstrap.stdout.txt" 2> "${artifact_dir}/bootstrap.stderr.txt"
  bootstrap_rc="$?"
  write_kv "$summary" "bootstrap_exit_code" "$bootstrap_rc"

  launchctl print "${gui_domain}/${label}" > "${artifact_dir}/launchctl-service-visible.txt" 2> "${artifact_dir}/launchctl-service-visible.stderr.txt"
  write_kv "$summary" "launchctl_visibility_exit_code" "$?"

  local waited=0
  while [[ ! -f "${artifact_dir}/helper.done" && "$waited" -lt 30 ]]; do
    sleep 1
    waited=$(( waited + 1 ))
  done
  write_kv "$summary" "helper_done_seen" "$([[ -f "${artifact_dir}/helper.done" ]] && print -r -- yes || print -r -- no)"

  if [[ -f "${artifact_dir}/helper.pid" ]]; then
    write_kv "$summary" "helper_pid" "$(cat "${artifact_dir}/helper.pid")"
  else
    write_kv "$summary" "helper_pid" "unavailable"
  fi

  if [[ -f "${artifact_dir}/launchagent-shortcuts-help.exit-code.txt" ]] &&
     [[ "$(cat "${artifact_dir}/launchagent-shortcuts-help.exit-code.txt")" == "0" ]]; then
    cli_from_launchagent="yes"
  fi

  if [[ -f "${artifact_dir}/fixture-available.txt" ]]; then
    fixture_available="$(cat "${artifact_dir}/fixture-available.txt")"
  fi
  if [[ "$fixture_available" == "yes" ]]; then
    shortcut_execution="no"
    if [[ -f "${artifact_dir}/fixture.exit-code.txt" ]] &&
       [[ "$(cat "${artifact_dir}/fixture.exit-code.txt")" == "0" ]]; then
      shortcut_execution="yes"
    fi
    expected_response="$(cat "${artifact_dir}/fixture-expected-response-received.txt" 2>/dev/null || print -r -- no)"
  fi

  launchctl bootout "$gui_domain" "$plist" > "${artifact_dir}/bootout.stdout.txt" 2> "${artifact_dir}/bootout.stderr.txt"
  bootout_rc="$?"
  cleanup_done="yes"
  write_kv "$summary" "bootout_exit_code" "$bootout_rc"

  sleep 1
  if launchctl print "${gui_domain}/${label}" > "${artifact_dir}/post-cleanup-service.stdout.txt" 2> "${artifact_dir}/post-cleanup-service.stderr.txt"; then
    bootout_clean="no"
  else
    bootout_clean="yes"
  fi

  if [[ -f "${artifact_dir}/helper.pid" ]]; then
    local helper_pid
    helper_pid="$(cat "${artifact_dir}/helper.pid")"
    if kill -0 "$helper_pid" 2>/dev/null; then
      print -r -- "running" > "${artifact_dir}/post-cleanup-process-state.txt"
    else
      print -r -- "not-running" > "${artifact_dir}/post-cleanup-process-state.txt"
    fi
  else
    print -r -- "no-helper-pid" > "${artifact_dir}/post-cleanup-process-state.txt"
  fi

  if [[ "$bootstrap_rc" == "0" && "$cli_from_launchagent" == "yes" && "$bootout_clean" == "yes" ]]; then
    if [[ "$fixture_available" == "yes" && "$shortcut_execution" == "yes" && "$expected_response" == "yes" ]]; then
      active_result="PASS"
    else
      active_result="PARTIAL"
    fi
  fi

  write_kv "$summary" "SPK04_ACTIVE_RESULT" "$active_result"
  write_kv "$summary" "LAUNCHAGENT_BOOTSTRAP_AVAILABLE" "$([[ "$bootstrap_rc" == "0" ]] && print -r -- yes || print -r -- no)"
  write_kv "$summary" "SHORTCUTS_CLI_FROM_LAUNCHAGENT" "$cli_from_launchagent"
  write_kv "$summary" "FIXTURE_AVAILABLE" "$fixture_available"
  write_kv "$summary" "SHORTCUT_EXECUTION_AVAILABLE" "$shortcut_execution"
  write_kv "$summary" "EXPECTED_RESPONSE_RECEIVED" "$expected_response"
  write_kv "$summary" "LAUNCHAGENT_BOOTOUT_CLEAN" "$bootout_clean"
  write_kv "$summary" "SPK04_UNIQUE_LABEL" "$label"

  trap - EXIT INT TERM

  print -r -- "SPK04_ACTIVE_RESULT=${active_result}"
  print -r -- "LAUNCHAGENT_BOOTSTRAP_AVAILABLE=$([[ "$bootstrap_rc" == "0" ]] && print -r -- yes || print -r -- no)"
  print -r -- "SHORTCUTS_CLI_FROM_LAUNCHAGENT=${cli_from_launchagent}"
  print -r -- "FIXTURE_AVAILABLE=${fixture_available}"
  print -r -- "SHORTCUT_EXECUTION_AVAILABLE=${shortcut_execution}"
  print -r -- "EXPECTED_RESPONSE_RECEIVED=${expected_response}"
  print -r -- "LAUNCHAGENT_BOOTOUT_CLEAN=${bootout_clean}"
  print -r -- "SPK04_UNIQUE_LABEL=${label}"
  print -r -- "SPK04_ACTIVE_ARTIFACTS=artifacts/spk-04/active/${label}"
}

main() {
  local active="no"
  local root

  while (( $# > 0 )); do
    case "$1" in
      --active-test)
        active="yes"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "unknown argument: $1"
        ;;
    esac
    shift
  done

  root="$(repo_root)" || die "must be run from a git repository"
  cd "$root" || die "failed to enter repository root"

  if [[ "$active" == "yes" ]]; then
    active_mode "$root"
  else
    read_only_mode "$root"
  fi
}

main "$@"
