#!/usr/bin/env zsh
set -u
set -o pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h}
ARTIFACT_ROOT="${REPO_ROOT}/artifacts/spk-06"
READ_ONLY_DIR="${ARTIFACT_ROOT}/read-only"
ACTIVE_DIR="${ARTIFACT_ROOT}/active"

ACTIVE_TEST=no
if [[ $# -gt 1 ]]; then
  print -r -- "usage: $0 [--active-test]" >&2
  exit 64
fi
if [[ $# -eq 1 ]]; then
  if [[ "$1" == "--active-test" ]]; then
    ACTIVE_TEST=yes
  else
    print -r -- "usage: $0 [--active-test]" >&2
    exit 64
  fi
fi

mkdir -p "${READ_ONLY_DIR}/probes" "${ACTIVE_DIR}"

log() {
  print -r -- "$*"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

write_probe() {
  local name="$1"
  local body="$2"
  local file="${READ_ONLY_DIR}/probes/${name}.swift"
  print -r -- "$body" > "$file"
  print -r -- "$file"
}

run_typecheck() {
  local label="$1"
  local file="$2"
  local logfile="${READ_ONLY_DIR}/${label}.log"
  if xcrun swiftc -parse-as-library -typecheck -target arm64-apple-macos13.0 "$file" >"$logfile" 2>&1; then
    print -r -- "yes"
  else
    print -r -- "no"
  fi
}

find_appintents_interface() {
  local sdk_path="$1"
  local candidate
  for candidate in \
    "${sdk_path}/System/Library/Frameworks/AppIntents.framework/Modules/AppIntents.swiftmodule/arm64-apple-macos.swiftinterface" \
    "${sdk_path}/System/Library/Frameworks/AppIntents.framework/Modules/AppIntents.swiftmodule/x86_64-apple-macos.swiftinterface" \
    "${sdk_path}/System/Library/Frameworks/AppIntents.framework/Modules/AppIntents.swiftmodule/arm64e-apple-macos.swiftinterface"; do
    if [[ -f "$candidate" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}

run_read_only() {
  log "SPK-06 read-only AppIntents validation"
  mkdir -p "$READ_ONLY_DIR"

  local xcode_available=no
  local appintents_framework_available=no
  local appintent_compile_available=no
  local appshortcuts_provider_compile_available=no

  local os_version arch xcode_version swift_version sdk_path deployment_target interface_file
  os_version="$(sw_vers -productVersion 2>/dev/null || true)"
  arch="$(uname -m)"
  deployment_target="macOS 13.0"

  if have_cmd xcodebuild && have_cmd xcrun; then
    xcode_available=yes
    xcode_version="$(xcodebuild -version 2>&1 | tr '\n' '; ')"
    swift_version="$(xcrun swift --version 2>&1 | head -n 1)"
    sdk_path="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  else
    xcode_version="unavailable"
    swift_version="unavailable"
    sdk_path=""
  fi

  if [[ -n "$sdk_path" && -d "${sdk_path}/System/Library/Frameworks/AppIntents.framework" ]]; then
    appintents_framework_available=yes
  fi

  {
    print -r -- "macOS=${os_version}"
    print -r -- "architecture=${arch}"
    print -r -- "xcode=${xcode_version}"
    print -r -- "swift=${swift_version}"
    print -r -- "sdk_path=${sdk_path}"
    print -r -- "deployment_target=${deployment_target}"
    print -r -- "appintents_framework=${appintents_framework_available}"
  } > "${READ_ONLY_DIR}/environment.txt"

  local minimal_probe appshortcuts_probe api_probe foreground_probe cancellation_probe summary_probe progress_probe long_running_probe
  minimal_probe="$(write_probe minimal-appintent 'import AppIntents

@available(macOS 13.0, *)
struct SPK06MinimalIntent: AppIntent {
    static var title: LocalizedStringResource = "SPK06 Minimal"

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
')"

  appshortcuts_probe="$(write_probe appshortcuts-provider 'import AppIntents

@available(macOS 13.0, *)
struct SPK06ShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "SPK06 Shortcut"
    func perform() async throws -> some IntentResult { .result() }
}

@available(macOS 13.0, *)
struct SPK06AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SPK06ShortcutIntent(), phrases: ["Run SPK06 in \(.applicationName)"])
    }
}
')"

  api_probe="$(write_probe appintent-api-surface 'import AppIntents

@available(macOS 13.0, *)
struct SPK06APISurfaceIntent: AppIntent {
    static var title: LocalizedStringResource = "SPK06 API Surface"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Binding")
    var binding: String

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$binding)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: IntentDialog("ACCEPTED"))
    }
}
')"

  foreground_probe="$(write_probe foreground-continuation 'import AppIntents

@available(macOS 26.0, *)
struct SPK06ForegroundIntent: AppIntent {
    static var title: LocalizedStringResource = "SPK06 Foreground"
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        try await continueInForeground(IntentDialog("Continue"), alwaysConfirm: false)
        return .result()
    }
}
')"

  cancellation_probe="$(write_probe cancellation-signal 'import AppIntents

@available(macOS 26.4, *)
struct SPK06CancellationIntent: CancellableIntent {
    static var title: LocalizedStringResource = "SPK06 Cancellation"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await withIntentCancellationHandler {
            if Task.isCancelled {
                return
            }
        } onCancel: { reason in
            _ = reason
        }
        return .result(dialog: IntentDialog("ACCEPTED"))
    }
}
')"

  summary_probe="$(write_probe parameter-summary 'import AppIntents

@available(macOS 13.0, *)
struct SPK06SummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "SPK06 Summary"
    @Parameter(title: "Request") var request: String
    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$request)")
    }
    func perform() async throws -> some IntentResult { .result() }
}
')"

  progress_probe="$(write_probe progress-api-negative 'import AppIntents
import Foundation

@available(macOS 13.0, *)
struct SPK06ProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "SPK06 Progress"
    func perform() async throws -> some IntentResult {
        let progress = Progress(totalUnitCount: 10)
        progress.completedUnitCount = 1
        return .result()
    }
}
')"

  long_running_probe="$(write_probe progress-and-long-running-intent 'import AppIntents
import Foundation

@available(macOS 14.0, *)
struct SPK06ProgressReportingIntent: ProgressReportingIntent {
    static var title: LocalizedStringResource = "SPK06 Progress Reporting"
    func perform() async throws -> some IntentResult {
        progress.totalUnitCount = 10
        progress.completedUnitCount = 1
        return .result()
    }
}

@available(macOS 27.0, *)
struct SPK06LongRunningIntent: LongRunningIntent {
    static var title: LocalizedStringResource = "SPK06 Long Running"
    func perform() async throws -> some IntentResult {
        _ = try await performBackgroundTask {
            return "done"
        }
        return .result()
    }
}
')"

  if [[ "$xcode_available" == yes ]]; then
    appintent_compile_available="$(run_typecheck minimal-appintent "$minimal_probe")"
    appshortcuts_provider_compile_available="$(run_typecheck appshortcuts-provider "$appshortcuts_probe")"
    run_typecheck appintent-api-surface "$api_probe" > "${READ_ONLY_DIR}/appintent-api-surface.result"
    run_typecheck foreground-continuation "$foreground_probe" > "${READ_ONLY_DIR}/foreground-continuation.result"
    run_typecheck cancellation-signal "$cancellation_probe" > "${READ_ONLY_DIR}/cancellation-signal.result"
    run_typecheck parameter-summary "$summary_probe" > "${READ_ONLY_DIR}/parameter-summary.result"
    run_typecheck progress-api-negative "$progress_probe" > "${READ_ONLY_DIR}/progress-api-negative.result"
    run_typecheck progress-and-long-running-intent "$long_running_probe" > "${READ_ONLY_DIR}/progress-and-long-running-intent.result"
  fi

  if [[ -n "$sdk_path" ]] && interface_file="$(find_appintents_interface "$sdk_path")"; then
    {
      print -r -- "interface=${interface_file}"
      for symbol in "protocol AppIntent" "protocol IntentResult" "struct IntentDialog" "openAppWhenRun" "continueInForeground" "requestToContinueInForeground" "protocol CancellableIntent" "IntentCancellationReason" "ParameterSummary" "protocol AppShortcutsProvider" "ProgressReportingIntent" "LongRunningIntent"; do
        if /usr/bin/grep -n "$symbol" "$interface_file" | head -n 20; then
          :
        else
          print -r -- "NO_MATCH ${symbol}"
        fi
      done
    } > "${READ_ONLY_DIR}/appintents-interface-symbols.txt"
  else
    print -r -- "No textual AppIntents swiftinterface found in SDK." > "${READ_ONLY_DIR}/appintents-interface-symbols.txt"
  fi

  local doc_hits=0
  if [[ -d /Applications/Xcode.app/Contents/Developer/DocumentationCache ]]; then
    doc_hits=$(/usr/bin/find /Applications/Xcode.app/Contents/Developer/DocumentationCache -iname '*AppIntents*' 2>/dev/null | wc -l | tr -d ' ')
  fi
  {
    print -r -- "local_xcode_doc_appintents_hits=${doc_hits}"
    print -r -- "codesign=$(command -v codesign 2>/dev/null || true)"
    print -r -- "simctl=$(xcrun -f simctl 2>/dev/null || true)"
    print -r -- "devicectl=$(xcrun -f devicectl 2>/dev/null || true)"
  } > "${READ_ONLY_DIR}/tooling.txt"

  local read_only_result=FAIL
  if [[ "$xcode_available" == yes && "$appintents_framework_available" == yes && "$appintent_compile_available" == yes ]]; then
    read_only_result=PASS
  elif [[ "$xcode_available" == yes || "$appintents_framework_available" == yes || "$appintent_compile_available" == yes ]]; then
    read_only_result=PARTIAL
  fi

  log "SPK06_READ_ONLY_RESULT=${read_only_result}"
  log "APPINTENTS_FRAMEWORK_AVAILABLE=${appintents_framework_available}"
  log "APPINTENT_COMPILE_AVAILABLE=${appintent_compile_available}"
  log "APPSHORTCUTS_PROVIDER_COMPILE_AVAILABLE=${appshortcuts_provider_compile_available}"
  log "XCODE_AVAILABLE=${xcode_available}"
}

write_active_source() {
  mkdir -p "${ACTIVE_DIR}/src"
  cat > "${ACTIVE_DIR}/src/SPK06Prototype.swift" <<'SWIFT'
import Foundation

let allowedBinding = "spk06.approved.binding"
let fixedOperation = "delayedFixedResult"

struct Request: Codable {
    let schemaVersion: Int
    let bindingID: String
    let operation: String
    let requestID: String
    let delaySeconds: Int
    let createdAt: String
}

struct StatusRecord: Codable {
    var schemaVersion: Int
    var requestID: String
    var bindingID: String
    var operation: String
    var state: String
    var createdAt: String
    var updatedAt: String
    var detail: String
    var result: String?
    var workerPID: Int32?
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let decoder = JSONDecoder()
let fm = FileManager.default

func now() -> String {
    ISO8601DateFormatter().string(from: Date())
}

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: SPK06Prototype <root> <worker|submit|status|cancel> [...]\n".utf8))
    exit(64)
}

func path(_ root: URL, _ components: String...) -> URL {
    components.reduce(root) { $0.appendingPathComponent($1) }
}

func ensureDirs(_ root: URL) throws {
    for dir in ["queue", "inflight", "status", "cancel"] {
        try fm.createDirectory(at: path(root, dir), withIntermediateDirectories: true)
    }
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let data = try encoder.encode(value)
    try data.write(to: url, options: [.atomic])
}

func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    let data = try Data(contentsOf: url)
    return try decoder.decode(type, from: data)
}

func statusURL(_ root: URL, _ requestID: String) -> URL {
    path(root, "status", "\(requestID).json")
}

func updateStatus(_ root: URL, _ request: Request, state: String, detail: String, result: String? = nil) throws {
    let url = statusURL(root, request.requestID)
    let existing = try? readJSON(StatusRecord.self, from: url)
    let record = StatusRecord(
        schemaVersion: 1,
        requestID: request.requestID,
        bindingID: request.bindingID,
        operation: request.operation,
        state: state,
        createdAt: existing?.createdAt ?? request.createdAt,
        updatedAt: now(),
        detail: detail,
        result: result ?? existing?.result,
        workerPID: getpid()
    )
    try writeJSON(record, to: url)
}

func reject(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(code)
}

let args = CommandLine.arguments
guard args.count >= 3 else { usage() }
let root = URL(fileURLWithPath: args[1], isDirectory: true)
let mode = args[2]
try ensureDirs(root)

switch mode {
case "submit":
    guard args.count == 5 else { reject("REJECTED invalid typed submit arguments", code: 64) }
    let bindingID = args[3]
    guard bindingID == allowedBinding else { reject("REJECTED unknown binding") }
    guard let delaySeconds = Int(args[4]), (1...30).contains(delaySeconds) else {
        reject("REJECTED delay outside bounded range")
    }
    let requestID = UUID().uuidString.lowercased()
    let request = Request(schemaVersion: 1, bindingID: bindingID, operation: fixedOperation, requestID: requestID, delaySeconds: delaySeconds, createdAt: now())
    try writeJSON(request, to: path(root, "queue", "\(requestID).json"))
    try updateStatus(root, request, state: "queued", detail: "accepted for bridge-owned worker")
    print("ACCEPTED \(requestID)")

case "status":
    guard args.count == 4 else { reject("REJECTED invalid typed status arguments", code: 64) }
    let requestID = args[3]
    let url = statusURL(root, requestID)
    guard fm.fileExists(atPath: url.path) else { reject("REJECTED unknown request ID") }
    let record = try readJSON(StatusRecord.self, from: url)
    let resultText = record.result ?? ""
    print("STATUS \(record.requestID) \(record.state) \(record.detail) \(resultText)")

case "cancel":
    guard args.count == 4 else { reject("REJECTED invalid typed cancel arguments", code: 64) }
    let requestID = args[3]
    let url = statusURL(root, requestID)
    guard fm.fileExists(atPath: url.path) else { reject("REJECTED unknown request ID") }
    let cancelURL = path(root, "cancel", "\(requestID).cancel")
    if !fm.fileExists(atPath: cancelURL.path) {
        try "cancel\n".write(to: cancelURL, atomically: true, encoding: .utf8)
    }
    var record = try readJSON(StatusRecord.self, from: url)
    if record.state != "completed" && record.state != "cancelled" {
        record.state = "cancelled"
        record.updatedAt = now()
        record.detail = "cancellation requested"
        try writeJSON(record, to: url)
    }
    print("CANCELLED \(requestID)")

case "worker":
    guard args.count == 3 else { reject("REJECTED invalid worker arguments", code: 64) }
    while true {
        if fm.fileExists(atPath: path(root, "worker.stop").path) { exit(0) }
        let inflight = (try? fm.contentsOfDirectory(at: path(root, "inflight"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }) ?? []
        let queued = (try? fm.contentsOfDirectory(at: path(root, "queue"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }) ?? []
        let candidates = inflight + queued
        if let jobURL = candidates.first {
            let request = try readJSON(Request.self, from: jobURL)
            let inflightURL = path(root, "inflight", jobURL.lastPathComponent)
            if jobURL.deletingLastPathComponent().lastPathComponent == "queue" {
                try? fm.moveItem(at: jobURL, to: inflightURL)
            }
            try updateStatus(root, request, state: "running", detail: "worker running fixed delayed operation")
            var cancelled = false
            for _ in 0..<request.delaySeconds {
                if fm.fileExists(atPath: path(root, "worker.stop").path) { exit(0) }
                if fm.fileExists(atPath: path(root, "cancel", "\(request.requestID).cancel").path) {
                    cancelled = true
                    break
                }
                sleep(1)
            }
            if cancelled {
                try updateStatus(root, request, state: "cancelled", detail: "worker observed cancellation")
            } else {
                try updateStatus(root, request, state: "completed", detail: "fixed operation completed", result: "SPK06_FIXED_RESULT")
            }
            try? fm.removeItem(at: inflightURL)
        } else {
            usleep(100_000)
        }
    }

default:
    usage()
}
SWIFT
}

run_active() {
  log "SPK-06 active handoff prototype validation"
  rm -rf "$ACTIVE_DIR"
  mkdir -p "$ACTIVE_DIR"
  write_active_source

  local binary="${ACTIVE_DIR}/SPK06Prototype"
  local compile_log="${ACTIVE_DIR}/compile.log"
  if ! xcrun swiftc "${ACTIVE_DIR}/src/SPK06Prototype.swift" -o "$binary" >"$compile_log" 2>&1; then
    log "SPK06_ACTIVE_RESULT=FAIL"
    log "IMMEDIATE_HANDOFF_AVAILABLE=no"
    log "REQUEST_ID_AVAILABLE=no"
    log "STATUS_QUERY_AVAILABLE=no"
    log "COMPLETION_RESULT_AVAILABLE=no"
    log "CANCELLATION_AVAILABLE=no"
    log "INVALID_BINDING_REJECTED=no"
    log "WORKER_RESTART_RECOVERY=no"
    log "REAL_APP_INTENT_RUNTIME_PROVEN=no"
    log "SPK06_SELECTED_HANDOFF_MODEL=app-intent-validates-and-enqueues-to-bridge-xpc"
    log "RESIDUAL_WORKER_PROCESS=no"
    return 1
  fi

  local state_root="${ACTIVE_DIR}/state"
  mkdir -p "$state_root"
  rm -f "${state_root}/worker.stop"
  "$binary" "$state_root" worker > "${ACTIVE_DIR}/worker.log" 2>&1 &
  local worker_pid=$!

  cleanup_worker() {
    if kill -0 "$worker_pid" >/dev/null 2>&1; then
      print -r -- "stop" > "${state_root}/worker.stop"
      wait "$worker_pid" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup_worker EXIT INT TERM

  zmodload zsh/datetime
  local immediate_handoff=no request_id_available=no status_query=no completion_result=no cancellation=no invalid_binding=no restart_recovery=no
  local submit_start submit_end latency_ms submit_out req_a status_a
  submit_start=$EPOCHREALTIME
  submit_out="$("$binary" "$state_root" submit spk06.approved.binding 3)"
  submit_end=$EPOCHREALTIME
  latency_ms="$(awk "BEGIN { printf \"%d\", (${submit_end} - ${submit_start}) * 1000 }")"
  req_a="${submit_out#ACCEPTED }"
  [[ "$submit_out" == ACCEPTED\ * && -n "$req_a" ]] && request_id_available=yes
  status_a="$("$binary" "$state_root" status "$req_a")" && status_query=yes
  if [[ "$status_a" != *" completed "* && "$latency_ms" -lt 2500 ]]; then
    immediate_handoff=yes
  fi
  sleep 1
  "$binary" "$state_root" status "$req_a" > "${ACTIVE_DIR}/scenario-a-worker-continues.txt"

  local req_b status_b
  req_b="$("$binary" "$state_root" submit spk06.approved.binding 2)"
  req_b="${req_b#ACCEPTED }"
  "$binary" "$state_root" status "$req_b" > "${ACTIVE_DIR}/scenario-b-initial-status.txt"
  for _ in {1..50}; do
    status_b="$("$binary" "$state_root" status "$req_b")"
    [[ "$status_b" == *" completed "* ]] && break
    sleep 0.2
  done
  print -r -- "$status_b" > "${ACTIVE_DIR}/scenario-b-completion-status.txt"
  [[ "$status_b" == *" completed "*"SPK06_FIXED_RESULT"* ]] && completion_result=yes

  local req_c cancel_one cancel_two status_c
  req_c="$("$binary" "$state_root" submit spk06.approved.binding 8)"
  req_c="${req_c#ACCEPTED }"
  sleep 0.5
  cancel_one="$("$binary" "$state_root" cancel "$req_c")"
  cancel_two="$("$binary" "$state_root" cancel "$req_c")"
  sleep 0.5
  status_c="$("$binary" "$state_root" status "$req_c")"
  {
    print -r -- "$cancel_one"
    print -r -- "$cancel_two"
    print -r -- "$status_c"
  } > "${ACTIVE_DIR}/scenario-c-cancellation.txt"
  [[ "$cancel_one" == CANCELLED\ * && "$cancel_two" == CANCELLED\ * && "$status_c" == *" cancelled "* ]] && cancellation=yes

  if ! "$binary" "$state_root" submit unknown.binding 1 > "${ACTIVE_DIR}/scenario-d-invalid-binding.out" 2> "${ACTIVE_DIR}/scenario-d-invalid-binding.err"; then
    if ! "$binary" "$state_root" status unknown-request-id > "${ACTIVE_DIR}/scenario-d-unknown-request.out" 2> "${ACTIVE_DIR}/scenario-d-unknown-request.err"; then
      if ! "$binary" "$state_root" submit spk06.approved.binding 1 arbitrary-command > "${ACTIVE_DIR}/scenario-d-extra-argument.out" 2> "${ACTIVE_DIR}/scenario-d-extra-argument.err"; then
        invalid_binding=yes
      fi
    fi
  fi

  local req_e status_e
  req_e="$("$binary" "$state_root" submit spk06.approved.binding 4)"
  req_e="${req_e#ACCEPTED }"
  sleep 0.5
  kill "$worker_pid" >/dev/null 2>&1 || true
  wait "$worker_pid" >/dev/null 2>&1 || true
  "$binary" "$state_root" status "$req_e" > "${ACTIVE_DIR}/scenario-e-after-termination.txt" || true
  rm -f "${state_root}/worker.stop"
  "$binary" "$state_root" worker >> "${ACTIVE_DIR}/worker-restarted.log" 2>&1 &
  worker_pid=$!
  for _ in {1..70}; do
    status_e="$("$binary" "$state_root" status "$req_e")"
    [[ "$status_e" == *" completed "* ]] && break
    sleep 0.2
  done
  print -r -- "$status_e" > "${ACTIVE_DIR}/scenario-e-after-restart.txt"
  [[ "$status_e" == *" completed "*"SPK06_FIXED_RESULT"* ]] && restart_recovery=yes

  cleanup_worker
  trap - EXIT INT TERM

  local residual=no
  if pgrep -f "${binary} ${state_root} worker" >/dev/null 2>&1; then
    residual=yes
  fi

  {
    print -r -- "scenario_a_request=${req_a}"
    print -r -- "scenario_a_acceptance_latency_ms=${latency_ms}"
    print -r -- "scenario_a_initial_status=${status_a}"
    print -r -- "scenario_b_request=${req_b}"
    print -r -- "scenario_b_final_status=${status_b}"
    print -r -- "scenario_c_request=${req_c}"
    print -r -- "scenario_c_final_status=${status_c}"
    print -r -- "scenario_e_request=${req_e}"
    print -r -- "scenario_e_final_status=${status_e}"
  } > "${ACTIVE_DIR}/active-summary.txt"

  local active_result=FAIL
  if [[ "$immediate_handoff" == yes && "$request_id_available" == yes && "$status_query" == yes && "$completion_result" == yes && "$cancellation" == yes && "$invalid_binding" == yes && "$restart_recovery" == yes && "$residual" == no ]]; then
    active_result=PASS
  elif [[ "$request_id_available" == yes || "$status_query" == yes || "$completion_result" == yes ]]; then
    active_result=PARTIAL
  fi

  log "SPK06_ACTIVE_RESULT=${active_result}"
  log "IMMEDIATE_HANDOFF_AVAILABLE=${immediate_handoff}"
  log "REQUEST_ID_AVAILABLE=${request_id_available}"
  log "STATUS_QUERY_AVAILABLE=${status_query}"
  log "COMPLETION_RESULT_AVAILABLE=${completion_result}"
  log "CANCELLATION_AVAILABLE=${cancellation}"
  log "INVALID_BINDING_REJECTED=${invalid_binding}"
  log "WORKER_RESTART_RECOVERY=${restart_recovery}"
  log "REAL_APP_INTENT_RUNTIME_PROVEN=no"
  log "SPK06_SELECTED_HANDOFF_MODEL=app-intent-validates-and-enqueues-to-bridge-xpc"
  log "RESIDUAL_WORKER_PROCESS=${residual}"
}

if [[ "$ACTIVE_TEST" == yes ]]; then
  run_active
else
  run_read_only
fi
