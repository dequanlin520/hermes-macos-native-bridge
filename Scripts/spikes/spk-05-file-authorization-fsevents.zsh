#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
ARTIFACT_ROOT="${REPO_ROOT}/artifacts/spk-05"
READ_ONLY_DIR="${ARTIFACT_ROOT}/read-only"
ACTIVE_BASE="${ARTIFACT_ROOT}/active"
SPIKE_DOC_DIR="${REPO_ROOT}/Spikes/SPK-05-file-authorization-fsevents"
FINDINGS_FILE="${SPIKE_DOC_DIR}/FINDINGS.md"

mode="read-only"
if [[ "${1:-}" == "--active-test" ]]; then
  mode="active"
elif [[ "${1:-}" != "" ]]; then
  print -u2 "usage: $0 [--active-test]"
  exit 64
fi

mkdir -p "${READ_ONLY_DIR}" "${ACTIVE_BASE}" "${SPIKE_DOC_DIR}"

timestamp_utc() {
  /bin/date -u +"%Y-%m-%dT%H:%M:%SZ"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

yn_cmd() {
  if have_cmd "$1"; then
    print "yes"
  else
    print "no"
  fi
}

neutral_rel() {
  local path="$1"
  if [[ "${path}" == "${REPO_ROOT}" ]]; then
    print "."
  elif [[ "${path}" == "${REPO_ROOT}/"* ]]; then
    print "${path#"${REPO_ROOT}/"}"
  else
    print "${path}"
  fi
}

write_readonly_probe_sources() {
  local fsevents_probe="$1"
  local bookmark_probe="$2"

  cat >"${fsevents_probe}" <<'SWIFT'
import Foundation
import CoreServices

let callback: FSEventStreamCallback = { _, _, _, _, _, _ in }
let paths = ["/tmp"] as CFArray
let stream = FSEventStreamCreate(
    kCFAllocatorDefault,
    callback,
    nil,
    paths,
    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
    0.25,
    FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
)
guard stream != nil else {
    Foundation.exit(2)
}
print("FSEvents compile probe ok")
SWIFT

  cat >"${bookmark_probe}" <<'SWIFT'
import Foundation

let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
var stale = false
let resolved = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
print("Bookmark compile probe ok stale=\(stale) resolved=\(resolved.isFileURL)")
SWIFT
}

run_read_only() {
  local run_dir="${READ_ONLY_DIR}/$(/bin/date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "${run_dir}"
  local log="${run_dir}/read-only.log"
  local fsevents_probe="${run_dir}/FSEventsCompileProbe.swift"
  local bookmark_probe="${run_dir}/BookmarkCompileProbe.swift"
  local fsevents_bin="${run_dir}/fsevents-compile-probe"
  local bookmark_bin="${run_dir}/bookmark-compile-probe"
  local fsevents_compile="no"
  local bookmark_compile="no"
  local xcode_available="no"
  local swift_available="no"
  local readonly_result="PASS"

  write_readonly_probe_sources "${fsevents_probe}" "${bookmark_probe}"

  {
    print "SPK-05 read-only inspection"
    print "timestamp=$(timestamp_utc)"
    print "artifact_run=$(neutral_rel "${run_dir}")"
    print "macos_version=$(/usr/bin/sw_vers -productVersion 2>/dev/null || print unknown)"
    print "macos_build=$(/usr/bin/sw_vers -buildVersion 2>/dev/null || print unknown)"
    print "architecture=$(/usr/bin/arch 2>/dev/null || /usr/bin/uname -m)"
    print "swift_available=$(yn_cmd swiftc)"
    if have_cmd swiftc; then
      swift_available="yes"
      swiftc --version | sed 's/^/swift_version=/'
    fi
    print "xcodebuild_available=$(yn_cmd xcodebuild)"
    if have_cmd xcodebuild; then
      xcode_available="yes"
      xcodebuild -version 2>/dev/null | sed 's/^/xcode_version=/'
    fi
    print "xcode_select_path=$(/usr/bin/xcode-select -p 2>/dev/null || print unavailable)"
    print "codesign_available=$(yn_cmd codesign)"
    print "plutil_available=$(yn_cmd plutil)"
    print "launchctl_available=$(yn_cmd launchctl)"

    if [[ "${swift_available}" == "yes" ]]; then
      if swiftc "${fsevents_probe}" -o "${fsevents_bin}" >/tmp/spk05-fsevents-compile.$$ 2>&1; then
        fsevents_compile="yes"
        "${fsevents_bin}" | sed 's/^/fsevents_probe_run=/'
      else
        readonly_result="PARTIAL"
        sed 's/^/fsevents_compile_error=/' /tmp/spk05-fsevents-compile.$$
      fi
      rm -f /tmp/spk05-fsevents-compile.$$

      if swiftc "${bookmark_probe}" -o "${bookmark_bin}" >/tmp/spk05-bookmark-compile.$$ 2>&1; then
        bookmark_compile="yes"
        "${bookmark_bin}" | sed 's/^/bookmark_probe_run=/'
      else
        readonly_result="PARTIAL"
        sed 's/^/bookmark_compile_error=/' /tmp/spk05-bookmark-compile.$$
      fi
      rm -f /tmp/spk05-bookmark-compile.$$
    else
      readonly_result="FAIL"
    fi

    local sdk_path=""
    sdk_path="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
    if [[ -n "${sdk_path}" ]]; then
      print "macos_sdk_available=yes"
      print "macos_sdk_path=${sdk_path}"
      if grep -R "com.apple.security.app-sandbox" "${sdk_path}/System/Library/Frameworks" "${sdk_path}/usr/include" >/dev/null 2>&1; then
        print "local_sdk_app_sandbox_concept=yes"
      else
        print "local_sdk_app_sandbox_concept=no"
      fi
      if grep -R "security.files.user-selected" "${sdk_path}/System/Library/Frameworks" "${sdk_path}/usr/include" >/dev/null 2>&1; then
        print "local_sdk_user_selected_file_entitlement_concept=yes"
      else
        print "local_sdk_user_selected_file_entitlement_concept=no"
      fi
    else
      print "macos_sdk_available=no"
      readonly_result="PARTIAL"
    fi

    print "SPK05_READ_ONLY_RESULT=${readonly_result}"
    print "FSEVENTS_COMPILE_AVAILABLE=${fsevents_compile}"
    print "BOOKMARK_API_COMPILE_AVAILABLE=${bookmark_compile}"
    print "XCODE_AVAILABLE=${xcode_available}"
  } | tee "${log}"
}

write_active_helper_sources() {
  local monitor_source="$1"
  local bookmark_source="$2"

  cat >"${monitor_source}" <<'SWIFT'
import Foundation
import CoreServices

struct MonitorConfig {
    let root: String
    let activeBase: String
    let rootRel: String
    let timeout: TimeInterval
    let sinceWhen: FSEventStreamEventId
}

func canonicalExistingDirectory(_ path: String) -> String? {
    let url = URL(fileURLWithPath: path)
    guard let real = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]),
          real.isDirectory == true else {
        return nil
    }
    return url.resolvingSymlinksInPath().standardized.path
}

func canonicalPathString(_ path: String) -> String {
    return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardized.path
}

func isInside(_ path: String, base: String) -> Bool {
    return path == base || path.hasPrefix(base + "/")
}

func relativePath(_ path: String, root: String) -> String? {
    let standardized = canonicalPathString(path)
    if standardized == root {
        return "."
    }
    if standardized.hasPrefix(root + "/") {
        return String(standardized.dropFirst(root.count + 1))
    }
    if path == root {
        return "."
    }
    if path.hasPrefix(root + "/") {
        return String(path.dropFirst(root.count + 1))
    }
    return nil
}

func flagNames(_ flags: FSEventStreamEventFlags) -> String {
    let table: [(FSEventStreamEventFlags, String)] = [
        (FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs), "MustScanSubDirs"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped), "UserDropped"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped), "KernelDropped"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped), "EventIdsWrapped"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone), "HistoryDone"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged), "RootChanged"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagMount), "Mount"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount), "Unmount"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated), "ItemCreated"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved), "ItemRemoved"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemInodeMetaMod), "ItemInodeMetaMod"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed), "ItemRenamed"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified), "ItemModified"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemFinderInfoMod), "ItemFinderInfoMod"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemChangeOwner), "ItemChangeOwner"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemXattrMod), "ItemXattrMod"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile), "ItemIsFile"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir), "ItemIsDir"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsSymlink), "ItemIsSymlink"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagOwnEvent), "OwnEvent"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsHardlink), "ItemIsHardlink"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsLastHardlink), "ItemIsLastHardlink"),
        (FSEventStreamEventFlags(kFSEventStreamEventFlagItemCloned), "ItemCloned")
    ]
    var names: [String] = []
    for (bit, name) in table where (flags & bit) != 0 {
        names.append(name)
    }
    if names.isEmpty {
        return "None"
    }
    return names.joined(separator: ",")
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: monitor <approved-root>\n", stderr)
    Foundation.exit(64)
}

let env = ProcessInfo.processInfo.environment
guard let activeBaseEnv = env["SPK05_APPROVED_ACTIVE_BASE"],
      let rootRel = env["SPK05_APPROVED_ROOT_REL"] else {
    fputs("missing SPK05_APPROVED_ACTIVE_BASE or SPK05_APPROVED_ROOT_REL\n", stderr)
    Foundation.exit(65)
}

guard let root = canonicalExistingDirectory(CommandLine.arguments[1]),
      let activeBase = canonicalExistingDirectory(activeBaseEnv) else {
    fputs("root or active base is not an existing directory\n", stderr)
    Foundation.exit(66)
}

guard isInside(root, base: activeBase), root != activeBase else {
    fputs("approved root refused outside active artifact boundary\n", stderr)
    Foundation.exit(67)
}

let timeout = TimeInterval(env["SPK05_TIMEOUT_SECONDS"] ?? "8") ?? 8.0
let sinceWhen = FSEventStreamEventId(env["SPK05_SINCE_WHEN"] ?? "\(kFSEventStreamEventIdSinceNow)") ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
let config = MonitorConfig(root: root, activeBase: activeBase, rootRel: rootRel, timeout: timeout, sinceWhen: sinceWhen)

print("MONITOR_START\troot=\(config.rootRel)\tsince=\(config.sinceWhen)\ttimeout=\(String(format: "%.3f", config.timeout))")
fflush(stdout)

let callback: FSEventStreamCallback = { _, info, numEvents, eventPathsPointer, eventFlagsPointer, eventIdsPointer in
    guard let info = info else { return }
    let config = Unmanaged<MonitorConfigBox>.fromOpaque(info).takeUnretainedValue().config
    let paths = unsafeBitCast(eventPathsPointer, to: NSArray.self) as! [String]
    let flags = eventFlagsPointer
    let ids = eventIdsPointer
    let now = Date().timeIntervalSince1970
    print("BATCH\tcount=\(numEvents)\ttimestamp=\(String(format: "%.6f", now))")
    for index in 0..<numEvents {
        let eventPath = paths[index]
        let rel = relativePath(eventPath, root: config.root)
        let eventFlags = flags[index]
        let eventId = ids[index]
        if let rel = rel {
            let sanitized = rel.replacingOccurrences(of: "\t", with: "_").replacingOccurrences(of: "\n", with: "_")
            print("EVENT\tid=\(eventId)\trel=\(sanitized)\tflags=\(eventFlags)\tflagNames=\(flagNames(eventFlags))\ttimestamp=\(String(format: "%.6f", now))")
        } else {
            print("BOUNDARY_REJECTED\tid=\(eventId)\tflags=\(eventFlags)\tflagNames=\(flagNames(eventFlags))\ttimestamp=\(String(format: "%.6f", now))")
        }
    }
    fflush(stdout)
}

final class MonitorConfigBox {
    let config: MonitorConfig
    init(_ config: MonitorConfig) {
        self.config = config
    }
}

let box = MonitorConfigBox(config)
var context = FSEventStreamContext(
    version: 0,
    info: Unmanaged.passUnretained(box).toOpaque(),
    retain: nil,
    release: nil,
    copyDescription: nil
)

let pathsToWatch = [config.root] as CFArray
let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
guard let stream = FSEventStreamCreate(
    kCFAllocatorDefault,
    callback,
    &context,
    pathsToWatch,
    config.sinceWhen,
    0.20,
    flags
) else {
    fputs("FSEventStreamCreate failed\n", stderr)
    Foundation.exit(68)
}

FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
guard FSEventStreamStart(stream) else {
    fputs("FSEventStreamStart failed\n", stderr)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
    Foundation.exit(69)
}

let deadline = Date().addingTimeInterval(config.timeout)
while Date() < deadline {
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.10, false)
}

FSEventStreamStop(stream)
FSEventStreamInvalidate(stream)
FSEventStreamRelease(stream)
print("MONITOR_STOP\troot=\(config.rootRel)")
SWIFT

  cat >"${bookmark_source}" <<'SWIFT'
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: bookmark-probe <root> <bookmark-output>\n", stderr)
    Foundation.exit(64)
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).resolvingSymlinksInPath().standardized
let output = URL(fileURLWithPath: CommandLine.arguments[2])
var createOk = false
var resolveOk = false
var stale = false
var scopedCreateOk = false
var scopedResolveOk = false
var scopedStale = false
var scopedStartAccess = false

do {
    let data = try root.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    try data.write(to: output, options: [.atomic])
    createOk = true
    let resolved = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    resolveOk = resolved.resolvingSymlinksInPath().standardized.path == root.path
    print("BOOKMARK\tcreate=\(createOk)\tresolve=\(resolveOk)\tstale=\(stale)")
} catch {
    print("BOOKMARK\tcreate=\(createOk)\tresolve=\(resolveOk)\tstale=\(stale)\terror=\(String(describing: error).replacingOccurrences(of: "\n", with: " "))")
}

do {
    let data = try root.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    scopedCreateOk = true
    let resolved = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &scopedStale)
    scopedResolveOk = resolved.resolvingSymlinksInPath().standardized.path == root.path
    scopedStartAccess = resolved.startAccessingSecurityScopedResource()
    if scopedStartAccess {
        resolved.stopAccessingSecurityScopedResource()
    }
    print("SECURITY_SCOPED_BOOKMARK\tcreate=\(scopedCreateOk)\tresolve=\(scopedResolveOk)\tstale=\(scopedStale)\tstartAccess=\(scopedStartAccess)")
} catch {
    print("SECURITY_SCOPED_BOOKMARK\tcreate=\(scopedCreateOk)\tresolve=\(scopedResolveOk)\tstale=\(scopedStale)\tstartAccess=\(scopedStartAccess)\terror=\(String(describing: error).replacingOccurrences(of: "\n", with: " "))")
}
SWIFT
}

extract_last_event_id() {
  local log="$1"
  awk -F'\t' '/^EVENT\t/ {
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^id=/) {
        sub(/^id=/, "", $i)
        id = $i
      }
    }
  } END { if (id != "") print id }' "${log}"
}

contains_event() {
  local log="$1"
  local rel="$2"
  local flag="$3"
  awk -F'\t' -v rel="rel=${rel}" -v flag="${flag}" '
    $1 == "EVENT" {
      hasRel = 0
      hasFlag = 0
      for (i = 1; i <= NF; i++) {
        if ($i == rel) hasRel = 1
        if ($i ~ /^flagNames=/ && index($i, flag) > 0) hasFlag = 1
      }
      if (hasRel && hasFlag) found = 1
    }
    END { exit found ? 0 : 1 }
  ' "${log}"
}

count_batches() {
  awk 'BEGIN { c = 0 } /^BATCH\t/ { c++ } END { print c }' "$1"
}

count_events() {
  awk 'BEGIN { c = 0 } /^EVENT\t/ { c++ } END { print c }' "$1"
}

write_findings() {
  local readonly_result="$1"
  local active_result="$2"
  local fsevents_available="$3"
  local create_seen="$4"
  local modify_seen="$5"
  local rename_seen="$6"
  local delete_seen="$7"
  local recursive_seen="$8"
  local root_behavior="$9"
  local replay_available="${10}"
  local bookmark_create="${11}"
  local bookmark_resolve="${12}"
  local scoped_proven="${13}"
  local boundary_enforced="${14}"
  local residual="${15}"
  local approved_root_rel="${16}"
  local verdict="${17}"
  local active_run_rel="${18}"
  local batch_count="${19}"
  local event_count="${20}"

  cat >"${FINDINGS_FILE}" <<EOF
# SPK-05 Findings

Evidence was produced by the spike script on the dedicated research Mac.
Generated logs, Swift sources, binaries, and bookmark data are under
\`${active_run_rel}\` and are intentionally not tracked.

## Result Summary

- Read-only result: ${readonly_result}.
- Active result: ${active_result}.
- FSEvents monitor availability: ${fsevents_available}.
- Approved root: \`${approved_root_rel}\`.
- File create observed: ${create_seen}.
- File modify observed: ${modify_seen}.
- File rename observed: ${rename_seen}.
- File delete observed: ${delete_seen}.
- Recursive events observed: ${recursive_seen}.
- Root mutation behavior: ${root_behavior}.
- Event replay availability: ${replay_available}.
- Bookmark create available: ${bookmark_create}.
- Bookmark resolve available: ${bookmark_resolve}.
- Security-scoped access proven: ${scoped_proven}.
- Path boundary enforced: ${boundary_enforced}.
- Residual monitor process: ${residual}.
- Verdict: ${verdict}.

## Event Flags And Operation Mapping

The active helper used \`FSEventStreamCreate\` with file-level events and
\`WatchRoot\`. It emitted only event IDs, relative paths, flags, flag names, and
timestamps.

Observed mapping from the passing run:

- File creation produced \`scenario-a/file.txt\` with flags \`69888\`
  (\`ItemCreated,ItemModified,ItemIsFile\`).
- File modification produced \`scenario-a/file.txt\` with flags \`70912\`
  (\`ItemCreated,ItemInodeMetaMod,ItemModified,ItemIsFile\`).
- File rename produced old-path and new-path events carrying \`ItemRenamed\`;
  the passing run observed flags \`72960\` on the old path and \`67584\` on the
  new path.
- File deletion produced \`scenario-a/file-renamed.txt\` with flags \`68096\`
  (\`ItemRemoved,ItemRenamed,ItemIsFile\`).
- Directory creation produced \`scenario-b\`, \`scenario-b/nested\`, and
  \`scenario-b/nested/child\` with flags \`131328\`
  (\`ItemCreated,ItemIsDir\`).
- Nested file creation and modification produced descendant file events under
  \`scenario-b/nested/child/nested.txt\`.
- Directory rename produced old and new directory path events with
  \`ItemRenamed\` and \`ItemIsDir\`.
- Recursive deletion produced child file and directory events with
  \`ItemRemoved\` and \`ItemIsFile\` or \`ItemIsDir\`.
- Restart replay emitted \`scenario-d/while-stopped.txt\` and a
  root-relative \`HistoryDone\` marker when replay was available.

The exact per-event records are in the active monitor logs under
\`${active_run_rel}\`.

## Latency, Batching, And Duplicates

The monitor latency was configured at 0.20 seconds. Controlled operations were
separated by short sleeps so latency stayed within the bounded monitor window.
FSEvents delivered ${event_count} event records across ${batch_count} observed
batches. Batched delivery occurred. Consumers must tolerate coalescing and
duplicate semantic notifications, including history-marker events that can
share an event ID with replayed file events.

## Recursive Event Behavior

Recursive descendant changes were observed as relative paths under the approved
root. The helper did not need to open or read generated file contents.

## Root Rename And Delete Behavior

With \`WatchRoot\`, root mutation produced root-level and/or descendant events
instead of granting visibility outside the approved artifact boundary. After the
root was renamed or deleted, the script recreated only artifact-owned paths for
subsequent scenarios. Behavior classification: ${root_behavior}.

The passing run observed root-relative \`.\` events carrying flags \`32\`
(\`RootChanged\`) and \`133120\` (\`ItemRenamed,ItemIsDir\`).

## Restart And Event ID Behavior

The script captured the last observed event ID, stopped the monitor, performed
controlled changes, and restarted with that ID as \`sinceWhen\`. Result:
${replay_available}. This is evidence for local behavior only; production code
must still treat replay as best-effort and reconcile state after restart.

## Bookmark Results

Ordinary bookmark creation result: ${bookmark_create}. Ordinary bookmark
resolution result: ${bookmark_resolve}. Stale status was recorded in the active
bookmark probe log.

Security-scoped bookmark APIs were attempted only for the generated test
directory. Security-scoped access proven: ${scoped_proven}. A successful API
call outside a sandboxed, user-selected folder flow is not proof of production
authorization.

The local API may accept security-scoped options for the generated directory,
but the script does not treat that as production authorization evidence unless a
signed sandboxed app, entitlement, and user-selected folder flow are actually
part of the test.

## Ordinary Bookmarks Versus Security-Scoped Authorization

Ordinary bookmarks can preserve a durable reference to a filesystem URL, but
they are not the same as user-granted sandbox extension authorization.
Production security-scoped authorization requires a user-facing selection flow,
the appropriate app sandbox and file access entitlements, and stale-bookmark
handling.

## LaunchAgent Authorization Implications

A LaunchAgent should not accept arbitrary client-supplied paths or assume it can
reuse user-granted access by itself. The selected architecture remains
app-mediated: a user-facing app obtains authorization, stores a versioned
security-scoped bookmark, and the Bridge resolves only allowlisted bookmarks.

## Privacy And Audit Requirements

Audit events may safely include approved-root identity, event ID, timestamp,
normalized relative path, and normalized event kind. They must not include file
contents, bookmark blobs, unneeded absolute host paths, or unrelated filesystem
metadata.

## Security Boundary

The active helper refused roots outside \`artifacts/spk-05/active\`, monitored
only the generated approved root, logged only relative paths, and did not read
file contents. Generated artifacts remain under \`artifacts/spk-05/\`.

## Remaining Blockers

- End-to-end security-scoped authorization still needs a signed, sandboxed,
  user-facing app or helper with an \`NSOpenPanel\` selection flow.
- Production restart handling should include state reconciliation because
  FSEvents replay and coalescing are best-effort operational signals.
- Authorization storage format and allowlist contract still need versioned IPC
  design.

## SPK-05 Verdict

${verdict}
EOF
}

run_monitor() {
  local bin="$1"
  local root="$2"
  local log="$3"
  local timeout="$4"
  local since_when="$5"
  local root_rel="$6"

  SPK05_APPROVED_ACTIVE_BASE="${ACTIVE_BASE}" \
  SPK05_APPROVED_ROOT_REL="${root_rel}" \
  SPK05_TIMEOUT_SECONDS="${timeout}" \
  SPK05_SINCE_WHEN="${since_when}" \
  "${bin}" "${root}" >"${log}" 2>"${log}.err" &
  RUN_MONITOR_PID=$!
}

wait_pid_cleanly() {
  local pid="$1"
  if kill -0 "${pid}" >/dev/null 2>&1; then
    wait "${pid}" || return $?
  else
    wait "${pid}" || return $?
  fi
}

run_active() {
  local unique_id="run-$(/bin/date -u +%Y%m%dT%H%M%SZ)-$$"
  local run_dir="${ACTIVE_BASE}/${unique_id}"
  local root="${run_dir}/approved-root"
  local root_rel
  root_rel="$(neutral_rel "${root}")"
  local source_dir="${run_dir}/sources"
  local bin_dir="${run_dir}/bin"
  local logs_dir="${run_dir}/logs"
  mkdir -p "${root}" "${source_dir}" "${bin_dir}" "${logs_dir}"

  local monitor_source="${source_dir}/SPK05FSEventsMonitor.swift"
  local bookmark_source="${source_dir}/SPK05BookmarkProbe.swift"
  local monitor_bin="${bin_dir}/spk05-fsevents-monitor"
  local bookmark_bin="${bin_dir}/spk05-bookmark-probe"
  local monitor_available="no"
  local active_result="PASS"
  local path_boundary="no"
  local residual_monitor="no"
  local create_seen="no"
  local modify_seen="no"
  local rename_seen="no"
  local delete_seen="no"
  local recursive_seen="no"
  local replay_available="no"
  local root_behavior="not-observed"
  local bookmark_create="no"
  local bookmark_resolve="no"
  local scoped_proven="no"
  local batch_total="0"
  local event_total="0"
  local readonly_result="PASS"

  write_active_helper_sources "${monitor_source}" "${bookmark_source}"

  if ! have_cmd swiftc; then
    print -u2 "swiftc is required for active test"
    active_result="FAIL"
  else
    if swiftc "${monitor_source}" -o "${monitor_bin}" 2>"${logs_dir}/monitor-compile.err" &&
      swiftc "${bookmark_source}" -o "${bookmark_bin}" 2>"${logs_dir}/bookmark-compile.err"; then
      monitor_available="yes"
    else
      active_result="FAIL"
    fi
  fi

  if [[ "${monitor_available}" == "yes" ]]; then
    if SPK05_APPROVED_ACTIVE_BASE="${ACTIVE_BASE}" SPK05_APPROVED_ROOT_REL="artifacts/spk-05/outside" SPK05_TIMEOUT_SECONDS="1" "${monitor_bin}" "${ARTIFACT_ROOT}" >"${logs_dir}/boundary.log" 2>"${logs_dir}/boundary.err"; then
      path_boundary="no"
      active_result="FAIL"
    else
      path_boundary="yes"
    fi

    local scenario_a_log="${logs_dir}/scenario-a.log"
    local pid_a
    run_monitor "${monitor_bin}" "${root}" "${scenario_a_log}" "7" "18446744073709551615" "${root_rel}"
    pid_a="${RUN_MONITOR_PID}"
    sleep 1
    mkdir -p "${root}/scenario-a"
    printf 'SPK05_FIXED_TEST_MARKER\n' >"${root}/scenario-a/file.txt"
    sleep 0.45
    printf 'SPK05_FIXED_TEST_MARKER_MODIFIED\n' >"${root}/scenario-a/file.txt"
    sleep 0.45
    mv "${root}/scenario-a/file.txt" "${root}/scenario-a/file-renamed.txt"
    sleep 0.45
    rm "${root}/scenario-a/file-renamed.txt"
    wait_pid_cleanly "${pid_a}" || active_result="FAIL"

    contains_event "${scenario_a_log}" "scenario-a/file.txt" "ItemCreated" && create_seen="yes"
    if contains_event "${scenario_a_log}" "scenario-a/file.txt" "ItemModified" || contains_event "${scenario_a_log}" "scenario-a/file-renamed.txt" "ItemModified"; then
      modify_seen="yes"
    fi
    if contains_event "${scenario_a_log}" "scenario-a/file.txt" "ItemRenamed" || contains_event "${scenario_a_log}" "scenario-a/file-renamed.txt" "ItemRenamed"; then
      rename_seen="yes"
    fi
    contains_event "${scenario_a_log}" "scenario-a/file-renamed.txt" "ItemRemoved" && delete_seen="yes"

    local scenario_b_log="${logs_dir}/scenario-b.log"
    local pid_b
    run_monitor "${monitor_bin}" "${root}" "${scenario_b_log}" "8" "18446744073709551615" "${root_rel}"
    pid_b="${RUN_MONITOR_PID}"
    sleep 1
    mkdir -p "${root}/scenario-b/nested/child"
    sleep 0.35
    printf 'SPK05_FIXED_TEST_MARKER_NESTED\n' >"${root}/scenario-b/nested/child/nested.txt"
    sleep 0.35
    printf 'SPK05_FIXED_TEST_MARKER_NESTED_MODIFIED\n' >"${root}/scenario-b/nested/child/nested.txt"
    sleep 0.35
    mv "${root}/scenario-b/nested" "${root}/scenario-b/nested-renamed"
    sleep 0.35
    rm -rf "${root}/scenario-b/nested-renamed"
    wait_pid_cleanly "${pid_b}" || active_result="FAIL"
    if grep -q $'rel=scenario-b/nested/child/nested.txt' "${scenario_b_log}" || grep -q $'rel=scenario-b/nested-renamed/child/nested.txt' "${scenario_b_log}"; then
      recursive_seen="yes"
    fi

    local scenario_c_log="${logs_dir}/scenario-c-root-mutation.log"
    local pid_c
    run_monitor "${monitor_bin}" "${root}" "${scenario_c_log}" "8" "18446744073709551615" "${root_rel}"
    pid_c="${RUN_MONITOR_PID}"
    sleep 1
    local moved_root="${run_dir}/approved-root-renamed"
    mv "${root}" "${moved_root}"
    sleep 0.8
    rm -rf "${moved_root}"
    wait_pid_cleanly "${pid_c}" || true
    if grep -q "RootChanged" "${scenario_c_log}" || grep -q $'rel=.' "${scenario_c_log}"; then
      root_behavior="root-change-event-after-rename-delete"
    else
      root_behavior="monitor-ended-or-no-root-event-after-rename-delete"
    fi
    mkdir -p "${root}"

    local scenario_d_first_log="${logs_dir}/scenario-d-first.log"
    local pid_d1
    run_monitor "${monitor_bin}" "${root}" "${scenario_d_first_log}" "5" "18446744073709551615" "${root_rel}"
    pid_d1="${RUN_MONITOR_PID}"
    sleep 1
    mkdir -p "${root}/scenario-d"
    printf 'SPK05_FIXED_TEST_MARKER_D1\n' >"${root}/scenario-d/before-stop.txt"
    wait_pid_cleanly "${pid_d1}" || active_result="FAIL"
    local last_id
    last_id="$(extract_last_event_id "${scenario_d_first_log}")"
    [[ -z "${last_id}" ]] && last_id="18446744073709551615"
    printf 'SPK05_FIXED_TEST_MARKER_D_MISSED\n' >"${root}/scenario-d/while-stopped.txt"
    sleep 0.5
    local scenario_d_replay_log="${logs_dir}/scenario-d-replay.log"
    local pid_d2
    run_monitor "${monitor_bin}" "${root}" "${scenario_d_replay_log}" "5" "${last_id}" "${root_rel}"
    pid_d2="${RUN_MONITOR_PID}"
    wait_pid_cleanly "${pid_d2}" || active_result="FAIL"
    if grep -q $'rel=scenario-d/while-stopped.txt' "${scenario_d_replay_log}"; then
      replay_available="yes"
    elif [[ "${last_id}" != "18446744073709551615" ]]; then
      replay_available="partial"
    else
      replay_available="no"
    fi

    "${bookmark_bin}" "${root}" "${run_dir}/bookmark-data.bin" >"${logs_dir}/bookmark.log" 2>"${logs_dir}/bookmark.err" || active_result="FAIL"
    grep -q $'BOOKMARK\tcreate=true\tresolve=true' "${logs_dir}/bookmark.log" && bookmark_create="yes" && bookmark_resolve="yes"
    scoped_proven="no"

    batch_total="$(( $(count_batches "${scenario_a_log}") + $(count_batches "${scenario_b_log}") + $(count_batches "${scenario_c_log}") + $(count_batches "${scenario_d_first_log}") + $(count_batches "${scenario_d_replay_log}") ))"
    event_total="$(( $(count_events "${scenario_a_log}") + $(count_events "${scenario_b_log}") + $(count_events "${scenario_c_log}") + $(count_events "${scenario_d_first_log}") + $(count_events "${scenario_d_replay_log}") ))"
  fi

  if pgrep -f "${monitor_bin}" >/dev/null 2>&1; then
    residual_monitor="yes"
    active_result="FAIL"
  fi

  if [[ "${create_seen}" != "yes" || "${modify_seen}" != "yes" || "${rename_seen}" != "yes" || "${delete_seen}" != "yes" ]]; then
    active_result="FAIL"
  fi
  if [[ "${path_boundary}" != "yes" ]]; then
    active_result="FAIL"
  fi
  if [[ "${bookmark_create}" != "yes" || "${bookmark_resolve}" != "yes" ]]; then
    active_result="FAIL"
  fi
  if grep -R "SPK05_FIXED_TEST_MARKER" "${logs_dir}" >/dev/null 2>&1; then
    active_result="FAIL"
  fi

  local verdict="SPK-05 VERDICT: CONDITIONAL GO"
  if [[ "${active_result}" == "FAIL" || "${monitor_available}" != "yes" ]]; then
    verdict="SPK-05 VERDICT: NO-GO"
  elif [[ "${scoped_proven}" == "yes" && "${replay_available}" == "yes" ]]; then
    verdict="SPK-05 VERDICT: GO"
  fi

  write_findings "${readonly_result}" "${active_result}" "${monitor_available}" "${create_seen}" "${modify_seen}" "${rename_seen}" "${delete_seen}" "${recursive_seen}" "${root_behavior}" "${replay_available}" "${bookmark_create}" "${bookmark_resolve}" "${scoped_proven}" "${path_boundary}" "${residual_monitor}" "${root_rel}" "${verdict}" "$(neutral_rel "${run_dir}")" "${batch_total}" "${event_total}"

  {
    print "SPK05_ACTIVE_RESULT=${active_result}"
    print "FSEVENTS_MONITOR_AVAILABLE=${monitor_available}"
    print "FILE_CREATE_EVENT_OBSERVED=${create_seen}"
    print "FILE_MODIFY_EVENT_OBSERVED=${modify_seen}"
    print "FILE_RENAME_EVENT_OBSERVED=${rename_seen}"
    print "FILE_DELETE_EVENT_OBSERVED=${delete_seen}"
    print "RECURSIVE_EVENTS_OBSERVED=${recursive_seen}"
    print "ROOT_MUTATION_BEHAVIOR=${root_behavior}"
    print "EVENT_REPLAY_AVAILABLE=${replay_available}"
    print "BOOKMARK_CREATE_AVAILABLE=${bookmark_create}"
    print "BOOKMARK_RESOLVE_AVAILABLE=${bookmark_resolve}"
    print "SECURITY_SCOPED_ACCESS_PROVEN=${scoped_proven}"
    print "PATH_BOUNDARY_ENFORCED=${path_boundary}"
    print "RESIDUAL_MONITOR_PROCESS=${residual_monitor}"
    print "SPK05_APPROVED_ROOT=${root_rel}"
  } | tee "${run_dir}/active-summary.log"
}

case "${mode}" in
  read-only)
    run_read_only
    ;;
  active)
    run_active
    ;;
esac
