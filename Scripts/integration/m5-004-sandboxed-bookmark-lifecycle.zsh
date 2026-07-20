#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m5-004"
FIXTURE_DIR="$ARTIFACT_DIR/SandboxedBookmarkFixture"
APP_NAME="Hermes Bridge.app"
APP_BUNDLE="$ARTIFACT_DIR/${APP_NAME}"
ENTITLEMENTS="$ROOT_DIR/Packaging/Entitlements/HermesBridgeApp.entitlements"
OUTPUT_FILE="$ARTIFACT_DIR/result.txt"
ENTITLEMENTS_OUT="$ARTIFACT_DIR/embedded-entitlements.plist"
MANUAL_MODE=no

for arg in "$@"; do
  case "$arg" in
    --manual-sandbox-bookmark-validation)
      MANUAL_MODE=yes
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

SANDBOXED_APP_BUILD_PASSED=no
APP_SANDBOX_ENTITLEMENT_PRESENT=no
USER_SELECTED_RW_ENTITLEMENT_PRESENT=no
BROAD_FILESYSTEM_ENTITLEMENT_PRESENT=yes
APP_INTENTS_METADATA_PRESENT=no
SECURITY_SCOPED_BOOKMARK_CREATED=no
BOOKMARK_PERSISTED_OVER_XPC=no
APP_RESTART_RESOLUTION_PASSED=no
SERVICE_RESTART_RESOLUTION_PASSED=no
SERVICE_SECURITY_SCOPE_STARTED=no
AUTHORIZED_ROOT_EVENT_OBSERVED=no
OUTSIDE_ROOT_EVENT_OBSERVED=yes
BOOKMARK_BYTES_EXPOSED=yes
RESIDUAL_APP_PROCESS=yes
RESIDUAL_MONITOR_PROCESS=yes
M5_004_RESULT=FAIL
M5_004_VERDICT="M5-004 VERDICT: NO-GO"

cleanup() {
  pkill -x HermesBridgeApp >/dev/null 2>&1 || true
  pkill -x "Hermes Bridge" >/dev/null 2>&1 || true
  if pgrep -x HermesBridgeApp >/dev/null 2>&1 || pgrep -x "Hermes Bridge" >/dev/null 2>&1; then
    RESIDUAL_APP_PROCESS=yes
  else
    RESIDUAL_APP_PROCESS=no
  fi
  if pgrep -f "SandboxedBookmarkFixture" >/dev/null 2>&1; then
    RESIDUAL_MONITOR_PROCESS=yes
  else
    RESIDUAL_MONITOR_PROCESS=no
  fi
}
trap cleanup EXIT

metadata_present() {
  local metadata_dir="$APP_BUNDLE/Contents/Resources/HermesAppIntents.appintents/Metadata.appintents"
  [[ -n "$(find "$metadata_dir" -type f -print -quit 2>/dev/null || true)" ]]
}

copy_or_generate_appintents_metadata() {
  local metadata candidate processor source_list const_list metadata_dir
  metadata_dir="$APP_BUNDLE/Contents/Resources/HermesAppIntents.appintents/Metadata.appintents"
  mkdir -p "$metadata_dir"
  candidate="$(find "${HOME}/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug/HermesAppIntents.appintents' -type d 2>/dev/null | sort | tail -n 1 || true)"
  if [[ -n "$candidate" ]]; then
    cp -R "$candidate" "$APP_BUNDLE/Contents/Resources/"
  fi
  metadata="$APP_BUNDLE/Contents/Resources/HermesAppIntents.appintents"
  if metadata_present; then
    return 0
  fi
  source_list="$ARTIFACT_DIR/appintents-sources.txt"
  const_list="$ARTIFACT_DIR/appintents-const-values.txt"
  find Sources/HermesAppIntents Sources/HermesBridgeApp -name '*.swift' | sort > "$source_list"
  find .build -name '*.swiftconstvalues' | sort > "$const_list"
  processor="$(xcrun --find appintentsmetadataprocessor || true)"
  if [[ -n "$processor" && -s "$const_list" ]]; then
    "$processor" \
      --output "$metadata" \
      --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
      --module-name HermesBridgeApp \
      --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
      --xcode-version "$(xcodebuild -version | awk '/Build version/ {print $3}')" \
      --platform-family macOS \
      --deployment-target 13.0 \
      --target-triple "$(swift -print-target-info | awk -F'"' '/"triple"/ {print $4; exit}')" \
      --source-file-list "$source_list" \
      --swift-const-vals-list "$const_list" \
      --force-metadata-output \
      --no-app-shortcuts-localization >/dev/null 2>"$ARTIFACT_DIR/appintents-metadata.log" || true
  fi
}

emit_results() {
  echo "SANDBOXED_APP_BUILD_PASSED=${SANDBOXED_APP_BUILD_PASSED}"
  echo "APP_SANDBOX_ENTITLEMENT_PRESENT=${APP_SANDBOX_ENTITLEMENT_PRESENT}"
  echo "USER_SELECTED_RW_ENTITLEMENT_PRESENT=${USER_SELECTED_RW_ENTITLEMENT_PRESENT}"
  echo "BROAD_FILESYSTEM_ENTITLEMENT_PRESENT=${BROAD_FILESYSTEM_ENTITLEMENT_PRESENT}"
  echo "APP_INTENTS_METADATA_PRESENT=${APP_INTENTS_METADATA_PRESENT}"
  echo "SECURITY_SCOPED_BOOKMARK_CREATED=${SECURITY_SCOPED_BOOKMARK_CREATED}"
  echo "BOOKMARK_PERSISTED_OVER_XPC=${BOOKMARK_PERSISTED_OVER_XPC}"
  echo "APP_RESTART_RESOLUTION_PASSED=${APP_RESTART_RESOLUTION_PASSED}"
  echo "SERVICE_RESTART_RESOLUTION_PASSED=${SERVICE_RESTART_RESOLUTION_PASSED}"
  echo "SERVICE_SECURITY_SCOPE_STARTED=${SERVICE_SECURITY_SCOPE_STARTED}"
  echo "AUTHORIZED_ROOT_EVENT_OBSERVED=${AUTHORIZED_ROOT_EVENT_OBSERVED}"
  echo "OUTSIDE_ROOT_EVENT_OBSERVED=${OUTSIDE_ROOT_EVENT_OBSERVED}"
  echo "BOOKMARK_BYTES_EXPOSED=${BOOKMARK_BYTES_EXPOSED}"
  echo "RESIDUAL_APP_PROCESS=${RESIDUAL_APP_PROCESS}"
  echo "RESIDUAL_MONITOR_PROCESS=${RESIDUAL_MONITOR_PROCESS}"
  echo "M5_004_RESULT=${M5_004_RESULT}"
  echo "${M5_004_VERDICT}"
}

cd "$ROOT_DIR"
rm -rf "$ARTIFACT_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" \
  "$FIXTURE_DIR/Sources/SandboxedBookmarkFixture"

plutil -lint "$ENTITLEMENTS" >/dev/null
xcodebuild -scheme HermesBridgeApp -destination 'platform=macOS' build >/dev/null
swift build --product HermesBridgeApp >/dev/null
cp ".build/debug/HermesBridgeApp" "$APP_BUNDLE/Contents/MacOS/HermesBridgeApp"
cp "Packaging/HermesBridgeApp/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
chmod 755 "$APP_BUNDLE/Contents/MacOS/HermesBridgeApp"
copy_or_generate_appintents_metadata
if metadata_present; then
  APP_INTENTS_METADATA_PRESENT=yes
fi

codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null
codesign -d --entitlements :- "$APP_BUNDLE" > "$ENTITLEMENTS_OUT" 2>/dev/null

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ENTITLEMENTS_OUT" 2>/dev/null || true)" == "true" ]]; then
  APP_SANDBOX_ENTITLEMENT_PRESENT=yes
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' "$ENTITLEMENTS_OUT" 2>/dev/null || true)" == "true" ]]; then
  USER_SELECTED_RW_ENTITLEMENT_PRESENT=yes
fi
if ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.absolute-path.read-write' "$ENTITLEMENTS_OUT" >/dev/null 2>&1 \
  && ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.home-relative-path.read-write' "$ENTITLEMENTS_OUT" >/dev/null 2>&1 \
  && ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.downloads.read-write' "$ENTITLEMENTS_OUT" >/dev/null 2>&1 \
  && ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.documents.read-write' "$ENTITLEMENTS_OUT" >/dev/null 2>&1 \
  && ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.files.absolute-path.read-write' "$ENTITLEMENTS_OUT" >/dev/null 2>&1 \
  && ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.bookmarks.app-scope' "$ENTITLEMENTS_OUT" >/dev/null 2>&1 \
  && ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.bookmarks.document-scope' "$ENTITLEMENTS_OUT" >/dev/null 2>&1; then
  BROAD_FILESYSTEM_ENTITLEMENT_PRESENT=no
fi

/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP_BUNDLE/Contents/Info.plist" >/dev/null
if [[ -x "$APP_BUNDLE/Contents/MacOS/HermesBridgeApp" \
  && "$APP_SANDBOX_ENTITLEMENT_PRESENT" == "yes" \
  && "$USER_SELECTED_RW_ENTITLEMENT_PRESENT" == "yes" \
  && "$BROAD_FILESYSTEM_ENTITLEMENT_PRESENT" == "no" ]]; then
  SANDBOXED_APP_BUILD_PASSED=yes
fi

if [[ "$MANUAL_MODE" == "yes" ]]; then
  mkdir -p "$ARTIFACT_DIR/selected-root" "$ARTIFACT_DIR/outside-root"
  echo "Manual sandbox bookmark validation."
  echo "Launch the artifact app and select only:"
  echo "$ARTIFACT_DIR/selected-root"
  echo "Do not select the sibling outside-root folder."
  open "$APP_BUNDLE"
  M5_004_RESULT=PARTIAL
  M5_004_VERDICT="M5-004 VERDICT: CONDITIONAL GO"
  cleanup
  emit_results
  exit 0
fi

cat > "$FIXTURE_DIR/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SandboxedBookmarkFixture",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(path: "$ROOT_DIR")
  ],
  targets: [
    .executableTarget(
      name: "SandboxedBookmarkFixture",
      dependencies: [
        .product(name: "HermesBridgeMenuBar", package: "hermes-macos-native-bridge"),
        .product(name: "HermesBridgeXPC", package: "hermes-macos-native-bridge"),
        .product(name: "HermesRuntimeFoundation", package: "hermes-macos-native-bridge"),
      ]
    )
  ]
)
EOF

cat > "$FIXTURE_DIR/Sources/SandboxedBookmarkFixture/main.swift" <<'EOF'
import Foundation
import HermesBridgeMenuBar
import HermesBridgeXPC
import HermesRuntimeFoundation

final class Fixture: NSObject, NSXPCListenerDelegate {
  let listener = NSXPCListener.anonymous()
  let service: HermesBridgeXPCService

  init(service: HermesBridgeXPCService) {
    self.service = service
    super.init()
    listener.delegate = self
    listener.resume()
  }

  func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    connection.exportedInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
    connection.exportedObject = service
    connection.resume()
    return true
  }

  func close() {
    service.invalidate()
    listener.invalidate()
  }
}

func result(_ value: Bool) -> String { value ? "yes" : "no" }

let artifactRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let selectedRoot = artifactRoot.appendingPathComponent("selected-root", isDirectory: true)
let outsideRoot = artifactRoot.appendingPathComponent("outside-root", isDirectory: true)
let registryRoot = artifactRoot.appendingPathComponent("registry", isDirectory: true)
try FileManager.default.createDirectory(at: selectedRoot, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: registryRoot, withIntermediateDirectories: true)

let creator = ProductionHermesAuthorizedRootBookmarkCreator()
let appBookmark = try creator.createBookmark(for: selectedRoot)
let securityScopedBookmarkCreated = appBookmark.securityScopeState == .securityScopeStarted
  || appBookmark.securityScopeState == .securityScopedBookmarkCreated

let registry1 = try FileBackedHermesAuthorizedRootRegistry(
  registryRoot: registryRoot,
  policy: HermesAuthorizedRootPolicy(permittedRootParents: [artifactRoot])
)
let coordinator1 = HermesBridgeFileIntegrationCoordinator(registry: registry1)
let fixture1 = Fixture(service: HermesBridgeXPCService(handler: coordinator1))
let connection1 = NSXPCConnection(listenerEndpoint: fixture1.listener.endpoint)
connection1.remoteObjectInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
connection1.resume()

let registeredResponse = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("register"),
    operation: .registerAuthorizedRoot,
    registerAuthorizedRoot: HermesBridgeRegisterAuthorizedRootPayload(
      displayName: appBookmark.displayName,
      bookmarkData: appBookmark.bookmarkData
    )
  ),
  connection: connection1
)
guard case .registerAuthorizedRoot(let registered)? = success(registeredResponse) else {
  throw NSError(domain: "fixture", code: 10)
}
let rootID = try HermesAuthorizedRootID(rawValue: registered.root.rootID)
let recordsAfterRegister = try FileManager.default.contentsOfDirectory(
  at: registryRoot,
  includingPropertiesForKeys: nil
)
let bookmarkPersistedOverXPC = recordsAfterRegister.contains {
  $0.lastPathComponent == "\(rootID.rawValue).json"
}
let listResponse = try await send(
  HermesBridgeRequestEnvelope(correlationID: correlation("list"), operation: .listAuthorizedRoots),
  connection: connection1
)
guard case .listAuthorizedRoots(let listed)? = success(listResponse) else {
  throw NSError(domain: "fixture", code: 11)
}
let listText = String(data: try JSONEncoder().encode(listed), encoding: .utf8) ?? ""
let bookmarkBytesExposedInXPC = listText.contains(appBookmark.bookmarkData.base64EncodedString())
  || listText.contains("bookmarkData")
  || listText.contains(selectedRoot.path)

connection1.invalidate()
await coordinator1.shutdown()
fixture1.close()

var stale = false
let appRestartURL = try URL(
  resolvingBookmarkData: appBookmark.bookmarkData,
  options: [.withSecurityScope, .withoutUI],
  relativeTo: nil,
  bookmarkDataIsStale: &stale
)
let appScopeStarted = appRestartURL.startAccessingSecurityScopedResource()
if appScopeStarted {
  appRestartURL.stopAccessingSecurityScopedResource()
}
let appRestartResolutionPassed = appRestartURL.standardizedFileURL.resolvingSymlinksInPath().path
  == selectedRoot.standardizedFileURL.resolvingSymlinksInPath().path
  && !stale

let registry2 = try FileBackedHermesAuthorizedRootRegistry(
  registryRoot: registryRoot,
  policy: HermesAuthorizedRootPolicy(permittedRootParents: [artifactRoot])
)
let coordinator2 = HermesBridgeFileIntegrationCoordinator(registry: registry2, inactivityTimeout: 4)
let monitor2 = HermesFSEventsMonitor(
  registry: registry2,
  configuration: try HermesFSEventsMonitorConfiguration(latency: 0.10)
) { batch in
  await coordinator2.ingest(batch: batch)
}
await coordinator2.setMonitor(monitor2)
let fixture2 = Fixture(service: HermesBridgeXPCService(handler: coordinator2))
let connection2 = NSXPCConnection(listenerEndpoint: fixture2.listener.endpoint)
connection2.remoteObjectInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
connection2.resume()

let serviceResolutionResponse = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("resolve"),
    operation: .resolveAuthorizedRoot,
    resolveAuthorizedRoot: HermesBridgeRootIDPayload(rootID: rootID.rawValue)
  ),
  connection: connection2
)
guard case .resolveAuthorizedRoot(let serviceResolution)? = success(serviceResolutionResponse)
else {
  throw NSError(domain: "fixture", code: 12)
}
let serviceRestartResolutionPassed = serviceResolution.resolvedSameAuthorizedRoot
  && !serviceResolution.staleAuthorization

let marked = try await registry2.markStale(
  rootID,
  expectedRevision: registered.root.revision,
  updatedAt: Date()
)
let staleStatusResponse = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("status"),
    operation: .authorizedRootStatus,
    authorizedRootStatus: HermesBridgeRootIDPayload(rootID: rootID.rawValue)
  ),
  connection: connection2
)
guard case .authorizedRootStatus(let staleStatus)? = success(staleStatusResponse) else {
  throw NSError(domain: "fixture", code: 13)
}
let refreshBookmark = try creator.createBookmark(for: selectedRoot)
let refreshedResponse = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("refresh"),
    operation: .refreshAuthorizedRoot,
    refreshAuthorizedRoot: HermesBridgeRefreshAuthorizedRootPayload(
      rootID: rootID.rawValue,
      bookmarkData: refreshBookmark.bookmarkData,
      expectedRevision: marked.revision
    )
  ),
  connection: connection2
)
guard case .refreshAuthorizedRoot(let refreshed)? = success(refreshedResponse) else {
  throw NSError(domain: "fixture", code: 14)
}
let staleRefreshRequiresExplicitBookmark = staleStatus.root.staleAuthorization
  && !refreshed.root.staleAuthorization

let subscriptionResponse = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("subscribe"),
    operation: .createFileEventSubscription,
    createFileEventSubscription: HermesBridgeCreateFileEventSubscriptionPayload(
      rootIDs: [rootID.rawValue]
    )
  ),
  connection: connection2
)
guard case .createFileEventSubscription(let subscription)? = success(subscriptionResponse)
else {
  throw NSError(domain: "fixture", code: 15)
}
let subscriptionID = try HermesBridgeFileEventSubscriptionID(rawValue: subscription.subscriptionID)
try await Task.sleep(nanoseconds: 250_000_000)
try "selected-change".write(
  to: selectedRoot.appendingPathComponent("selected-event.txt"),
  atomically: true,
  encoding: .utf8
)
try "outside-change".write(
  to: outsideRoot.appendingPathComponent("outside-event.txt"),
  atomically: true,
  encoding: .utf8
)

var authorizedRootEventObserved = false
var outsideRootEventObserved = false
for _ in 0..<20 {
  let pollResponse = try await send(
    HermesBridgeRequestEnvelope(
      correlationID: correlation("poll-\(UUID().uuidString)"),
      operation: .pollFileEventSubscription,
      pollFileEventSubscription: HermesBridgePollFileEventSubscriptionPayload(
        subscriptionID: subscriptionID.rawValue,
        timeoutMilliseconds: 250
      )
    ),
    connection: connection2
  )
  guard case .pollFileEventSubscription(let batch)? = success(pollResponse) else {
    throw NSError(domain: "fixture", code: 16)
  }
  for event in batch.events {
    if event.relativePath == "selected-event.txt" {
      authorizedRootEventObserved = true
    }
    if event.relativePath.contains("outside-event.txt") {
      outsideRootEventObserved = true
    }
  }
  if authorizedRootEventObserved {
    break
  }
}

let removeResponse = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("remove"),
    operation: .removeAuthorizedRoot,
    removeAuthorizedRoot: HermesBridgeRootIDPayload(
      rootID: rootID.rawValue
    )
  ),
  connection: connection2
)
guard case .removeAuthorizedRoot(_)? = success(removeResponse) else {
  throw NSError(domain: "fixture", code: 17)
}
await coordinator2.shutdown()
connection2.invalidate()
fixture2.close()
try FileManager.default.removeItem(at: selectedRoot)
try FileManager.default.removeItem(at: outsideRoot)
try FileManager.default.removeItem(at: registryRoot)

print("SECURITY_SCOPED_BOOKMARK_CREATED=\(result(securityScopedBookmarkCreated))")
print("BOOKMARK_PERSISTED_OVER_XPC=\(result(bookmarkPersistedOverXPC))")
print("APP_RESTART_RESOLUTION_PASSED=\(result(appRestartResolutionPassed))")
print("SERVICE_RESTART_RESOLUTION_PASSED=\(result(serviceRestartResolutionPassed && staleRefreshRequiresExplicitBookmark))")
print("SERVICE_SECURITY_SCOPE_STARTED=\(result(serviceResolution.securityScopeStarted))")
print("AUTHORIZED_ROOT_EVENT_OBSERVED=\(result(authorizedRootEventObserved))")
print("OUTSIDE_ROOT_EVENT_OBSERVED=\(result(outsideRootEventObserved))")
print("BOOKMARK_BYTES_EXPOSED=\(result(bookmarkBytesExposedInXPC))")

func correlation(_ value: String) -> HermesBridgeCorrelationID {
  let safe = value.filter {
    $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
  }
  return try! HermesBridgeCorrelationID(rawValue: String(safe.prefix(120)))
}

func send(
  _ envelope: HermesBridgeRequestEnvelope,
  connection: NSXPCConnection
) async throws -> HermesBridgeResponseEnvelope {
  guard let proxy = connection.remoteObjectProxy as? HermesBridgeXPCProtocol else {
    throw NSError(domain: "fixture", code: 20)
  }
  let requestData = try JSONEncoder().encode(envelope)
  let responseData = await withCheckedContinuation { continuation in
    proxy.handleRequest(requestData) { continuation.resume(returning: $0) }
  }
  return try JSONDecoder().decode(HermesBridgeResponseEnvelope.self, from: responseData)
}

func success(_ response: HermesBridgeResponseEnvelope) -> HermesBridgeSuccessPayload? {
  if case .success(let payload) = response.result { return payload }
  return nil
}
EOF

set +e
swift run --package-path "$FIXTURE_DIR" SandboxedBookmarkFixture "$ARTIFACT_DIR" > "$OUTPUT_FILE"
fixture_status=$?
set -e

if [[ $fixture_status -eq 0 ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      SECURITY_SCOPED_BOOKMARK_CREATED) SECURITY_SCOPED_BOOKMARK_CREATED="$value" ;;
      BOOKMARK_PERSISTED_OVER_XPC) BOOKMARK_PERSISTED_OVER_XPC="$value" ;;
      APP_RESTART_RESOLUTION_PASSED) APP_RESTART_RESOLUTION_PASSED="$value" ;;
      SERVICE_RESTART_RESOLUTION_PASSED) SERVICE_RESTART_RESOLUTION_PASSED="$value" ;;
      SERVICE_SECURITY_SCOPE_STARTED) SERVICE_SECURITY_SCOPE_STARTED="$value" ;;
      AUTHORIZED_ROOT_EVENT_OBSERVED) AUTHORIZED_ROOT_EVENT_OBSERVED="$value" ;;
      OUTSIDE_ROOT_EVENT_OBSERVED) OUTSIDE_ROOT_EVENT_OBSERVED="$value" ;;
      BOOKMARK_BYTES_EXPOSED) BOOKMARK_BYTES_EXPOSED="$value" ;;
    esac
  done < "$OUTPUT_FILE"
fi

rm -rf "$FIXTURE_DIR" "$ARTIFACT_DIR/selected-root" "$ARTIFACT_DIR/outside-root" \
  "$ARTIFACT_DIR/registry"
cleanup

if [[ "$SANDBOXED_APP_BUILD_PASSED" == "yes" \
  && "$APP_SANDBOX_ENTITLEMENT_PRESENT" == "yes" \
  && "$USER_SELECTED_RW_ENTITLEMENT_PRESENT" == "yes" \
  && "$BROAD_FILESYSTEM_ENTITLEMENT_PRESENT" == "no" \
  && "$APP_INTENTS_METADATA_PRESENT" == "yes" \
  && "$SECURITY_SCOPED_BOOKMARK_CREATED" == "yes" \
  && "$BOOKMARK_PERSISTED_OVER_XPC" == "yes" \
  && "$APP_RESTART_RESOLUTION_PASSED" == "yes" \
  && "$SERVICE_RESTART_RESOLUTION_PASSED" == "yes" \
  && "$AUTHORIZED_ROOT_EVENT_OBSERVED" == "yes" \
  && "$OUTSIDE_ROOT_EVENT_OBSERVED" == "no" \
  && "$BOOKMARK_BYTES_EXPOSED" == "no" \
  && "$RESIDUAL_APP_PROCESS" == "no" \
  && "$RESIDUAL_MONITOR_PROCESS" == "no" ]]; then
  if [[ "$SERVICE_SECURITY_SCOPE_STARTED" == "yes" ]]; then
    M5_004_RESULT=PASS
    M5_004_VERDICT="M5-004 VERDICT: CONDITIONAL GO"
  else
    M5_004_RESULT=PARTIAL
    M5_004_VERDICT="M5-004 VERDICT: CONDITIONAL GO"
  fi
elif [[ $fixture_status -eq 0 && "$SANDBOXED_APP_BUILD_PASSED" == "yes" ]]; then
  M5_004_RESULT=PARTIAL
  M5_004_VERDICT="M5-004 VERDICT: CONDITIONAL GO"
else
  M5_004_RESULT=FAIL
  M5_004_VERDICT="M5-004 VERDICT: NO-GO"
fi

emit_results
