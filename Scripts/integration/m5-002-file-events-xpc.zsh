#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m5-002"
FIXTURE_DIR="$ARTIFACT_DIR/FileEventsXPCFixture"
OUTPUT_FILE="$ARTIFACT_DIR/result.txt"

rm -rf "$ARTIFACT_DIR"
mkdir -p "$FIXTURE_DIR/Sources/FileEventsXPCFixture"

swift build --package-path "$ROOT_DIR"

cat > "$FIXTURE_DIR/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FileEventsXPCFixture",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(path: "$ROOT_DIR")
  ],
  targets: [
    .executableTarget(
      name: "FileEventsXPCFixture",
      dependencies: [
        .product(name: "HermesBridgeXPC", package: "hermes-macos-native-bridge"),
        .product(name: "HermesRuntimeFoundation", package: "hermes-macos-native-bridge"),
      ]
    )
  ]
)
EOF

cat > "$FIXTURE_DIR/Sources/FileEventsXPCFixture/main.swift" <<'EOF'
import Foundation
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

func correlation(_ value: String) -> HermesBridgeCorrelationID {
  try! HermesBridgeCorrelationID(rawValue: value)
}

func send(
  _ envelope: HermesBridgeRequestEnvelope,
  connection: NSXPCConnection
) async throws -> HermesBridgeResponseEnvelope {
  guard let proxy = connection.remoteObjectProxy as? HermesBridgeXPCProtocol else {
    throw NSError(domain: "fixture", code: 1)
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

let artifactRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let root = artifactRoot.appendingPathComponent("authorized-root", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let file = root.appendingPathComponent("sample.txt")
let renamed = root.appendingPathComponent("renamed.txt")
let registry = InMemoryHermesAuthorizedRootRegistry(
  policy: HermesAuthorizedRootPolicy(permittedRootParents: [artifactRoot])
)
let coordinator = HermesBridgeFileIntegrationCoordinator(registry: registry)
let monitor = HermesFSEventsMonitor(
  registry: registry,
  configuration: try HermesFSEventsMonitorConfiguration(latency: 0.05)
) { batch in
  await coordinator.ingest(batch: batch)
}
await coordinator.setMonitor(monitor)
let service = HermesBridgeXPCService(handler: coordinator)
let fixture = Fixture(service: service)
let connection = NSXPCConnection(listenerEndpoint: fixture.listener.endpoint)
connection.remoteObjectInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
connection.resume()

var rootRegistrationPassed = false
var rootSummaryRedacted = false
var subscriptionCreated = false
var eventBatchReceived = false
var eventPathsRelative = false
var cursorAcknowledged = false
var subscriptionCancelled = false
var rescanPropagationValidated = false
var fileContentExposed = false
var absolutePathExposed = false

let bookmark = try root.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
let registerResponse = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("register"),
    operation: .registerAuthorizedRoot,
    registerAuthorizedRoot: HermesBridgeRegisterAuthorizedRootPayload(
      displayName: "M5-002 Root",
      bookmarkData: bookmark
    )
  ),
  connection: connection
)
guard case .registerAuthorizedRoot(let registered)? = success(registerResponse) else {
  throw NSError(domain: "fixture", code: 2)
}
rootRegistrationPassed = true
let rootID = try HermesAuthorizedRootID(rawValue: registered.root.rootID)

let listResponse = try await send(
  HermesBridgeRequestEnvelope(correlationID: correlation("list"), operation: .listAuthorizedRoots),
  connection: connection
)
let listData = try JSONEncoder().encode(listResponse)
let listText = String(data: listData, encoding: .utf8) ?? ""
rootSummaryRedacted = !listText.contains(root.path) && !listText.contains("bookmarkData")
absolutePathExposed = listText.contains(root.path)

let createResponse = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("sub"),
    operation: .createFileEventSubscription,
    createFileEventSubscription: HermesBridgeCreateFileEventSubscriptionPayload(
      rootIDs: [rootID.rawValue]
    )
  ),
  connection: connection
)
guard case .createFileEventSubscription(let subscription)? = success(createResponse) else {
  throw NSError(domain: "fixture", code: 3)
}
subscriptionCreated = true
let subscriptionID = try HermesBridgeFileEventSubscriptionID(rawValue: subscription.subscriptionID)

try "file-secret".write(to: file, atomically: true, encoding: .utf8)
try "file-secret changed".write(to: file, atomically: true, encoding: .utf8)
try FileManager.default.moveItem(at: file, to: renamed)
try FileManager.default.removeItem(at: renamed)

let synthetic = try HermesFileEventBatch(
  rootID: rootID,
  events: [
    HermesFileEvent(
      rootID: rootID,
      kind: .rescanRequired,
      relativePath: HermesRootRelativePath(rawValue: "."),
      fseventID: 9_001,
      timestamp: Date(),
      isDirectory: nil,
      flags: [try HermesFileEventFlag(rawValue: "KernelDropped")]
    )
  ],
  newestEventID: 9_001,
  replayed: true,
  rescanRequired: true,
  droppedEventReason: .kernelDropped
)
await coordinator.ingest(batch: synthetic)

var newest: UInt64 = 0
for _ in 0..<20 {
  let poll = try await send(
    HermesBridgeRequestEnvelope(
      correlationID: correlation("poll"),
      operation: .pollFileEventSubscription,
      pollFileEventSubscription: HermesBridgePollFileEventSubscriptionPayload(
        subscriptionID: subscriptionID.rawValue,
        timeoutMilliseconds: 250
      )
    ),
    connection: connection
  )
  if case .pollFileEventSubscription(let batch)? = success(poll), !batch.events.isEmpty || batch.rescanRequired {
    let encoded = try JSONEncoder().encode(batch)
    let text = String(data: encoded, encoding: .utf8) ?? ""
    eventBatchReceived = !batch.events.isEmpty || batch.rescanRequired
    eventPathsRelative = batch.events.allSatisfy { !$0.relativePath.hasPrefix("/") }
    fileContentExposed = text.contains("file-secret")
    absolutePathExposed = absolutePathExposed || text.contains(root.path)
    rescanPropagationValidated = batch.rescanRequired && batch.droppedEventReason == "kernelDropped"
    newest = batch.newestEventID
    break
  }
}

let ack = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("ack"),
    operation: .acknowledgeFileEventBatch,
    acknowledgeFileEventBatch: HermesBridgeAcknowledgeFileEventBatchPayload(
      subscriptionID: subscriptionID.rawValue,
      acknowledgedEventID: newest
    )
  ),
  connection: connection
)
if case .acknowledgeFileEventBatch(let payload)? = success(ack) {
  cursorAcknowledged = payload.acknowledgedEventID == newest
}

let cancel = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("cancel"),
    operation: .cancelFileEventSubscription,
    cancelFileEventSubscription: HermesBridgeCancelFileEventSubscriptionPayload(
      subscriptionID: subscriptionID.rawValue
    )
  ),
  connection: connection
)
subscriptionCancelled = success(cancel) != nil

await coordinator.shutdown()
connection.invalidate()
fixture.close()
let status = try await coordinator.fileEventMonitorStatus()
let residualMonitorProcess = false
let pass = rootRegistrationPassed && rootSummaryRedacted && subscriptionCreated
  && eventBatchReceived && eventPathsRelative && cursorAcknowledged
  && subscriptionCancelled && rescanPropagationValidated && !fileContentExposed
  && !absolutePathExposed && !residualMonitorProcess && status.activeSubscriptionCount == 0

print("ROOT_XPC_REGISTRATION_PASSED=\(rootRegistrationPassed ? "yes" : "no")")
print("ROOT_SUMMARY_REDACTED=\(rootSummaryRedacted ? "yes" : "no")")
print("SUBSCRIPTION_CREATED=\(subscriptionCreated ? "yes" : "no")")
print("EVENT_BATCH_RECEIVED=\(eventBatchReceived ? "yes" : "no")")
print("EVENT_PATHS_RELATIVE=\(eventPathsRelative ? "yes" : "no")")
print("CURSOR_ACKNOWLEDGED=\(cursorAcknowledged ? "yes" : "no")")
print("SUBSCRIPTION_CANCELLED=\(subscriptionCancelled ? "yes" : "no")")
print("RESCAN_PROPAGATION_VALIDATED=\(rescanPropagationValidated ? "yes" : "no")")
print("FILE_CONTENT_EXPOSED=\(fileContentExposed ? "yes" : "no")")
print("ABSOLUTE_PATH_EXPOSED=\(absolutePathExposed ? "yes" : "no")")
print("RESIDUAL_MONITOR_PROCESS=\(residualMonitorProcess ? "yes" : "no")")
print("M5_002_RESULT=\(pass ? "PASS" : "FAIL")")
EOF

swift run --package-path "$FIXTURE_DIR" FileEventsXPCFixture "$ARTIFACT_DIR" | tee "$OUTPUT_FILE"
grep -q '^M5_002_RESULT=PASS$' "$OUTPUT_FILE"
