import Foundation
import HermesBridgeServiceManager
import HermesBridgeXPC
import HermesRuntimeFoundation
import XCTest

@testable import HermesBridgeControlCore

final class HermesBridgeControlTests: XCTestCase {
  private let validRequestID = "hrq_" + String(repeating: "A", count: 43)
  private let bindingID = "binding:v1:test"

  func testCommandParsing() throws {
    let invocation = try HermesBridgeCLIInvocation(arguments: [
      "request-status", "--request-id", validRequestID, "--format", "json", "--timeout", "2",
    ])
    XCTAssertEqual(invocation.format, .json)
    XCTAssertEqual(invocation.timeout, 2)
    XCTAssertEqual(invocation.command, .requestStatus(validRequestID))
  }

  func testUnknownCommandRejected() async throws {
    let result = await runner().run(arguments: ["execute"])
    XCTAssertEqual(result.exitCode, .usageError)
  }

  func testUnknownOptionRejected() async throws {
    let result = await runner().run(arguments: ["status", "--method", "raw"])
    XCTAssertEqual(result.exitCode, .usageError)
  }

  func testTextStatusOutput() async throws {
    let result = await runner(status: .runningHealthy).run(arguments: ["status"])
    XCTAssertEqual(result.exitCode, .success)
    XCTAssertTrue(result.stdout.contains("status: runningHealthy"))
    XCTAssertTrue(result.stdout.contains("capabilities:"))
  }

  func testJSONStatusOutput() async throws {
    let result = await runner(status: .runningHealthy).run(arguments: [
      "status", "--format", "json",
    ])
    XCTAssertEqual(result.exitCode, .success)
    XCTAssertTrue(result.stdout.contains(#""status" : "runningHealthy""#))
    XCTAssertTrue(result.stdout.contains(#""capabilities""#))
  }

  func testDoctorAllPassReport() async throws {
    let report = HermesBridgeDoctorReport(
      checks: ProductionDoctorChecker.checkIDs.map {
        HermesBridgeDoctorCheck(id: $0, status: .pass, explanation: "ok")
      })
    let result = await runner(doctor: FakeDoctor(report: report)).run(arguments: ["doctor"])
    XCTAssertEqual(result.exitCode, .success)
    XCTAssertTrue(result.stdout.contains("doctor: pass"))
  }

  func testDoctorWarningReport() async throws {
    let report = HermesBridgeDoctorReport(checks: [
      HermesBridgeDoctorCheck(id: "signing.mode", status: .warning, explanation: "adhoc")
    ])
    let result = await runner(doctor: FakeDoctor(report: report)).run(arguments: ["doctor"])
    XCTAssertEqual(result.exitCode, .success)
    XCTAssertTrue(result.stdout.contains("doctor: warning"))
  }

  func testDoctorFailureReport() async throws {
    let report = HermesBridgeDoctorReport(checks: [
      HermesBridgeDoctorCheck(
        id: "xpc.handshake",
        status: .fail,
        explanation: "failed",
        remediationCode: "START_SERVICE",
      )
    ])
    let result = await runner(doctor: FakeDoctor(report: report)).run(arguments: ["doctor"])
    XCTAssertEqual(result.exitCode, .unhealthy)
  }

  func testFixedRemediationCodes() async throws {
    let report = HermesBridgeDoctorReport(checks: [
      HermesBridgeDoctorCheck(
        id: "plist.validity",
        status: .fail,
        explanation: "failed",
        remediationCode: "REINSTALL_LAUNCHAGENT"
      )
    ])
    let result = await runner(doctor: FakeDoctor(report: report)).run(arguments: ["doctor"])
    XCTAssertTrue(result.stdout.contains("REINSTALL_LAUNCHAGENT"))
  }

  func testDoctorDoesNotRepair() async throws {
    let manager = FakeManager()
    _ = await runner(manager: manager).run(arguments: ["doctor"])
    XCTAssertEqual(manager.commands, [])
  }

  func testPermissionsDoctorCommandRendersSafeReport() async throws {
    let report = HermesBridgeDoctorReport(
      checks: [],
      permissions: HermesPermissionsDoctorReport(checks: [
        HermesPermissionCheck(
          kind: .accessibility,
          state: .notDetermined,
          detailCode: "preflight_only",
          remediationCode: .openAccessibilitySettings
        )
      ])
    )
    let result = await runner(doctor: FakeDoctor(report: report)).run(arguments: [
      "permissions-doctor", "--format", "json",
    ])
    XCTAssertEqual(result.exitCode, .success)
    XCTAssertTrue(result.stdout.contains(#""kind" : "accessibility""#))
    XCTAssertFalse(result.stdout.localizedCaseInsensitiveContains("prompt"))
    XCTAssertFalse(result.stdout.localizedCaseInsensitiveContains("token"))
  }

  func testCapabilitiesOutput() async throws {
    let result = await runner().run(arguments: ["capabilities"])
    XCTAssertEqual(result.exitCode, .success)
    XCTAssertTrue(result.stdout.contains("protocolVersion"))
  }

  func testStartExactServiceOnly() async throws {
    let manager = FakeManager(status: .installedStopped)
    _ = await runner(manager: manager).run(arguments: ["start"])
    XCTAssertEqual(manager.commands, ["bootstrap"])
  }

  func testStopExactServiceOnly() async throws {
    let manager = FakeManager(status: .runningHealthy)
    _ = await runner(manager: manager).run(arguments: ["stop"])
    XCTAssertEqual(manager.commands, ["stop"])
  }

  func testRestartSequence() async throws {
    let manager = FakeManager(status: .runningHealthy)
    _ = await runner(manager: manager).run(arguments: ["restart"])
    XCTAssertEqual(manager.commands, ["restart"])
  }

  func testRequestListRedaction() async throws {
    let result = await runner(requests: [
      summary(state: "running", resultAvailable: true)
    ]).run(arguments: ["requests", "--format", "json"])
    XCTAssertFalse(result.stdout.localizedCaseInsensitiveContains("token"))
    XCTAssertFalse(result.stdout.localizedCaseInsensitiveContains("prompt"))
    XCTAssertFalse(result.stdout.localizedCaseInsensitiveContains("raw result"))
  }

  func testRequestStatusValidation() async throws {
    let result = await runner().run(arguments: ["request-status", "--request-id", "bad"])
    XCTAssertEqual(result.exitCode, .usageError)
  }

  func testCancelValidation() async throws {
    let result = await runner().run(arguments: ["cancel", "--request-id", "bad"])
    XCTAssertEqual(result.exitCode, .usageError)
  }

  func testApprovalDecisionValidation() async throws {
    let result = await runner().run(arguments: [
      "approval-response", "--request-id", validRequestID, "--decision", "maybe",
    ])
    XCTAssertEqual(result.exitCode, .usageError)
  }

  func testXPCUnavailableError() async throws {
    let xpc = FakeXPC(error: HermesBridgeXPCClientError.timedOut)
    let result = await runner(xpc: xpc).run(arguments: ["capabilities"])
    XCTAssertEqual(result.exitCode, .serviceUnavailable)
  }

  func testProtocolVersionMismatch() async throws {
    let xpc = FakeXPC(error: HermesBridgeXPCClientError.protocolNegotiationFailed)
    let result = await runner(xpc: xpc).run(arguments: ["capabilities"])
    XCTAssertEqual(result.exitCode, .protocolIncompatible)
  }

  func testStableExitCodes() {
    XCTAssertEqual(HermesBridgeCLIExitCode.success.rawValue, 0)
    XCTAssertEqual(HermesBridgeCLIExitCode.usageError.rawValue, 2)
    XCTAssertEqual(HermesBridgeCLIExitCode.notInstalled.rawValue, 10)
    XCTAssertEqual(HermesBridgeCLIExitCode.serviceUnavailable.rawValue, 11)
    XCTAssertEqual(HermesBridgeCLIExitCode.unhealthy.rawValue, 12)
    XCTAssertEqual(HermesBridgeCLIExitCode.protocolIncompatible.rawValue, 13)
    XCTAssertEqual(HermesBridgeCLIExitCode.requestNotFound.rawValue, 14)
    XCTAssertEqual(HermesBridgeCLIExitCode.operationRejected.rawValue, 15)
    XCTAssertEqual(HermesBridgeCLIExitCode.internalFailure.rawValue, 20)
  }

  func testNotInstalledStatusExitCode() async throws {
    let result = await runner(status: .notInstalled).run(arguments: ["status"])
    XCTAssertEqual(result.exitCode, .notInstalled)
    XCTAssertTrue(result.stdout.contains("status: notInstalled"))
  }

  func testBackendTokenAbsent() async throws {
    let result = await runner().run(arguments: ["status", "--format", "json"])
    XCTAssertFalse(result.stdout.localizedCaseInsensitiveContains("token"))
  }

  func testPromptAbsent() async throws {
    let result = await runner().run(arguments: ["request-status", "--request-id", validRequestID])
    XCTAssertFalse(result.stdout.localizedCaseInsensitiveContains("prompt"))
  }

  func testRawResultBodyAbsent() async throws {
    let result = await runner().run(arguments: ["request-status", "--request-id", validRequestID])
    XCTAssertFalse(result.stdout.localizedCaseInsensitiveContains("raw"))
    XCTAssertFalse(result.stdout.localizedCaseInsensitiveContains("body"))
  }

  func testPrivatePathRedaction() {
    let fakePrivatePath = "/Users/" + "privateuser/Library/Application Support/HermesBridge/token"
    let redacted = HermesBridgeControlRenderer.redact(
      "failed at \(fakePrivatePath)"
    )
    XCTAssertFalse(redacted.contains("/Users/privateuser"))
  }

  func testEmergencyStopNormalPath() async throws {
    let emergency = FakeEmergencyStopper(
      result: .init(
        normalShutdownRequested: true,
        bootoutRequested: true,
        verifiedProcessGroupShutdown: false,
        serviceCleanedUp: true,
        message: "cleaned_up"
      ))
    let result = await runner(emergency: emergency).run(arguments: ["emergency-stop"])
    XCTAssertEqual(result.exitCode, .success)
    XCTAssertTrue(result.stdout.contains("cleaned_up"))
  }

  func testEmergencyStopBootoutPath() async throws {
    let manager = FakeManager(status: .runningHealthy)
    let emergency = ProductionEmergencyStopper()
    let result = await runner(manager: manager, emergency: emergency).run(arguments: [
      "emergency-stop"
    ])
    XCTAssertEqual(result.exitCode, .success)
    XCTAssertTrue(manager.commands.contains("stop"))
  }

  func testEmergencyStopIdentityMismatchRefusal() async throws {
    let emergency = FakeEmergencyStopper(
      result: .init(
        normalShutdownRequested: true,
        bootoutRequested: true,
        verifiedProcessGroupShutdown: false,
        serviceCleanedUp: false,
        message: "identity_mismatch_refused"
      ))
    let result = await runner(emergency: emergency).run(arguments: ["emergency-stop"])
    XCTAssertTrue(result.stdout.contains("identity_mismatch_refused"))
  }

  func testRecentAuditEventsAndExportCommands() async throws {
    let event = try HermesAuditEvent.make(
      kind: .doctorExecuted,
      actor: .controlCLI,
      outcome: .succeeded,
      reasonCode: "complete"
    )
    let audit = FakeAuditViewer(events: [event])
    let recent = await runner(audit: audit).run(arguments: ["recent-audit-events"])
    XCTAssertEqual(recent.exitCode, .success)
    XCTAssertTrue(recent.stdout.contains("doctorExecuted"))

    let output = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("hermes-control-audit-\(UUID().uuidString)", isDirectory: true)
    let exported = await runner(audit: audit).run(arguments: [
      "export-audit", "--output-directory", output.path,
    ])
    XCTAssertEqual(exported.exitCode, .success)
    XCTAssertTrue(exported.stdout.contains("checksum="))
  }

  func testVerifyAuditCommandRendersSafeSummary() async throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(
        "artifacts/m6-002/control-verify-\(UUID().uuidString)", isDirectory: true)
    let auditRoot = HermesBridgeInstallationLayout(
      homeRoot: root.appendingPathComponent("fake-home", isDirectory: true),
      label: "com.hermes.bridge.test.m3-003",
      machService: "com.hermes.bridge.test.m3-003.xpc"
    ).logsRoot.appendingPathComponent("Audit", isDirectory: true)
    let store = try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(root: auditRoot))
    try await store.append(
      HermesAuditEvent.make(
        kind: .doctorExecuted,
        actor: .testFixture,
        outcome: .succeeded,
        reasonCode: "complete"
      ))

    let result = await runner().run(arguments: [
      "verify-audit", "--installation-root", root.path,
    ])

    XCTAssertEqual(result.exitCode, .success)
    XCTAssertTrue(result.stdout.contains("auditIntegrity: verifiedUnsigned"))
    XCTAssertFalse(result.stdout.contains("/Users/"))
    XCTAssertFalse(result.stdout.localizedCaseInsensitiveContains("prompt"))
    XCTAssertFalse(result.stdout.localizedCaseInsensitiveContains("token"))
  }

  func testNoKillallOrPkillUse() throws {
    let source = try String(
      contentsOf: URL(
        fileURLWithPath: "Sources/HermesBridgeControlCore/HermesBridgeControlCore.swift"))
    XCTAssertFalse(source.contains("killall"))
    XCTAssertFalse(source.contains("pkill"))
  }

  func testRepeatedStopIdempotency() async throws {
    let manager = FakeManager(status: .installedStopped)
    _ = await runner(manager: manager).run(arguments: ["stop"])
    _ = await runner(manager: manager).run(arguments: ["stop"])
    XCTAssertEqual(manager.commands, ["stop", "stop"])
  }

  func testTestRootOperationWithoutRealInstallation() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("artifacts/m3-003/test-root", isDirectory: true)
    let invocation = try HermesBridgeCLIInvocation(arguments: [
      "status", "--installation-root", root.path,
    ])
    XCTAssertTrue(invocation.layout.label.hasPrefix("com.hermes.bridge.test."))
  }

  func testNoPermanentLaunchAgentModification() async throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("artifacts/m3-003/no-launchagent", isDirectory: true)
    try? FileManager.default.removeItem(at: root)
    let result = await runner().run(arguments: ["status", "--installation-root", root.path])
    XCTAssertEqual(result.exitCode, .success)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: NSHomeDirectory() + "/Library/LaunchAgents/com.hermes.bridge.test.m3-003.plist"
      )
    )
  }

  func testNoResidualTestProcess() throws {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-fl", "com.hermes.bridge.test.m3-003"]
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    let output =
      String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    XCTAssertTrue(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private func runner(
    status: HermesBridgeServiceStatus = .runningHealthy,
    manager: FakeManager? = nil,
    xpc: FakeXPC = FakeXPC(),
    requests: [HermesBridgeRequestSummary] = [],
    doctor: HermesBridgeDoctorChecking = FakeDoctor(report: HermesBridgeDoctorReport(checks: [])),
    emergency: HermesBridgeEmergencyStopping = FakeEmergencyStopper(),
    audit: HermesBridgeAuditViewing = FakeAuditViewer()
  ) -> HermesBridgeControlRunner {
    let manager = manager ?? FakeManager(status: status)
    return HermesBridgeControlRunner(
      runtime: HermesBridgeControlRuntime(
        manager: { _ in manager },
        xpc: { _, _ in xpc },
        lister: { _ in FakeLister(requests: requests) },
        doctor: doctor,
        emergencyStopper: emergency,
        audit: audit
      )
    )
  }

  private func summary(state: String, resultAvailable: Bool = false) -> HermesBridgeRequestSummary {
    HermesBridgeRequestSummary(
      requestID: validRequestID,
      bindingID: bindingID,
      lifecycleState: state,
      cancellationRequested: false,
      resultAvailable: resultAvailable,
      failureCode: nil,
      failureRetryable: nil
    )
  }
}

private final class FakeManager: HermesBridgeControlServiceManaging, @unchecked Sendable {
  var commands: [String] = []
  var currentStatus: HermesBridgeServiceStatus

  init(status: HermesBridgeServiceStatus = .runningHealthy) {
    self.currentStatus = status
  }

  func status() async -> HermesBridgeServiceStatus { currentStatus }
  func activeVersion() throws -> String? { "1.0.0" }
  func bootstrap() throws {
    commands.append("bootstrap")
    currentStatus = .runningHealthy
  }
  func stop() throws {
    commands.append("stop")
    currentStatus = .installedStopped
  }
  func restart() async throws -> HermesBridgeHealthCheckResult {
    commands.append("restart")
    return .healthy()
  }
  func validateInstallation() async -> HermesBridgeHealthCheckResult {
    currentStatus == .installedStopped
      ? .unhealthy("stopped")
      : .healthy()
  }
}

private actor FakeXPC: HermesBridgeControlXPC {
  let error: Error?

  init(error: Error? = nil) {
    self.error = error
  }

  func capabilities() async throws -> HermesBridgeCapabilitiesPayload {
    if let error { throw error }
    return HermesBridgeCapabilitiesPayload()
  }

  func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload {
    if let error { throw error }
    return HermesBridgeProtocolVersionPayload(version: .current)
  }

  func status(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload {
    if let error { throw error }
    return payload(requestID: requestID, state: "running")
  }

  func cancel(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload {
    if let error { throw error }
    return payload(requestID: requestID, state: "cancelled")
  }

  func respondToApproval(
    requestID: HermesRequestID,
    decision _: HermesBridgeApprovalDecision
  ) async throws -> HermesBridgeRequestStatusPayload {
    if let error { throw error }
    return payload(requestID: requestID, state: "running")
  }

  func close() async {}

  private func payload(requestID: HermesRequestID, state: String)
    -> HermesBridgeRequestStatusPayload
  {
    let lifecycleState = HermesRequestLifecycleState(rawValue: state) ?? .running
    let record = try! HermesRequestRecord(
      requestID: requestID,
      bindingID: HermesRequestBindingID(rawValue: "binding:v1:test"),
      lifecycleState: lifecycleState,
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 0),
      result: lifecycleState == .completed
        ? try! HermesRequestResultMetadata(
          availability: .available,
          completedAt: Date(timeIntervalSince1970: 0)
        ) : nil
    )
    return HermesBridgeRequestStatusPayload(record: record)
  }
}

private struct FakeLister: HermesBridgeRequestListing {
  let requests: [HermesBridgeRequestSummary]
  func listRequests() async throws -> [HermesBridgeRequestSummary] { requests }
}

private struct FakeDoctor: HermesBridgeDoctorChecking {
  let report: HermesBridgeDoctorReport
  func report(layout _: HermesBridgeInstallationLayout, timeout _: TimeInterval) async
    -> HermesBridgeDoctorReport
  {
    report
  }
}

private struct FakeEmergencyStopper: HermesBridgeEmergencyStopping {
  let result: EmergencyStopResult

  init(
    result: EmergencyStopResult = .init(
      normalShutdownRequested: true,
      bootoutRequested: true,
      verifiedProcessGroupShutdown: false,
      serviceCleanedUp: true,
      message: "cleaned_up"
    )
  ) {
    self.result = result
  }

  func emergencyStop(
    manager _: HermesBridgeControlServiceManaging,
    xpc _: HermesBridgeControlXPC,
    layout _: HermesBridgeInstallationLayout
  ) async -> EmergencyStopResult {
    result
  }
}

private struct FakeAuditViewer: HermesBridgeAuditViewing {
  let events: [HermesAuditEvent]

  init(events: [HermesAuditEvent] = []) {
    self.events = events
  }

  func recentEvents(layout _: HermesBridgeInstallationLayout, limit: Int) async throws
    -> [HermesAuditEvent]
  {
    Array(events.prefix(limit))
  }

  func export(layout _: HermesBridgeInstallationLayout, outputDirectory _: URL) async throws
    -> HermesAuditExportManifest
  {
    HermesAuditExportManifest(
      schemaVersion: 1,
      exportedAt: Date(timeIntervalSince1970: 0),
      format: .jsonl,
      eventCount: events.count,
      sha256: String(repeating: "a", count: 64),
      dataFileName: "audit-export.jsonl"
    )
  }
}
