#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
ARTIFACT_BASE="${REPO_ROOT}/artifacts/m5-001"
RUN_DIR="${ARTIFACT_BASE}/run-$(/bin/date -u +%Y%m%dT%H%M%SZ)-$$"
SOURCE_DIR="${RUN_DIR}/sources"
BIN_DIR="${RUN_DIR}/bin"
LOG_DIR="${RUN_DIR}/logs"

mkdir -p "${SOURCE_DIR}" "${BIN_DIR}" "${LOG_DIR}"

ROOT_REGISTRATION_PASSED=no
BOOKMARK_RESOLUTION_PASSED=no
CREATE_EVENT_OBSERVED=no
MODIFY_EVENT_OBSERVED=no
RENAME_EVENT_OBSERVED=no
DELETE_EVENT_OBSERVED=no
RECURSIVE_EVENT_OBSERVED=no
CURSOR_PERSISTED=no
RESTART_REPLAY_VALIDATED=no
OUTSIDE_ROOT_EVENT_OBSERVED=no
RESIDUAL_MONITOR_PROCESS=no
M5_001_RESULT=FAIL

HELPER_SOURCE="${SOURCE_DIR}/M5001Integration.swift"
HELPER_BIN="${BIN_DIR}/m5-001-integration"
HELPER_LOG="${LOG_DIR}/helper.log"

cat >"${HELPER_SOURCE}" <<'SWIFT'
import Foundation
import HermesRuntimeFoundation

final class Collector: @unchecked Sendable {
  private let queue = DispatchQueue(label: "m5-001.collector")
  private var batches: [HermesFileEventBatch] = []

  func append(_ batch: HermesFileEventBatch) {
    queue.sync {
      batches.append(batch)
    }
  }

  func events() -> [HermesFileEvent] {
    queue.sync {
      batches.flatMap(\.events)
    }
  }

  func newestEventID() -> UInt64 {
    queue.sync {
      batches.map(\.newestEventID).max() ?? 0
    }
  }

  func hasReplayedOrHistory() -> Bool {
    queue.sync {
      batches.contains(where: { $0.replayed || $0.events.contains(where: { $0.kind == .historyDone }) })
    }
  }
}

func waitUntil(timeout: TimeInterval = 8, _ predicate: @escaping () async -> Bool) async throws -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if await predicate() {
      return true
    }
    try await Task.sleep(nanoseconds: 100_000_000)
  }
  return false
}

func printKV(_ key: String, _ value: String) {
  print("\(key)=\(value)")
}

@main
struct Main {
  static func main() async throws {
    let args = CommandLine.arguments
    guard args.count == 2 else {
      printKV("HELPER_ERROR", "usage")
      Foundation.exit(64)
    }

    let runRoot = URL(fileURLWithPath: args[1], isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let policyRoot = runRoot.appendingPathComponent("policy", isDirectory: true)
    let watchedRoot = policyRoot.appendingPathComponent("authorized-root", isDirectory: true)
    let registryRoot = runRoot.appendingPathComponent("registry", isDirectory: true)
    try FileManager.default.createDirectory(at: watchedRoot, withIntermediateDirectories: true)

    let registry = try FileBackedHermesAuthorizedRootRegistry(
      registryRoot: registryRoot,
      policy: HermesAuthorizedRootPolicy(permittedRootParents: [policyRoot])
    )
    let bookmark = try watchedRoot.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    let record = try await registry.registerBookmark(
      displayName: "M5 Integration Root",
      bookmarkData: bookmark,
      createdAt: Date()
    )
    printKV("ROOT_REGISTRATION_PASSED", "yes")

    let resolution = try await registry.resolveRoot(record.rootID)
    if resolution.resolvedURL?.path == watchedRoot.path {
      printKV("BOOKMARK_RESOLUTION_PASSED", "yes")
    } else {
      printKV("BOOKMARK_RESOLUTION_PASSED", "no")
    }

    let collector = Collector()
    let monitor = HermesFSEventsMonitor(
      registry: registry,
      configuration: try HermesFSEventsMonitorConfiguration(latency: 0.10)
    ) { batch in
      collector.append(batch)
    }

    try await monitor.start(records: [record])
    try await Task.sleep(nanoseconds: 750_000_000)

    let file = watchedRoot.appendingPathComponent("file.txt")
    try "create".write(to: file, atomically: false, encoding: .utf8)
    let createObserved = try await waitUntil {
      collector.events().contains { $0.relativePath.rawValue == "file.txt" }
    }
    printKV("CREATE_EVENT_OBSERVED", createObserved ? "yes" : "no")

    let countBeforeModify = collector.events().count
    try "modify".write(to: file, atomically: false, encoding: .utf8)
    let modifyObserved = try await waitUntil {
      collector.events().count > countBeforeModify
        && collector.events().contains { $0.relativePath.rawValue == "file.txt" }
    }
    printKV("MODIFY_EVENT_OBSERVED", modifyObserved ? "yes" : "no")

    let renamed = watchedRoot.appendingPathComponent("renamed.txt")
    try FileManager.default.moveItem(at: file, to: renamed)
    let renameObserved = try await waitUntil {
      collector.events().contains { $0.kind == .renamed }
    }
    printKV("RENAME_EVENT_OBSERVED", renameObserved ? "yes" : "no")

    let nested = watchedRoot.appendingPathComponent("nested/child/deep.txt")
    try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "nested".write(to: nested, atomically: false, encoding: .utf8)
    let recursiveObserved = try await waitUntil {
      collector.events().contains { $0.relativePath.rawValue.hasSuffix("nested/child/deep.txt") }
    }
    printKV("RECURSIVE_EVENT_OBSERVED", recursiveObserved ? "yes" : "no")

    try FileManager.default.removeItem(at: renamed)
    let deleteObserved = try await waitUntil {
      collector.events().contains { $0.kind == .removed }
    }
    printKV("DELETE_EVENT_OBSERVED", deleteObserved ? "yes" : "no")

    let cursorObserved = try await waitUntil {
      ((try? await registry.readRoot(record.rootID).lastObservedFSEventID) ?? 0) > 0
    }
    printKV("CURSOR_PERSISTED", cursorObserved ? "yes" : "no")

    try await monitor.stop()

    let afterStop = watchedRoot.appendingPathComponent("while-stopped.txt")
    try "stopped".write(to: afterStop, atomically: false, encoding: .utf8)
    let persisted = try await registry.readRoot(record.rootID)
    let replayCollector = Collector()
    let replayMonitor = HermesFSEventsMonitor(
      registry: registry,
      configuration: try HermesFSEventsMonitorConfiguration(latency: 0.10)
    ) { batch in
      replayCollector.append(batch)
    }
    try await replayMonitor.start(records: [persisted])
    let replayValidated = try await waitUntil(timeout: 4) {
      replayCollector.hasReplayedOrHistory()
        || replayCollector.events().contains { $0.relativePath.rawValue == "while-stopped.txt" }
    }
    printKV("RESTART_REPLAY_VALIDATED", replayValidated ? "yes" : "no")
    try await replayMonitor.stop()

    let allPaths = collector.events().map(\.relativePath.rawValue)
      + replayCollector.events().map(\.relativePath.rawValue)
    let outside = allPaths.contains { $0.hasPrefix("/") || $0.contains("..") }
    printKV("OUTSIDE_ROOT_EVENT_OBSERVED", outside ? "yes" : "no")

    let evidence = [
      "rootID": record.rootID.rawValue,
      "eventCount": "\(collector.events().count + replayCollector.events().count)",
      "newestEventID": "\(max(collector.newestEventID(), replayCollector.newestEventID()))",
      "securityScopedAccessStarted": resolution.securityScopedAccessStarted ? "yes" : "no",
      "securityScopedValidationStatus": "not_proven_by_integration"
    ]
    let data = try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: runRoot.appendingPathComponent("evidence.json"))
  }
}
SWIFT

{
  print "run_dir=${RUN_DIR}"
  print "step=swift_build"
} >"${LOG_DIR}/integration.log"

swift build >>"${LOG_DIR}/integration.log" 2>&1
BIN_PATH="$(swift build --show-bin-path)"

swiftc \
  -parse-as-library \
  -I "${BIN_PATH}" \
  -L "${BIN_PATH}" \
  -lHermesRuntimeFoundation \
  "${HELPER_SOURCE}" \
  -o "${HELPER_BIN}" \
  >>"${LOG_DIR}/integration.log" 2>&1

if "${HELPER_BIN}" "${RUN_DIR}" >"${HELPER_LOG}" 2>"${LOG_DIR}/helper.err"; then
  :
else
  print -u2 "integration helper failed; see ${LOG_DIR}/helper.err"
fi

value_for() {
  local key="$1"
  local value=""
  value="$(grep -E "^${key}=" "${HELPER_LOG}" | tail -n 1 | cut -d= -f2- || true)"
  print "${value:-no}"
}

ROOT_REGISTRATION_PASSED="$(value_for ROOT_REGISTRATION_PASSED)"
BOOKMARK_RESOLUTION_PASSED="$(value_for BOOKMARK_RESOLUTION_PASSED)"
CREATE_EVENT_OBSERVED="$(value_for CREATE_EVENT_OBSERVED)"
MODIFY_EVENT_OBSERVED="$(value_for MODIFY_EVENT_OBSERVED)"
RENAME_EVENT_OBSERVED="$(value_for RENAME_EVENT_OBSERVED)"
DELETE_EVENT_OBSERVED="$(value_for DELETE_EVENT_OBSERVED)"
RECURSIVE_EVENT_OBSERVED="$(value_for RECURSIVE_EVENT_OBSERVED)"
CURSOR_PERSISTED="$(value_for CURSOR_PERSISTED)"
RESTART_REPLAY_VALIDATED="$(value_for RESTART_REPLAY_VALIDATED)"
OUTSIDE_ROOT_EVENT_OBSERVED="$(value_for OUTSIDE_ROOT_EVENT_OBSERVED)"

if pgrep -f "${HELPER_BIN}" >/dev/null 2>&1; then
  RESIDUAL_MONITOR_PROCESS=yes
fi

required=(
  "${ROOT_REGISTRATION_PASSED}"
  "${BOOKMARK_RESOLUTION_PASSED}"
  "${CREATE_EVENT_OBSERVED}"
  "${MODIFY_EVENT_OBSERVED}"
  "${RENAME_EVENT_OBSERVED}"
  "${DELETE_EVENT_OBSERVED}"
  "${RECURSIVE_EVENT_OBSERVED}"
  "${CURSOR_PERSISTED}"
)

M5_001_RESULT=PASS
for value in "${required[@]}"; do
  if [[ "${value}" != "yes" ]]; then
    M5_001_RESULT=FAIL
  fi
done
if [[ "${OUTSIDE_ROOT_EVENT_OBSERVED}" != "no" || "${RESIDUAL_MONITOR_PROCESS}" != "no" ]]; then
  M5_001_RESULT=FAIL
fi
if [[ "${RESTART_REPLAY_VALIDATED}" != "yes" && "${M5_001_RESULT}" == "PASS" ]]; then
  M5_001_RESULT=PARTIAL
fi

print "ROOT_REGISTRATION_PASSED=${ROOT_REGISTRATION_PASSED}"
print "BOOKMARK_RESOLUTION_PASSED=${BOOKMARK_RESOLUTION_PASSED}"
print "CREATE_EVENT_OBSERVED=${CREATE_EVENT_OBSERVED}"
print "MODIFY_EVENT_OBSERVED=${MODIFY_EVENT_OBSERVED}"
print "RENAME_EVENT_OBSERVED=${RENAME_EVENT_OBSERVED}"
print "DELETE_EVENT_OBSERVED=${DELETE_EVENT_OBSERVED}"
print "RECURSIVE_EVENT_OBSERVED=${RECURSIVE_EVENT_OBSERVED}"
print "CURSOR_PERSISTED=${CURSOR_PERSISTED}"
print "RESTART_REPLAY_VALIDATED=${RESTART_REPLAY_VALIDATED}"
print "OUTSIDE_ROOT_EVENT_OBSERVED=${OUTSIDE_ROOT_EVENT_OBSERVED}"
print "RESIDUAL_MONITOR_PROCESS=${RESIDUAL_MONITOR_PROCESS}"
print "M5_001_RESULT=${M5_001_RESULT}"

[[ "${M5_001_RESULT}" != "FAIL" ]]
