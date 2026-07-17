import Darwin
import Foundation
import HermesBridgeXPC
import HermesRuntimeFoundation
import XCTest

@testable import HermesBridgeService

final class HermesBridgeServiceTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("artifacts/m2-008/unit-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testConfigurationSchemaValidation() throws {
    XCTAssertThrowsError(try configuration(schemaVersion: 99)) {
      XCTAssertEqual(
        $0 as? HermesBridgeServiceConfigurationError,
        .unsupportedSchemaVersion(99)
      )
    }
  }

  func testFixedProductionServiceNameValidation() throws {
    _ = try configuration()
    XCTAssertThrowsError(try configuration(machServiceName: "com.example.other")) {
      XCTAssertEqual(
        $0 as? HermesBridgeServiceConfigurationError,
        .invalidMachServiceName
      )
    }
    _ = try configuration(
      machServiceName: "com.hermes.bridge.test.\(UUID().uuidString)",
      allowTestMachServiceName: true
    )
  }

  func testPathCreationAndPermissions() throws {
    let paths = try HermesBridgeServicePaths(configuration: configuration())

    for root in [paths.runtimeRoot, paths.requestStateRoot, paths.logsRoot, paths.temporaryRoot] {
      var isDirectory: ObjCBool = false
      XCTAssertTrue(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
      XCTAssertTrue(isDirectory.boolValue)
      let attrs = try FileManager.default.attributesOfItem(atPath: root.path)
      let permissions = (attrs[.posixPermissions] as? NSNumber)?.intValue
      XCTAssertEqual(permissions.map { $0 & 0o777 }, 0o700)
    }
  }

  func testSymlinkRootRejection() throws {
    let real = temporaryDirectory.appendingPathComponent("real", isDirectory: true)
    let link = temporaryDirectory.appendingPathComponent("link", isDirectory: true)
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

    XCTAssertThrowsError(
      try HermesBridgeServicePaths(
        runtimeRoot: link,
        requestStateRoot: temporaryDirectory.appendingPathComponent("state", isDirectory: true),
        logsRoot: temporaryDirectory.appendingPathComponent("logs", isDirectory: true),
        temporaryRoot: temporaryDirectory.appendingPathComponent("tmp", isDirectory: true)
      )
    ) {
      guard case .symbolicLinkRoot = $0 as? HermesBridgeServicePathsError else {
        return XCTFail("expected symbolicLinkRoot, got \($0)")
      }
    }
  }

  func testDuplicateBindingRejection() throws {
    let id = "binding:v1:test.binding"
    let first = try binding(id: id)
    let second = try binding(id: id)

    XCTAssertThrowsError(try configuration(bindings: [first, second])) {
      XCTAssertEqual(
        $0 as? HermesBridgeServiceConfigurationError,
        .duplicateBindingID(id)
      )
    }
  }

  func testDisabledBindingBehaviorDoesNotLaunchHermes() async throws {
    let id = "binding:v1:test.disabled"
    let root = try HermesBridgeCompositionRoot(
      configuration: configuration(bindings: [try binding(id: id, enabled: false)])
    )

    await XCTAssertThrowsAsyncError(
      try await root.orchestrator.submit(
        bindingID: HermesRequestBindingID(rawValue: id),
        prompt: "hello"
      )
    ) {
      XCTAssertEqual($0 as? HermesRequestOrchestratorError, .invalidBinding)
    }
    XCTAssertEqual(root.supervisor.state, .idle)
    try? await root.shutdown()
  }

  func testCompositionRootConstruction() throws {
    let root = try HermesBridgeCompositionRoot(configuration: configuration())

    XCTAssertEqual(
      root.configuration.machServiceName, HermesBridgeServiceConfiguration.productionMachServiceName
    )
    XCTAssertEqual(root.supervisor.state, .idle)
  }

  func testServiceHostStartStopIdempotency() async throws {
    let fixture = try AnonymousHostFixture(configuration: configuration())

    try fixture.host.start()
    await fixture.host.stop()
    await fixture.host.stop()
  }

  func testExportedXPCInterfaceCorrectnessAndConnectionAcceptance() async throws {
    let fixture = try AnonymousHostFixture(configuration: configuration())
    try fixture.host.start()

    let response = try await fixture.send(operation: .protocolVersion)

    guard case .success(.protocolVersion(let payload)) = response.result else {
      return XCTFail("expected protocolVersion")
    }
    XCTAssertEqual(payload.version, .current)
    await fixture.host.stop()
  }

  func testCapabilityHandshakeThroughComposedService() async throws {
    let fixture = try AnonymousHostFixture(configuration: configuration())
    try fixture.host.start()

    let response = try await fixture.send(operation: .capabilities)

    guard case .success(.capabilities(let payload)) = response.result else {
      return XCTFail("expected capabilities")
    }
    XCTAssertTrue(payload.capabilities.contains(.protocolVersion))
    XCTAssertTrue(payload.capabilities.contains(.submitRequest))
    XCTAssertEqual(fixture.compositionRoot.supervisor.state, .idle)
    await fixture.host.stop()
  }

  func testStartupFailureRedaction() {
    let message = HermesBridgeServiceMain.redactedStartupFailure(
      HermesBridgeServiceConfigurationError.invalidRoot(temporaryDirectory.path)
    )

    XCTAssertTrue(message.hasPrefix("HERMES_BRIDGE_SERVICE_STARTUP_FAILED error="))
    XCTAssertFalse(message.contains(temporaryDirectory.path))
  }

  func testOrderedShutdownStopsServiceBeforeBackend() async throws {
    let fixture = try AnonymousHostFixture(configuration: configuration())
    try fixture.host.start()

    await fixture.host.stop()

    let log = try String(
      contentsOf: fixture.compositionRoot.paths.logsRoot
        .appendingPathComponent("hermes-bridge-service.log"),
      encoding: .utf8
    )
    XCTAssertLessThan(
      log.range(of: "event=stopping")!.lowerBound,
      log.range(of: "event=stopped")!.lowerBound
    )
    XCTAssertEqual(fixture.compositionRoot.supervisor.state, .idle)
  }

  func testLaunchAgentTemplateServiceNameConsistency() throws {
    let template = try String(
      contentsOfFile: "Packaging/LaunchAgent/com.hermes.bridge.plist.template",
      encoding: .utf8
    )

    XCTAssertTrue(template.contains("<string>com.hermes.bridge</string>"))
    XCTAssertTrue(
      template.contains("<key>\(HermesBridgeServiceConfiguration.productionMachServiceName)</key>"))
    XCTAssertFalse(template.contains("HOME"))
    XCTAssertFalse(template.contains("hermes --safe-mode"))
  }

  func testPlistGenerationAndValidation() throws {
    let binary = try executableFixture()
    let output = temporaryDirectory.appendingPathComponent("generated.plist")

    _ = try shell("Scripts/packaging/generate-launchagent-plist.zsh \(output.path) \(binary.path)")
    _ = try shell("plutil -lint \(output.path)")

    let plist = try String(contentsOf: output, encoding: .utf8)
    XCTAssertTrue(plist.contains(binary.path))
    XCTAssertFalse(plist.contains("__HERMES_BRIDGE_SERVICE_BINARY__"))
  }

  func testPlistContainsNoTokenOrPrompt() throws {
    let binary = try executableFixture()
    let output = temporaryDirectory.appendingPathComponent("generated.plist")
    _ = try shell("Scripts/packaging/generate-launchagent-plist.zsh \(output.path) \(binary.path)")
    let plist = try String(contentsOf: output, encoding: .utf8)

    XCTAssertFalse(plist.localizedCaseInsensitiveContains("token"))
    XCTAssertFalse(plist.localizedCaseInsensitiveContains("prompt"))
    XCTAssertFalse(plist.contains("HERMES_DASHBOARD_SESSION_TOKEN"))
  }

  func testGeneratorRejectsUnsafeOutputPath() throws {
    let binary = try executableFixture()
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("unsafe.plist")

    XCTAssertThrowsError(
      try shell("Scripts/packaging/generate-launchagent-plist.zsh \(output.path) \(binary.path)")
    )
  }

  func testGeneratorRejectsMissingExecutable() throws {
    let output = temporaryDirectory.appendingPathComponent("generated.plist")
    let missing = temporaryDirectory.appendingPathComponent("missing-service")

    XCTAssertThrowsError(
      try shell("Scripts/packaging/generate-launchagent-plist.zsh \(output.path) \(missing.path)")
    )
  }

  func testReadinessMarkerIsFixedAndSanitized() {
    let marker = HermesBridgeServiceMain.readinessMarker(
      serviceName: HermesBridgeServiceConfiguration.productionMachServiceName)

    XCTAssertEqual(
      marker,
      "HERMES_BRIDGE_SERVICE_READY service=com.hermes.bridge.xpc"
    )
    XCTAssertFalse(marker.contains("/"))
  }

  func testNoRealHermesLaunchDuringServiceHostIntegrationTest() async throws {
    let fixture = try AnonymousHostFixture(configuration: configuration())
    try fixture.host.start()
    _ = try await fixture.send(operation: .capabilities)

    XCTAssertEqual(fixture.compositionRoot.supervisor.state, .idle)
    await fixture.host.stop()
  }

  func testNoPersistentLaunchAgentWrite() throws {
    let binary = try executableFixture()
    let output = temporaryDirectory.appendingPathComponent("generated.plist")
    _ = try shell("Scripts/packaging/generate-launchagent-plist.zsh \(output.path) \(binary.path)")

    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: NSHomeDirectory() + "/Library/LaunchAgents/com.hermes.bridge.plist"))
  }

  func testNoResidualServiceProcess() throws {
    let output = try shell("pgrep -fl com.hermes.bridge.test || true")
    XCTAssertTrue(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  func testNoResidualGeneratedPlistOutsideArtifacts() throws {
    let output = try shell(
      "find /tmp -maxdepth 2 -name 'com.hermes.bridge*.plist' 2>/dev/null || true")
    XCTAssertFalse(output.contains("com.hermes.bridge.plist"))
  }

  private func configuration(
    schemaVersion: Int = HermesBridgeServiceConfiguration.currentSchemaVersion,
    machServiceName: String = HermesBridgeServiceConfiguration.productionMachServiceName,
    allowTestMachServiceName: Bool = false,
    bindings: [HermesBridgeBindingDefinition] = []
  ) throws -> HermesBridgeServiceConfiguration {
    try HermesBridgeServiceConfiguration(
      schemaVersion: schemaVersion,
      machServiceName: machServiceName,
      runtimeRoot: temporaryDirectory.appendingPathComponent("Runtime", isDirectory: true),
      requestStateRoot: temporaryDirectory.appendingPathComponent("State", isDirectory: true),
      allowlistedHermesExecutableCandidates: [try executableFixture()],
      loopbackPortPolicy: HermesBridgeLoopbackPortPolicy(fixedPort: try freePort()),
      timeouts: HermesBridgeServiceTimeouts(
        startup: 1,
        gracefulShutdown: 1,
        forcedShutdown: 1,
        gatewayReady: 1
      ),
      maximumConcurrentXPCRequests: 4,
      bindings: bindings,
      allowTestMachServiceName: allowTestMachServiceName
    )
  }

  private func binding(
    id: String,
    enabled: Bool = true
  ) throws -> HermesBridgeBindingDefinition {
    try HermesBridgeBindingDefinition(
      id: id,
      enabled: enabled,
      maximumPromptBytes: 1024,
      timeoutSeconds: 30,
      approvalPolicy: .explicit
    )
  }

  private func executableFixture() throws -> URL {
    let url = temporaryDirectory.appendingPathComponent("fixture-service")
    if !FileManager.default.fileExists(atPath: url.path) {
      try "#!/bin/zsh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o700))],
        ofItemAtPath: url.path
      )
    }
    return url
  }

  private func freePort() throws -> Int {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    XCTAssertGreaterThanOrEqual(fd, 0)
    defer { close(fd) }
    var address = sockaddr_in(
      sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
      sin_family: sa_family_t(AF_INET),
      sin_port: 0,
      sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
      sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
    )
    let bindResult = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    XCTAssertEqual(bindResult, 0)
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    getsockname(
      fd,
      withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
      }, &length)
    return Int(UInt16(bigEndian: address.sin_port))
  }
}

private final class AnonymousHostFixture: @unchecked Sendable {
  let listener: NSXPCListener
  let compositionRoot: HermesBridgeCompositionRoot
  let host: HermesBridgeServiceHost
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(configuration: HermesBridgeServiceConfiguration) throws {
    self.listener = NSXPCListener.anonymous()
    self.compositionRoot = try HermesBridgeCompositionRoot(configuration: configuration)
    self.host = try HermesBridgeServiceHost(
      configuration: configuration,
      compositionRoot: compositionRoot,
      listener: listener
    )
  }

  func send(operation: HermesBridgeOperation) async throws -> HermesBridgeResponseEnvelope {
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    connection.remoteObjectInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
    connection.resume()
    defer {
      connection.invalidate()
    }
    guard let proxy = connection.remoteObjectProxy as? HermesBridgeXPCProtocol else {
      throw HermesBridgeXPCClientError.interrupted
    }
    let request = HermesBridgeRequestEnvelope(
      correlationID: try HermesBridgeCorrelationID(rawValue: "service-test"),
      operation: operation
    )
    let data = try encoder.encode(request)
    let responseData = await withCheckedContinuation { continuation in
      proxy.handleRequest(data) { data in
        continuation.resume(returning: data)
      }
    }
    return try decoder.decode(HermesBridgeResponseEnvelope.self, from: responseData)
  }
}

private func shell(_ command: String) throws -> String {
  let process = Process()
  let stdout = Pipe()
  let stderr = Pipe()
  process.executableURL = URL(fileURLWithPath: "/bin/zsh")
  process.arguments = ["-lc", command]
  process.standardOutput = stdout
  process.standardError = stderr
  try process.run()
  process.waitUntilExit()
  let output =
    String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  let errorOutput =
    String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  guard process.terminationStatus == 0 else {
    throw NSError(
      domain: "ShellError",
      code: Int(process.terminationStatus),
      userInfo: [NSLocalizedDescriptionKey: output + errorOutput]
    )
  }
  return output
}

extension XCTestCase {
  fileprivate func XCTAssertThrowsAsyncError<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void
  ) async {
    do {
      _ = try await expression()
      XCTFail("expected error", file: file, line: line)
    } catch {
      errorHandler(error)
    }
  }
}
