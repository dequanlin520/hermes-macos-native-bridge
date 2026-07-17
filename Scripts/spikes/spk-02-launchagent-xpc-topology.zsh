#!/usr/bin/env zsh
set -u

SCRIPT_NAME="${0:t}"
REPO_ROOT="$(cd "${0:A:h}/../.." && pwd)"
ARTIFACT_ROOT="${REPO_ROOT}/artifacts/spk-02"
BUILD_ROOT="${ARTIFACT_ROOT}/build"
LOG_DIR="${ARTIFACT_ROOT}/logs"
MODULE_CACHE_DIR="${BUILD_ROOT}/module-cache"
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
RUN_LOG="${LOG_DIR}/read-only-${TIMESTAMP}.log"

ACTIVE_TEST="no"
for arg in "$@"; do
  case "${arg}" in
    --active-test)
      ACTIVE_TEST="yes"
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: Scripts/spikes/spk-02-launchagent-xpc-topology.zsh [--active-test]

Default mode is read-only. It inspects local LaunchAgent/XPC development
capabilities and writes generated probes under artifacts/spk-02.

--active-test runs an isolated launchd Mach-service/XPC experiment under
artifacts/spk-02/active without installing a permanent LaunchAgent.
USAGE
      exit 0
      ;;
    *)
      print -u2 "Unknown argument: ${arg}"
      exit 2
      ;;
  esac
done

mkdir -p "${BUILD_ROOT}" "${LOG_DIR}" "${MODULE_CACHE_DIR}"
: > "${RUN_LOG}"

log() {
  print -r -- "$*" | tee -a "${RUN_LOG}"
}

section() {
  log ""
  log "## $*"
}

command_available() {
  command -v "$1" >/dev/null 2>&1
}

capture_command() {
  local name="$1"
  shift
  local output_file="${LOG_DIR}/${TIMESTAMP}-${name}.txt"

  log "\$ $*"
  if "$@" >"${output_file}" 2>&1; then
    sed -n '1,80p' "${output_file}" | tee -a "${RUN_LOG}" >/dev/null
    local line_count
    line_count="$(wc -l < "${output_file}" | tr -d ' ')"
    if [[ "${line_count}" -gt 80 ]]; then
      log "[truncated in console log; full output: ${output_file}]"
    fi
    return 0
  else
    local exit_status=$?
    sed -n '1,80p' "${output_file}" | tee -a "${RUN_LOG}" >/dev/null
    log "[exit ${exit_status}; output: ${output_file}]"
    return "${exit_status}"
  fi
}

summary_value() {
  local key="$1"
  local value="$2"
  print -r -- "${key}=${value}" | tee -a "${RUN_LOG}"
}

if [[ "${ACTIVE_TEST}" == "yes" ]]; then
  uid="$(id -u)"
  gui_domain="gui/${uid}"
  unique_label="com.hermes.spk02.${TIMESTAMP}.$$"
  active_root="${ARTIFACT_ROOT}/active/${unique_label}"
  active_build_root="${active_root}/build"
  active_log_root="${active_root}/logs"
  active_module_cache="${active_build_root}/module-cache"
  RUN_LOG="${active_log_root}/active-${TIMESTAMP}.log"

  server_source="${active_build_root}/SPK02Server.swift"
  client_source="${active_build_root}/SPK02Client.swift"
  server_binary="${active_build_root}/spk02-server"
  client_binary="${active_build_root}/spk02-client"
  plist_path="${active_root}/${unique_label}.plist"
  server_stdout="${active_log_root}/server.stdout.log"
  server_stderr="${active_log_root}/server.stderr.log"
  client_output_file="${active_log_root}/client-output.txt"
  launchctl_pre_file="${active_log_root}/launchctl-pre-print.txt"
  launchctl_domain_before_file="${active_log_root}/launchctl-domain-before.txt"
  launchctl_post_bootstrap_file="${active_log_root}/launchctl-post-bootstrap-print.txt"
  launchctl_post_client_file="${active_log_root}/launchctl-post-client-print.txt"
  launchctl_post_cleanup_file="${active_log_root}/launchctl-post-cleanup-print.txt"
  process_post_cleanup_file="${active_log_root}/process-post-cleanup.txt"

  mkdir -p "${active_build_root}" "${active_log_root}" "${active_module_cache}"
  : > "${RUN_LOG}"

  launchagent_bootstrap_available="no"
  mach_service_visible="no"
  xpc_roundtrip_available="no"
  launchagent_bootout_clean="no"
  active_failures=0
  active_bootstrapped="no"
  bootout_attempted="no"
  server_pid=""

  cleanup() {
    local cleanup_status=$?
    trap - EXIT INT TERM

    if [[ "${active_bootstrapped}" == "yes" && "${bootout_attempted}" != "yes" ]]; then
      launchctl bootout "${gui_domain}/${unique_label}" >>"${RUN_LOG}" 2>&1 || true
      bootout_attempted="yes"
    fi

    if [[ -n "${server_pid}" ]]; then
      if kill -0 "${server_pid}" >/dev/null 2>&1; then
        kill -TERM "${server_pid}" >>"${RUN_LOG}" 2>&1 || true
        sleep 1
      fi
    fi

    exit "${cleanup_status}"
  }
  trap cleanup EXIT INT TERM

  log "SPK-02 LaunchAgent/XPC topology active experiment"
  log "Artifacts: ${active_root}"
  log "Timestamp UTC: ${TIMESTAMP}"
  log "Mode: active-test"
  log "Unique label: ${unique_label}"
  log "GUI launchd domain: ${gui_domain}"

  section "Preflight"
  for required_command in swiftc plutil launchctl; do
    if command_available "${required_command}"; then
      log "${required_command}=available"
    else
      log "${required_command}=missing"
      (( active_failures++ ))
    fi
  done

  log "\$ launchctl print ${gui_domain}/${unique_label}"
  if launchctl print "${gui_domain}/${unique_label}" >"${launchctl_pre_file}" 2>&1; then
    log "pre_existing_registration=yes"
    (( active_failures++ ))
  else
    log "pre_existing_registration=no"
  fi

  log "\$ launchctl print ${gui_domain}"
  if launchctl print "${gui_domain}" >"${launchctl_domain_before_file}" 2>&1; then
    log "gui_domain_recorded=yes"
  else
    log "gui_domain_recorded=no"
    (( active_failures++ ))
  fi

  section "Generate Sources"
  cat > "${server_source}" <<'SWIFT'
import Foundation

@objc(SPK02V1Protocol) protocol SPK02V1Protocol {
  func ping(_ request: String, withReply reply: @escaping (String) -> Void)
}

final class SPK02Service: NSObject, SPK02V1Protocol, NSXPCListenerDelegate {
  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    emit("SPK02_SERVER_CONNECTION=accepted")
    connection.exportedInterface = NSXPCInterface(with: SPK02V1Protocol.self)
    connection.exportedObject = self
    connection.resume()
    return true
  }

  func ping(_ request: String, withReply reply: @escaping (String) -> Void) {
    if request == "SPK02_REQUEST" {
      emit("SPK02_SERVER_REQUEST=accepted")
      reply("SPK02_RESPONSE")
    } else {
      emit("SPK02_SERVER_REQUEST=rejected")
      reply("SPK02_REJECTED")
    }
  }
}

func emit(_ line: String) {
  let data = Data((line + "\n").utf8)
  FileHandle.standardOutput.write(data)
}

guard CommandLine.arguments.count == 2 else {
  emit("SPK02_SERVER_ERROR=missing_service_name")
  exit(64)
}

let serviceName = CommandLine.arguments[1]
let service = SPK02Service()
let listener = NSXPCListener(machServiceName: serviceName)
listener.delegate = service
listener.resume()
emit("SPK02_SERVER_STARTED=\(serviceName)")

let timeout = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
timeout.schedule(deadline: .now() + 60)
timeout.setEventHandler {
  emit("SPK02_SERVER_TIMEOUT=exit")
  exit(0)
}
timeout.resume()

RunLoop.main.run()
SWIFT

  cat > "${client_source}" <<'SWIFT'
import Foundation

@objc(SPK02V1Protocol) protocol SPK02V1Protocol {
  func ping(_ request: String, withReply reply: @escaping (String) -> Void)
}

guard CommandLine.arguments.count == 2 else {
  print("SPK02_CLIENT_ERROR=missing_service_name")
  exit(64)
}

let serviceName = CommandLine.arguments[1]
let connection = NSXPCConnection(machServiceName: serviceName, options: [])
connection.remoteObjectInterface = NSXPCInterface(with: SPK02V1Protocol.self)
connection.resume()

let semaphore = DispatchSemaphore(value: 0)
var response = ""
var failed = false

connection.interruptionHandler = {
  failed = true
  semaphore.signal()
}

connection.invalidationHandler = {
  if response.isEmpty {
    failed = true
    semaphore.signal()
  }
}

if let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
  print("SPK02_CLIENT_ERROR=\(error.localizedDescription)")
  failed = true
  semaphore.signal()
}) as? SPK02V1Protocol {
  proxy.ping("SPK02_REQUEST") { value in
    response = value
    print("SPK02_XPC_RESPONSE=\(value)")
    semaphore.signal()
  }
} else {
  print("SPK02_CLIENT_ERROR=proxy_unavailable")
  failed = true
  semaphore.signal()
}

let waitResult = semaphore.wait(timeout: .now() + 10)
connection.invalidate()

if waitResult == .timedOut {
  print("SPK02_CLIENT_ERROR=timeout")
  exit(70)
}

if failed || response != "SPK02_RESPONSE" {
  exit(1)
}

exit(0)
SWIFT
  log "server_source=${server_source}"
  log "client_source=${client_source}"

  section "Compile"
  if [[ "${active_failures}" -eq 0 ]]; then
    capture_command "active-swiftc-server" env CLANG_MODULE_CACHE_PATH="${active_module_cache}" swiftc "${server_source}" -o "${server_binary}" || (( active_failures++ ))
    capture_command "active-swiftc-client" env CLANG_MODULE_CACHE_PATH="${active_module_cache}" swiftc "${client_source}" -o "${client_binary}" || (( active_failures++ ))
  fi

  section "Generate LaunchAgent Plist"
  cat > "${plist_path}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${unique_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${server_binary}</string>
    <string>${unique_label}</string>
  </array>
  <key>MachServices</key>
  <dict>
    <key>${unique_label}</key>
    <true/>
  </dict>
  <key>StandardOutPath</key>
  <string>${server_stdout}</string>
  <key>StandardErrorPath</key>
  <string>${server_stderr}</string>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
PLIST

  if [[ "${active_failures}" -eq 0 ]]; then
    capture_command "active-plutil-lint" plutil -lint "${plist_path}" || (( active_failures++ ))
  fi

  section "Bootstrap"
  bootstrap_exit=1
  if [[ "${active_failures}" -eq 0 ]]; then
    log "\$ launchctl bootstrap ${gui_domain} ${plist_path}"
    if launchctl bootstrap "${gui_domain}" "${plist_path}" >>"${RUN_LOG}" 2>&1; then
      bootstrap_exit=0
      active_bootstrapped="yes"
      launchagent_bootstrap_available="yes"
    else
      bootstrap_exit=$?
      (( active_failures++ ))
    fi
    log "bootstrap_exit_code=${bootstrap_exit}"
  fi

  section "Launchctl Visibility"
  if [[ "${active_bootstrapped}" == "yes" ]]; then
    log "\$ launchctl print ${gui_domain}/${unique_label}"
    if launchctl print "${gui_domain}/${unique_label}" >"${launchctl_post_bootstrap_file}" 2>&1; then
      sed -n '1,80p' "${launchctl_post_bootstrap_file}" | tee -a "${RUN_LOG}" >/dev/null
      if grep -q "${unique_label}" "${launchctl_post_bootstrap_file}"; then
        mach_service_visible="yes"
      fi
    else
      log "launchctl_print_registered=no"
      (( active_failures++ ))
    fi
  fi

  section "XPC Round Trip"
  client_exit=1
  if [[ "${mach_service_visible}" == "yes" ]]; then
    log "\$ ${client_binary} ${unique_label}"
    if "${client_binary}" "${unique_label}" >"${client_output_file}" 2>&1; then
      client_exit=0
    else
      client_exit=$?
    fi
    sed -n '1,80p' "${client_output_file}" | tee -a "${RUN_LOG}" >/dev/null
    log "client_exit_code=${client_exit}"

    if [[ "${client_exit}" -eq 0 ]] && grep -qx "SPK02_XPC_RESPONSE=SPK02_RESPONSE" "${client_output_file}"; then
      xpc_roundtrip_available="yes"
    else
      (( active_failures++ ))
    fi

    sleep 1
    log "\$ launchctl print ${gui_domain}/${unique_label}"
    if launchctl print "${gui_domain}/${unique_label}" >"${launchctl_post_client_file}" 2>&1; then
      server_pid="$(awk -F'= ' '/^[[:space:]]*pid = [0-9]+/ { print $2; exit }' "${launchctl_post_client_file}" | tr -dc '0-9')"
      if [[ -n "${server_pid}" ]]; then
        log "server_pid=${server_pid}"
      else
        log "server_pid=unavailable"
      fi
    fi
  fi

  section "Bootout"
  bootout_exit=1
  if [[ "${active_bootstrapped}" == "yes" ]]; then
    log "\$ launchctl bootout ${gui_domain}/${unique_label}"
    if launchctl bootout "${gui_domain}/${unique_label}" >>"${RUN_LOG}" 2>&1; then
      bootout_exit=0
      bootout_attempted="yes"
      active_bootstrapped="no"
    else
      bootout_exit=$?
      bootout_attempted="yes"
      (( active_failures++ ))
    fi
    log "bootout_exit_code=${bootout_exit}"
  fi

  section "Post-cleanup Evidence"
  if launchctl print "${gui_domain}/${unique_label}" >"${launchctl_post_cleanup_file}" 2>&1; then
    log "post_cleanup_registration=present"
    (( active_failures++ ))
  else
    log "post_cleanup_registration=absent"
  fi

  if [[ -n "${server_pid}" ]]; then
    if ps -p "${server_pid}" >"${process_post_cleanup_file}" 2>&1; then
      log "post_cleanup_server_process=present"
      (( active_failures++ ))
    else
      log "post_cleanup_server_process=absent"
    fi
  else
    log "post_cleanup_server_process=not_observed"
  fi

  if [[ "${bootout_exit}" -eq 0 ]] && ! launchctl print "${gui_domain}/${unique_label}" >/dev/null 2>&1; then
    if [[ -z "${server_pid}" ]] || ! ps -p "${server_pid}" >/dev/null 2>&1; then
      launchagent_bootout_clean="yes"
    fi
  fi

  section "Safety Confirmation"
  log "No sudo was used."
  log "No LaunchAgent was installed or written to ~/Library/LaunchAgents."
  log "Only the generated label was bootstrapped and booted out: ${unique_label}"
  log "No broad process termination command was used."
  log "Generated active sources, binaries, plist, and logs are under ${active_root}."

  section "Summary"
  if [[ "${active_failures}" -eq 0 && "${launchagent_bootstrap_available}" == "yes" && "${mach_service_visible}" == "yes" && "${xpc_roundtrip_available}" == "yes" && "${launchagent_bootout_clean}" == "yes" ]]; then
    active_result="PASS"
  elif [[ "${launchagent_bootstrap_available}" == "yes" || "${mach_service_visible}" == "yes" || "${xpc_roundtrip_available}" == "yes" || "${launchagent_bootout_clean}" == "yes" ]]; then
    active_result="PARTIAL"
  else
    active_result="FAIL"
  fi

  summary_value "SPK02_ACTIVE_RESULT" "${active_result}"
  summary_value "LAUNCHAGENT_BOOTSTRAP_AVAILABLE" "${launchagent_bootstrap_available}"
  summary_value "MACH_SERVICE_VISIBLE" "${mach_service_visible}"
  summary_value "XPC_ROUNDTRIP_AVAILABLE" "${xpc_roundtrip_available}"
  summary_value "LAUNCHAGENT_BOOTOUT_CLEAN" "${launchagent_bootout_clean}"
  summary_value "SPK02_UNIQUE_LABEL" "${unique_label}"
  summary_value "SPK02_ARTIFACT_LOG" "${RUN_LOG}"

  trap - EXIT INT TERM
  case "${active_result}" in
    PASS) exit 0 ;;
    PARTIAL) exit 1 ;;
    *) exit 1 ;;
  esac
fi

uid="$(id -u)"
gui_domain="gui/${uid}"

swift_build_available="no"
xpc_compile_available="no"
xcode_available="no"
launchctl_gui_domain_readable="no"
required_failures=0

log "SPK-02 LaunchAgent/XPC topology read-only inspection"
log "Repository: ${REPO_ROOT}"
log "Artifacts: ${ARTIFACT_ROOT}"
log "Timestamp UTC: ${TIMESTAMP}"
log "Mode: read-only"

section "System"
capture_command "sw_vers" sw_vers || (( required_failures++ ))
capture_command "uname-m" uname -m || (( required_failures++ ))
capture_command "id-u" id -u || (( required_failures++ ))
log "Expected per-user launchd GUI domain: ${gui_domain}"

section "launchctl"
if command_available launchctl; then
  capture_command "launchctl-help" launchctl help || true
  launchctl_help_file="${LOG_DIR}/${TIMESTAMP}-launchctl-help.txt"
  for subcommand in print bootstrap bootout enable disable kickstart blame procinfo; do
    if grep -Eq "(^|[[:space:]])${subcommand}([[:space:]]|$)" "${launchctl_help_file}" 2>/dev/null; then
      log "launchctl_subcommand_${subcommand}=available"
    else
      log "launchctl_subcommand_${subcommand}=unknown"
    fi
  done
  if capture_command "launchctl-print-gui-domain" launchctl print "${gui_domain}"; then
    launchctl_gui_domain_readable="yes"
  else
    (( required_failures++ ))
  fi
else
  log "launchctl not found"
  (( required_failures++ ))
fi

section "Developer Tools"
if command_available codesign; then
  capture_command "codesign-location" command -v codesign || true
  capture_command "codesign-help" codesign -h || true
else
  log "codesign not found"
fi

if command_available xcrun; then
  capture_command "xcrun-location" command -v xcrun || true
  capture_command "xcrun-version" xcrun --version || true
else
  log "xcrun not found"
fi

if command_available xcode-select; then
  capture_command "xcode-select-p" xcode-select -p && xcode_available="yes" || true
else
  log "xcode-select not found"
fi

if command_available xcodebuild; then
  if capture_command "xcodebuild-version" xcodebuild -version; then
    xcode_available="yes"
  fi
else
  log "xcodebuild not found"
fi

if command_available swift; then
  capture_command "swift-version" swift --version || true
else
  log "swift not found"
fi

if command_available clang; then
  capture_command "clang-version" clang --version || true
else
  log "clang not found"
fi

section "Swift and XPC Compile Probes"
swift_source="${BUILD_ROOT}/Minimal.swift"
swift_binary="${BUILD_ROOT}/minimal-swift"
xpc_source="${BUILD_ROOT}/XPCProbe.swift"

cat > "${swift_source}" <<'SWIFT'
import Foundation

let message = "SPK02_MINIMAL_SWIFT_OK"
print(message)
SWIFT

cat > "${xpc_source}" <<'SWIFT'
import Foundation

let _ = NSXPCConnection.self
let _ = NSXPCInterface.self
let _ = Protocol.self
SWIFT

if command_available swiftc; then
  if capture_command "swiftc-minimal-build" env CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" swiftc "${swift_source}" -o "${swift_binary}"; then
    if capture_command "swiftc-minimal-run" "${swift_binary}"; then
      if grep -q "SPK02_MINIMAL_SWIFT_OK" "${LOG_DIR}/${TIMESTAMP}-swiftc-minimal-run.txt"; then
        swift_build_available="yes"
      fi
    fi
  fi

  if capture_command "swiftc-xpc-typecheck" env CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" swiftc -typecheck "${xpc_source}"; then
    xpc_compile_available="yes"
  fi
else
  log "swiftc not found"
fi

section "plist Validation"
plist_probe="${BUILD_ROOT}/com.hermes.spk02.example.plist"
cat > "${plist_probe}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.hermes.spk02.example</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/true</string>
  </array>
  <key>RunAtLoad</key>
  <false/>
  <key>MachServices</key>
  <dict>
    <key>com.hermes.spk02.example.xpc</key>
    <true/>
  </dict>
</dict>
</plist>
PLIST

if command_available plutil; then
  capture_command "plutil-help" plutil -help || true
  capture_command "plutil-lint-probe" plutil -lint "${plist_probe}" || (( required_failures++ ))
else
  log "plutil not found"
  (( required_failures++ ))
fi

section "Local Documentation Availability"
if command_available man; then
  for page in launchd.plist launchctl xpcd xpcservice.plist; do
    capture_command "man-w-${page//./-}" man -w "${page}" || true
  done
else
  log "man not found"
fi

section "Safety Confirmation"
log "No sudo was used."
log "No LaunchAgent was installed or written to ~/Library/LaunchAgents."
log "No launchd state-changing subcommands were run."
log "No Keychain, browser data, or unrelated user files were inspected."
log "Generated probes and build outputs are under ${ARTIFACT_ROOT}."

section "Summary"
if [[ "${swift_build_available}" == "yes" && "${xpc_compile_available}" == "yes" && "${launchctl_gui_domain_readable}" == "yes" && "${required_failures}" -eq 0 ]]; then
  read_only_result="PASS"
elif [[ "${required_failures}" -le 1 && ( "${swift_build_available}" == "yes" || "${xpc_compile_available}" == "yes" || "${launchctl_gui_domain_readable}" == "yes" ) ]]; then
  read_only_result="PARTIAL"
else
  read_only_result="FAIL"
fi

summary_value "SPK02_READ_ONLY_RESULT" "${read_only_result}"
summary_value "SWIFT_BUILD_AVAILABLE" "${swift_build_available}"
summary_value "XPC_COMPILE_AVAILABLE" "${xpc_compile_available}"
summary_value "XCODE_AVAILABLE" "${xcode_available}"
summary_value "LAUNCHCTL_GUI_DOMAIN_READABLE" "${launchctl_gui_domain_readable}"
summary_value "SPK02_ARTIFACT_LOG" "${RUN_LOG}"

case "${read_only_result}" in
  PASS|PARTIAL) exit 0 ;;
  *) exit 1 ;;
esac
