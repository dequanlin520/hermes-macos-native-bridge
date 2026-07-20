import CryptoKit
import Darwin
import Foundation
import HermesBridgeServiceManager
import HermesBridgeXPC
import HermesRuntimeFoundation

public enum HermesBridgeCLIExitCode: Int32, Codable, Sendable {
  case success = 0
  case usageError = 2
  case notInstalled = 10
  case serviceUnavailable = 11
  case unhealthy = 12
  case protocolIncompatible = 13
  case requestNotFound = 14
  case operationRejected = 15
  case internalFailure = 20
}

public enum HermesBridgeCLIOutputFormat: String, Codable, Sendable {
  case text
  case json
}

public struct HermesBridgeCLIStatusOutput: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let status: String
  public let installed: Bool
  public let launchdVisible: Bool
  public let protocolVersion: String?
  public let capabilities: [String]
  public let activeVersion: String?
  public let label: String
  public let machService: String

  public init(
    schemaVersion: Int = 1,
    status: String,
    installed: Bool,
    launchdVisible: Bool,
    protocolVersion: String?,
    capabilities: [String],
    activeVersion: String?,
    label: String,
    machService: String
  ) {
    self.schemaVersion = schemaVersion
    self.status = status
    self.installed = installed
    self.launchdVisible = launchdVisible
    self.protocolVersion = protocolVersion
    self.capabilities = capabilities
    self.activeVersion = activeVersion
    self.label = label
    self.machService = machService
  }
}

public enum HermesBridgeDoctorCheckStatus: String, Codable, Equatable, Sendable {
  case pass
  case warning
  case fail
  case notApplicable
}

public struct HermesBridgeDoctorCheck: Codable, Equatable, Sendable {
  public let id: String
  public let status: HermesBridgeDoctorCheckStatus
  public let explanation: String
  public let remediationCode: String?

  public init(
    id: String,
    status: HermesBridgeDoctorCheckStatus,
    explanation: String,
    remediationCode: String? = nil
  ) {
    self.id = id
    self.status = status
    self.explanation = explanation
    self.remediationCode = remediationCode
  }
}

public struct HermesBridgeDoctorReport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let overallStatus: HermesBridgeDoctorCheckStatus
  public let checks: [HermesBridgeDoctorCheck]
  public let permissions: HermesPermissionsDoctorReport

  public init(
    schemaVersion: Int = 1,
    checks: [HermesBridgeDoctorCheck],
    permissions: HermesPermissionsDoctorReport = HermesPermissionsDoctorReport(checks: [])
  ) {
    self.schemaVersion = schemaVersion
    self.checks = checks
    self.permissions = permissions
    if checks.contains(where: { $0.status == .fail }) {
      self.overallStatus = .fail
    } else if checks.contains(where: { $0.status == .warning }) {
      self.overallStatus = .warning
    } else {
      self.overallStatus = .pass
    }
  }
}

public struct HermesBridgeCLIErrorOutput: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let code: String
  public let message: String

  public init(schemaVersion: Int = 1, code: String, message: String) {
    self.schemaVersion = schemaVersion
    self.code = code
    self.message = message
  }
}

public struct HermesBridgeRequestSummary: Codable, Equatable, Sendable {
  public let requestID: String
  public let bindingID: String
  public let lifecycleState: String
  public let cancellationRequested: Bool
  public let resultAvailable: Bool
  public let failureCode: String?
  public let failureRetryable: Bool?

  public init(
    requestID: String,
    bindingID: String,
    lifecycleState: String,
    cancellationRequested: Bool,
    resultAvailable: Bool,
    failureCode: String?,
    failureRetryable: Bool?
  ) {
    self.requestID = requestID
    self.bindingID = bindingID
    self.lifecycleState = lifecycleState
    self.cancellationRequested = cancellationRequested
    self.resultAvailable = resultAvailable
    self.failureCode = failureCode
    self.failureRetryable = failureRetryable
  }

  public init(payload: HermesBridgeRequestStatusPayload) {
    self.init(
      requestID: payload.requestID,
      bindingID: payload.bindingID,
      lifecycleState: payload.lifecycleState,
      cancellationRequested: payload.cancellationRequested,
      resultAvailable: payload.resultAvailable,
      failureCode: payload.failureCode,
      failureRetryable: payload.failureRetryable
    )
  }

  public init(record: HermesRequestRecord) {
    self.init(
      requestID: record.requestID.rawValue,
      bindingID: record.bindingID.rawValue,
      lifecycleState: record.lifecycleState.rawValue,
      cancellationRequested: record.cancellationRequested,
      resultAvailable: record.result?.availability == .available,
      failureCode: record.failure?.code,
      failureRetryable: record.failure?.retryable
    )
  }
}

public struct HermesBridgeCLIRunResult: Sendable {
  public let exitCode: HermesBridgeCLIExitCode
  public let stdout: String
  public let stderr: String
}

public enum HermesBridgeCLICommand: Equatable, Sendable {
  case status
  case doctor
  case permissionsDoctor
  case recentAuditEvents
  case exportAudit(URL)
  case capabilities
  case start
  case stop
  case restart
  case requests
  case requestStatus(String)
  case cancel(String)
  case approvalResponse(String, HermesBridgeApprovalDecision)
  case emergencyStop
}

public struct HermesBridgeCLIInvocation: Equatable, Sendable {
  public let command: HermesBridgeCLICommand
  public let format: HermesBridgeCLIOutputFormat
  public let timeout: TimeInterval
  public let installationRoot: URL?

  public init(arguments: [String]) throws {
    guard let commandName = arguments.first else {
      throw HermesBridgeCLIUsageError.missingCommand
    }
    var format = HermesBridgeCLIOutputFormat.text
    var timeout: TimeInterval = 5
    var installationRoot: URL?
    var requestID: String?
    var decision: HermesBridgeApprovalDecision?
    var outputDirectory: URL?

    var index = 1
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--format":
        index += 1
        guard index < arguments.count else {
          throw HermesBridgeCLIUsageError.missingValue(argument)
        }
        guard let parsed = HermesBridgeCLIOutputFormat(rawValue: arguments[index]) else {
          throw HermesBridgeCLIUsageError.invalidValue(argument)
        }
        format = parsed
      case "--timeout":
        index += 1
        guard index < arguments.count, let parsed = TimeInterval(arguments[index]),
          parsed.isFinite, parsed > 0, parsed <= 30
        else {
          throw HermesBridgeCLIUsageError.invalidValue(argument)
        }
        timeout = parsed
      case "--installation-root":
        index += 1
        guard index < arguments.count else {
          throw HermesBridgeCLIUsageError.missingValue(argument)
        }
        let url = URL(fileURLWithPath: arguments[index]).standardizedFileURL
        guard url.path.contains("/artifacts/") || url.path.contains("/tmp/") else {
          throw HermesBridgeCLIUsageError.invalidValue(argument)
        }
        installationRoot = url
      case "--output-directory":
        index += 1
        guard index < arguments.count else {
          throw HermesBridgeCLIUsageError.missingValue(argument)
        }
        let url = URL(fileURLWithPath: arguments[index]).standardizedFileURL
        guard url.path.contains("/artifacts/") || url.path.contains("/tmp/") else {
          throw HermesBridgeCLIUsageError.invalidValue(argument)
        }
        outputDirectory = url
      case "--request-id":
        index += 1
        guard index < arguments.count else {
          throw HermesBridgeCLIUsageError.missingValue(argument)
        }
        requestID = arguments[index]
      case "--decision":
        index += 1
        guard index < arguments.count else {
          throw HermesBridgeCLIUsageError.missingValue(argument)
        }
        guard let parsed = HermesBridgeApprovalDecision(rawValue: arguments[index]) else {
          throw HermesBridgeCLIUsageError.invalidValue(argument)
        }
        decision = parsed
      default:
        throw HermesBridgeCLIUsageError.unknownOption(argument)
      }
      index += 1
    }

    switch commandName {
    case "status":
      self.command = .status
    case "doctor":
      self.command = .doctor
    case "permissions-doctor":
      self.command = .permissionsDoctor
    case "recent-audit-events":
      self.command = .recentAuditEvents
    case "export-audit":
      guard let outputDirectory else {
        throw HermesBridgeCLIUsageError.missingOption("--output-directory")
      }
      self.command = .exportAudit(outputDirectory)
    case "capabilities":
      self.command = .capabilities
    case "start":
      self.command = .start
    case "stop":
      self.command = .stop
    case "restart":
      self.command = .restart
    case "requests":
      self.command = .requests
    case "request-status":
      guard let requestID else { throw HermesBridgeCLIUsageError.missingOption("--request-id") }
      self.command = .requestStatus(requestID)
    case "cancel":
      guard let requestID else { throw HermesBridgeCLIUsageError.missingOption("--request-id") }
      self.command = .cancel(requestID)
    case "approval-response":
      guard let requestID else { throw HermesBridgeCLIUsageError.missingOption("--request-id") }
      guard let decision else { throw HermesBridgeCLIUsageError.missingOption("--decision") }
      self.command = .approvalResponse(requestID, decision)
    case "emergency-stop":
      self.command = .emergencyStop
    default:
      throw HermesBridgeCLIUsageError.unknownCommand(commandName)
    }

    self.format = format
    self.timeout = timeout
    self.installationRoot = installationRoot
  }

  public var layout: HermesBridgeInstallationLayout {
    if let installationRoot {
      return HermesBridgeInstallationLayout(
        homeRoot: installationRoot.appendingPathComponent("fake-home", isDirectory: true),
        label: "com.hermes.bridge.test.m3-003",
        machService: "com.hermes.bridge.test.m3-003.xpc"
      )
    }
    return .production()
  }
}

public enum HermesBridgeCLIUsageError: Error, Equatable, Sendable {
  case missingCommand
  case unknownCommand(String)
  case unknownOption(String)
  case missingOption(String)
  case missingValue(String)
  case invalidValue(String)
}

public protocol HermesBridgeControlServiceManaging: Sendable {
  func status() async -> HermesBridgeServiceStatus
  func activeVersion() throws -> String?
  func bootstrap() throws
  func stop() throws
  func restart() async throws -> HermesBridgeHealthCheckResult
  func validateInstallation() async -> HermesBridgeHealthCheckResult
}

public protocol HermesBridgeControlXPC: Sendable {
  func capabilities() async throws -> HermesBridgeCapabilitiesPayload
  func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload
  func status(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload
  func cancel(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload
  func respondToApproval(
    requestID: HermesRequestID,
    decision: HermesBridgeApprovalDecision
  ) async throws -> HermesBridgeRequestStatusPayload
  func close() async
}

public protocol HermesBridgeRequestListing: Sendable {
  func listRequests() async throws -> [HermesBridgeRequestSummary]
}

public protocol HermesBridgeDoctorChecking: Sendable {
  func report(layout: HermesBridgeInstallationLayout, timeout: TimeInterval) async
    -> HermesBridgeDoctorReport
}

public protocol HermesBridgeEmergencyStopping: Sendable {
  func emergencyStop(
    manager: HermesBridgeControlServiceManaging,
    xpc: HermesBridgeControlXPC,
    layout: HermesBridgeInstallationLayout
  ) async -> EmergencyStopResult
}

public protocol HermesBridgeAuditViewing: Sendable {
  func recentEvents(layout: HermesBridgeInstallationLayout, limit: Int) async throws
    -> [HermesAuditEvent]
  func export(layout: HermesBridgeInstallationLayout, outputDirectory: URL) async throws
    -> HermesAuditExportManifest
}

public struct EmergencyStopResult: Codable, Equatable, Sendable {
  public let normalShutdownRequested: Bool
  public let bootoutRequested: Bool
  public let verifiedProcessGroupShutdown: Bool
  public let serviceCleanedUp: Bool
  public let message: String
}

public struct HermesBridgeControlRuntime: Sendable {
  public let manager:
    @Sendable (HermesBridgeInstallationLayout) -> HermesBridgeControlServiceManaging
  public let xpc: @Sendable (HermesBridgeInstallationLayout, TimeInterval) -> HermesBridgeControlXPC
  public let lister: @Sendable (HermesBridgeInstallationLayout) -> HermesBridgeRequestListing
  public let doctor: HermesBridgeDoctorChecking
  public let emergencyStopper: HermesBridgeEmergencyStopping
  public let audit: HermesBridgeAuditViewing

  public static let production = HermesBridgeControlRuntime(
    manager: { ProductionServiceManager(layout: $0) },
    xpc: { layout, timeout in ProductionXPC(layout: layout, timeout: timeout) },
    lister: { ProductionRequestLister(layout: $0) },
    doctor: ProductionDoctorChecker(),
    emergencyStopper: ProductionEmergencyStopper(),
    audit: ProductionAuditViewer()
  )
}

public struct HermesBridgeControlRunner: Sendable {
  private let runtime: HermesBridgeControlRuntime

  public init(runtime: HermesBridgeControlRuntime = .production) {
    self.runtime = runtime
  }

  public func run(arguments: [String]) async -> HermesBridgeCLIRunResult {
    do {
      let invocation = try HermesBridgeCLIInvocation(arguments: arguments)
      return await run(invocation)
    } catch let error as HermesBridgeCLIUsageError {
      let output = HermesBridgeCLIErrorOutput(
        code: "usage_error",
        message: HermesBridgeControlRenderer.redact(String(describing: error))
      )
      return HermesBridgeCLIRunResult(
        exitCode: .usageError,
        stdout: "",
        stderr: HermesBridgeControlRenderer.renderError(output, format: .text) + "\n"
      )
    } catch {
      let output = HermesBridgeCLIErrorOutput(code: "internal_failure", message: "internal failure")
      return HermesBridgeCLIRunResult(
        exitCode: .internalFailure,
        stdout: "",
        stderr: HermesBridgeControlRenderer.renderError(output, format: .text) + "\n"
      )
    }
  }

  public func run(_ invocation: HermesBridgeCLIInvocation) async -> HermesBridgeCLIRunResult {
    let layout = invocation.layout
    let manager = runtime.manager(layout)
    let xpc = runtime.xpc(layout, invocation.timeout)
    defer {
      Task { await xpc.close() }
    }

    do {
      switch invocation.command {
      case .status:
        let output = try await statusOutput(manager: manager, xpc: xpc, layout: layout)
        let code: HermesBridgeCLIExitCode =
          output.status == HermesBridgeServiceStatus.notInstalled.rawValue
          ? .notInstalled : .success
        return HermesBridgeCLIRunResult(
          exitCode: code,
          stdout: HermesBridgeControlRenderer.renderStatus(output, format: invocation.format)
            + "\n",
          stderr: ""
        )
      case .doctor:
        let report = await runtime.doctor.report(layout: layout, timeout: invocation.timeout)
        let code: HermesBridgeCLIExitCode =
          report.overallStatus == .fail ? .unhealthy : .success
        return HermesBridgeCLIRunResult(
          exitCode: code,
          stdout: HermesBridgeControlRenderer.renderDoctor(report, format: invocation.format)
            + "\n",
          stderr: ""
        )
      case .permissionsDoctor:
        let report = await runtime.doctor.report(layout: layout, timeout: invocation.timeout)
        return success(
          HermesBridgeControlRenderer.renderPermissions(
            report.permissions, format: invocation.format)
        )
      case .recentAuditEvents:
        let events = try await runtime.audit.recentEvents(layout: layout, limit: 20)
        return success(
          HermesBridgeControlRenderer.renderAuditEvents(events, format: invocation.format))
      case .exportAudit(let outputDirectory):
        let manifest = try await runtime.audit.export(
          layout: layout, outputDirectory: outputDirectory)
        return success(
          HermesBridgeControlRenderer.renderAuditExport(manifest, format: invocation.format))
      case .capabilities:
        let capabilities = try await xpc.capabilities()
        let values = capabilities.capabilities.map(\.rawValue).sorted()
        return success(
          HermesBridgeControlRenderer.renderCapabilities(values, format: invocation.format))
      case .start:
        try manager.bootstrap()
        let output = try await statusOutput(manager: manager, xpc: xpc, layout: layout)
        return success(HermesBridgeControlRenderer.renderStatus(output, format: invocation.format))
      case .stop:
        try manager.stop()
        let output = HermesBridgeCLIStatusOutput(
          status: HermesBridgeServiceStatus.installedStopped.rawValue,
          installed: true,
          launchdVisible: false,
          protocolVersion: nil,
          capabilities: [],
          activeVersion: try manager.activeVersion(),
          label: layout.label,
          machService: layout.machService
        )
        return success(HermesBridgeControlRenderer.renderStatus(output, format: invocation.format))
      case .restart:
        let health = try await manager.restart()
        let report = HermesBridgeDoctorReport(checks: [
          HermesBridgeDoctorCheck(
            id: "restart.health",
            status: health.isHealthy ? .pass : .fail,
            explanation: health.isHealthy ? "restart completed" : "restart health check failed",
            remediationCode: health.isHealthy ? nil : "CHECK_SERVICE_HEALTH")
        ])
        let code: HermesBridgeCLIExitCode = health.isHealthy ? .success : .unhealthy
        return HermesBridgeCLIRunResult(
          exitCode: code,
          stdout: HermesBridgeControlRenderer.renderDoctor(report, format: invocation.format)
            + "\n",
          stderr: ""
        )
      case .requests:
        let requests = try await runtime.lister(layout).listRequests()
        return success(
          HermesBridgeControlRenderer.renderRequests(requests, format: invocation.format))
      case .requestStatus(let id):
        let requestID = try validatedRequestID(id)
        let output = HermesBridgeRequestSummary(payload: try await xpc.status(requestID: requestID))
        return success(HermesBridgeControlRenderer.renderRequest(output, format: invocation.format))
      case .cancel(let id):
        let requestID = try validatedRequestID(id)
        let output = HermesBridgeRequestSummary(payload: try await xpc.cancel(requestID: requestID))
        return success(HermesBridgeControlRenderer.renderRequest(output, format: invocation.format))
      case .approvalResponse(let id, let decision):
        let requestID = try validatedRequestID(id)
        let output = HermesBridgeRequestSummary(
          payload: try await xpc.respondToApproval(requestID: requestID, decision: decision)
        )
        return success(HermesBridgeControlRenderer.renderRequest(output, format: invocation.format))
      case .emergencyStop:
        try? await auditStore(layout: layout).append(
          HermesAuditEvent.make(
            kind: .emergencyStopRequested,
            actor: .controlCLI,
            outcome: .started,
            reasonCode: "requested"
          ))
        let output = await runtime.emergencyStopper.emergencyStop(
          manager: manager,
          xpc: xpc,
          layout: layout
        )
        try? await auditStore(layout: layout).append(
          HermesAuditEvent.make(
            kind: .emergencyStopCompleted,
            actor: .controlCLI,
            outcome: output.serviceCleanedUp ? .succeeded : .failed,
            reasonCode: output.message
          ))
        return success(
          HermesBridgeControlRenderer.renderEmergencyStop(output, format: invocation.format))
      }
    } catch let error as HermesBridgeControlMappedError {
      return failure(error: error, format: invocation.format)
    } catch let error as HermesBridgeXPCClientError {
      return failure(error: HermesBridgeControlMappedError(error), format: invocation.format)
    } catch let error as HermesBridgeXPCError {
      return failure(error: HermesBridgeControlMappedError(error), format: invocation.format)
    } catch let error as HermesBridgeServiceManagerError {
      return failure(error: HermesBridgeControlMappedError(error), format: invocation.format)
    } catch let error as HermesRequestStateStoreError {
      return failure(error: HermesBridgeControlMappedError(error), format: invocation.format)
    } catch {
      return failure(
        error: .init(
          exitCode: .internalFailure,
          code: "internal_failure",
          message: HermesBridgeControlRenderer.redact(String(describing: error))
        ),
        format: invocation.format
      )
    }
  }

  private func statusOutput(
    manager: HermesBridgeControlServiceManaging,
    xpc: HermesBridgeControlXPC,
    layout: HermesBridgeInstallationLayout
  ) async throws -> HermesBridgeCLIStatusOutput {
    let status = await manager.status()
    var version: HermesBridgeProtocolVersionPayload?
    var capabilities: HermesBridgeCapabilitiesPayload?
    if status == .runningHealthy || status == .runningUnhealthy || status == .starting {
      version = try? await xpc.protocolVersion()
      capabilities = try? await xpc.capabilities()
    }
    return HermesBridgeCLIStatusOutput(
      status: status.rawValue,
      installed: status != .notInstalled,
      launchdVisible: [.runningHealthy, .runningUnhealthy, .starting].contains(status),
      protocolVersion: version.map { "\($0.version.major).\($0.version.minor)" },
      capabilities: capabilities?.capabilities.map(\.rawValue).sorted() ?? [],
      activeVersion: try manager.activeVersion(),
      label: layout.label,
      machService: layout.machService
    )
  }

  private func success(_ output: String) -> HermesBridgeCLIRunResult {
    HermesBridgeCLIRunResult(exitCode: .success, stdout: output + "\n", stderr: "")
  }

  private func failure(
    error: HermesBridgeControlMappedError,
    format: HermesBridgeCLIOutputFormat
  ) -> HermesBridgeCLIRunResult {
    let output = HermesBridgeCLIErrorOutput(code: error.code, message: error.message)
    return HermesBridgeCLIRunResult(
      exitCode: error.exitCode,
      stdout: "",
      stderr: HermesBridgeControlRenderer.renderError(output, format: format) + "\n"
    )
  }

  private func validatedRequestID(_ value: String) throws -> HermesRequestID {
    do {
      return try HermesRequestID(rawValue: value)
    } catch {
      throw HermesBridgeControlMappedError(
        exitCode: .usageError,
        code: "invalid_request_id",
        message: "invalid request identifier"
      )
    }
  }

  private func auditStore(layout: HermesBridgeInstallationLayout) async throws
    -> FileBackedHermesAuditStore
  {
    try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(
        root: layout.logsRoot.appendingPathComponent("Audit", isDirectory: true)
      ))
  }
}

public struct HermesBridgeControlMappedError: Error, Sendable {
  public let exitCode: HermesBridgeCLIExitCode
  public let code: String
  public let message: String

  public init(exitCode: HermesBridgeCLIExitCode, code: String, message: String) {
    self.exitCode = exitCode
    self.code = code
    self.message = message
  }

  public init(_ error: HermesBridgeXPCClientError) {
    switch error {
    case .protocolNegotiationFailed:
      self.init(
        exitCode: .protocolIncompatible, code: "protocol_incompatible",
        message: "protocol incompatible")
    case .service(let xpcError):
      self.init(xpcError)
    case .timedOut, .interrupted, .invalidated:
      self.init(
        exitCode: .serviceUnavailable, code: "service_unavailable", message: "service unavailable")
    case .responseDecodingFailure:
      self.init(
        exitCode: .internalFailure, code: "response_decoding_failure",
        message: "response decoding failure")
    }
  }

  public init(_ error: HermesBridgeXPCError) {
    switch error {
    case .unsupportedProtocolVersion:
      self.init(
        exitCode: .protocolIncompatible, code: error.rawValue, message: "protocol incompatible")
    case .requestNotFound:
      self.init(exitCode: .requestNotFound, code: error.rawValue, message: "request not found")
    case .invalidState, .invalidBinding:
      self.init(exitCode: .operationRejected, code: error.rawValue, message: "operation rejected")
    case .serviceUnavailable:
      self.init(exitCode: .serviceUnavailable, code: error.rawValue, message: "service unavailable")
    case .malformedPayload, .oversizedPayload, .unsupportedOperation, .unsupportedCapability,
      .internalFailure, .duplicateAuthorizedRoot, .rootNotFound, .rootInactive, .invalidBookmark,
      .bookmarkTooLarge, .staleAuthorization, .securityScopeUnavailable, .subscriptionNotFound,
      .subscriptionExpired, .acknowledgementRejected, .eventBufferOverflow, .rescanRequired:
      self.init(exitCode: .internalFailure, code: error.rawValue, message: "internal failure")
    }
  }

  public init(_ error: HermesRequestStateStoreError) {
    switch error {
    case .unknownRequest:
      self.init(exitCode: .requestNotFound, code: "request_not_found", message: "request not found")
    default:
      self.init(
        exitCode: .internalFailure, code: "request_state_unavailable",
        message: "request state unavailable")
    }
  }

  public init(_ error: HermesBridgeServiceManagerError) {
    switch error {
    case .invalidLaunchctlBoundary("missing_plist"), .invalidLayout("not_installed"):
      self.init(exitCode: .notInstalled, code: "not_installed", message: "service not installed")
    case .launchctlFailed:
      self.init(
        exitCode: .serviceUnavailable, code: "service_unavailable", message: "service unavailable")
    case .healthCheckFailed:
      self.init(exitCode: .unhealthy, code: "unhealthy", message: "service unhealthy")
    case .invalidLaunchctlBoundary, .invalidPlist, .invalidServiceBinary, .invalidLayout,
      .symlinkEscape, .unsupportedArchitecture:
      self.init(
        exitCode: .operationRejected, code: "operation_rejected", message: "operation rejected")
    case .rollbackUnavailable, .statePersistenceFailed, .realUserOperationRequiresExplicitFlag:
      self.init(exitCode: .internalFailure, code: "internal_failure", message: "internal failure")
    }
  }
}

public enum HermesBridgeControlRenderer {
  public static func renderStatus(
    _ output: HermesBridgeCLIStatusOutput,
    format: HermesBridgeCLIOutputFormat
  ) -> String {
    if format == .json { return json(output) }
    return [
      "status: \(output.status)",
      "installed: \(output.installed)",
      "launchdVisible: \(output.launchdVisible)",
      "activeVersion: \(output.activeVersion ?? "none")",
      "protocolVersion: \(output.protocolVersion ?? "unavailable")",
      "capabilities: \(output.capabilities.joined(separator: ","))",
    ].joined(separator: "\n")
  }

  public static func renderDoctor(
    _ report: HermesBridgeDoctorReport,
    format: HermesBridgeCLIOutputFormat
  ) -> String {
    if format == .json { return json(report) }
    return
      (["doctor: \(report.overallStatus.rawValue)"]
      + report.checks.map {
        "\($0.status.rawValue) \($0.id): \($0.explanation)"
          + ($0.remediationCode.map { " [\($0)]" } ?? "")
      }
      + ["permissions: \(report.permissions.checks.count) checks"]).joined(separator: "\n")
  }

  public static func renderPermissions(
    _ report: HermesPermissionsDoctorReport,
    format: HermesBridgeCLIOutputFormat
  ) -> String {
    if format == .json { return json(report) }
    return
      (["permissionsDoctor: \(report.checks.count) checks"]
      + report.checks.map {
        "\($0.state.rawValue) \($0.kind.rawValue): \($0.detailCode)"
          + ($0.remediationCode.map { " [\($0.rawValue)]" } ?? "")
      }).joined(separator: "\n")
  }

  public static func renderAuditEvents(
    _ events: [HermesAuditEvent],
    format: HermesBridgeCLIOutputFormat
  ) -> String {
    if format == .json { return json(["events": events]) }
    if events.isEmpty { return "audit: none" }
    return events.map {
      "\($0.timestamp) \($0.kind.rawValue) \($0.outcome.rawValue) \($0.reasonCode)"
    }.joined(separator: "\n")
  }

  public static func renderAuditExport(
    _ manifest: HermesAuditExportManifest,
    format: HermesBridgeCLIOutputFormat
  ) -> String {
    if format == .json { return json(manifest) }
    return "auditExport: \(manifest.eventCount) events checksum=\(manifest.sha256)"
  }

  public static func renderCapabilities(
    _ capabilities: [String], format: HermesBridgeCLIOutputFormat
  )
    -> String
  {
    if format == .json { return json(["capabilities": capabilities]) }
    return capabilities.joined(separator: "\n")
  }

  public static func renderRequests(
    _ requests: [HermesBridgeRequestSummary],
    format: HermesBridgeCLIOutputFormat
  ) -> String {
    if format == .json { return json(["requests": requests]) }
    if requests.isEmpty { return "requests: none" }
    return requests.map {
      "\($0.requestID) \($0.bindingID) \($0.lifecycleState) resultAvailable=\($0.resultAvailable)"
    }.joined(separator: "\n")
  }

  public static func renderRequest(
    _ request: HermesBridgeRequestSummary,
    format: HermesBridgeCLIOutputFormat
  ) -> String {
    if format == .json { return json(request) }
    return
      "request: \(request.requestID)\nbinding: \(request.bindingID)\nstate: \(request.lifecycleState)\nresultAvailable: \(request.resultAvailable)"
  }

  public static func renderEmergencyStop(
    _ result: EmergencyStopResult,
    format: HermesBridgeCLIOutputFormat
  ) -> String {
    if format == .json { return json(result) }
    return
      "emergencyStop: \(result.message)\nnormalShutdownRequested: \(result.normalShutdownRequested)\nbootoutRequested: \(result.bootoutRequested)\nverifiedProcessGroupShutdown: \(result.verifiedProcessGroupShutdown)\nserviceCleanedUp: \(result.serviceCleanedUp)"
  }

  public static func renderError(
    _ output: HermesBridgeCLIErrorOutput,
    format: HermesBridgeCLIOutputFormat
  ) -> String {
    if format == .json { return json(output) }
    return "error: \(output.code): \(output.message)"
  }

  public static func redact(_ value: String) -> String {
    var output = value
    output = output.replacingOccurrences(of: NSHomeDirectory(), with: "<redacted-home>")
    output = output.replacingOccurrences(
      of: #"/Users/[A-Za-z0-9._-]+/[^ \n\t"]*"#,
      with: "<redacted-path>",
      options: .regularExpression
    )
    let allowed = output.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || " _.:,=-[]<>/".contains($0))
    }
    return String(allowed.prefix(240))
  }

  private static func json<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return String(data: (try? encoder.encode(value)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
  }
}

public final class ProductionServiceManager: HermesBridgeControlServiceManaging, @unchecked Sendable
{
  private let manager: HermesBridgeServiceManager

  public init(layout: HermesBridgeInstallationLayout) {
    let auditStore: any HermesAuditStore =
      (try? FileBackedHermesAuditStore(
        configuration: HermesAuditStoreConfiguration(
          root: layout.logsRoot.appendingPathComponent("Audit", isDirectory: true)
        ))) as (any HermesAuditStore)? ?? NoopHermesAuditStore()
    self.manager = HermesBridgeServiceManager(layout: layout, auditStore: auditStore)
  }

  public func status() async -> HermesBridgeServiceStatus {
    await manager.status()
  }

  public func activeVersion() throws -> String? {
    try manager.loadState()?.activeVersion
  }

  public func bootstrap() throws {
    try manager.bootstrap()
  }

  public func stop() throws {
    try manager.stop()
  }

  public func restart() async throws -> HermesBridgeHealthCheckResult {
    try await manager.restart()
  }

  public func validateInstallation() async -> HermesBridgeHealthCheckResult {
    await manager.validateInstallation()
  }
}

public actor ProductionXPC: HermesBridgeControlXPC {
  private let client: HermesBridgeXPCClient

  public init(layout: HermesBridgeInstallationLayout, timeout: TimeInterval) {
    self.client = HermesBridgeXPCClient(
      machServiceName: try! HermesBridgeMachServiceName(layout.machService),
      timeout: timeout
    )
  }

  public func capabilities() async throws -> HermesBridgeCapabilitiesPayload {
    try await client.capabilities()
  }

  public func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload {
    try await client.protocolVersion()
  }

  public func status(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload {
    try await client.status(requestID: requestID)
  }

  public func cancel(requestID: HermesRequestID) async throws -> HermesBridgeRequestStatusPayload {
    try await client.cancel(requestID: requestID)
  }

  public func respondToApproval(
    requestID: HermesRequestID,
    decision: HermesBridgeApprovalDecision
  ) async throws -> HermesBridgeRequestStatusPayload {
    try await client.respondToApproval(requestID: requestID, decision: decision)
  }

  public func close() async {
    await client.close()
  }
}

public struct ProductionRequestLister: HermesBridgeRequestListing {
  private let layout: HermesBridgeInstallationLayout

  public init(layout: HermesBridgeInstallationLayout) {
    self.layout = layout
  }

  public func listRequests() async throws -> [HermesBridgeRequestSummary] {
    let store = try FileBackedHermesRequestStateStore(storageRoot: layout.stateRoot)
    return try await store.listRecoverableRequests().map {
      HermesBridgeRequestSummary(record: $0.record)
    }
  }
}

public struct ProductionEmergencyStopper: HermesBridgeEmergencyStopping {
  public init() {}

  public func emergencyStop(
    manager: HermesBridgeControlServiceManaging,
    xpc: HermesBridgeControlXPC,
    layout _: HermesBridgeInstallationLayout
  ) async -> EmergencyStopResult {
    let normal = (try? await xpc.capabilities()) != nil
    try? manager.stop()
    let health = await manager.validateInstallation()
    let cleaned = !health.launchdVisible && !health.processPresent
    return EmergencyStopResult(
      normalShutdownRequested: normal,
      bootoutRequested: true,
      verifiedProcessGroupShutdown: false,
      serviceCleanedUp: cleaned,
      message: cleaned ? "cleaned_up" : "bootout_requested"
    )
  }
}

public struct ProductionAuditViewer: HermesBridgeAuditViewing {
  public init() {}

  public func recentEvents(layout: HermesBridgeInstallationLayout, limit: Int) async throws
    -> [HermesAuditEvent]
  {
    let store = try store(layout: layout)
    return try await store.query(HermesAuditQuery(limit: limit))
  }

  public func export(layout: HermesBridgeInstallationLayout, outputDirectory: URL) async throws
    -> HermesAuditExportManifest
  {
    let store = try store(layout: layout)
    return try await HermesAuditExporter(store: store).export(
      HermesAuditExportRequest(
        query: try HermesAuditQuery(limit: 500),
        outputDirectory: outputDirectory,
        format: .jsonl
      ))
  }

  private func store(layout: HermesBridgeInstallationLayout) throws -> FileBackedHermesAuditStore {
    try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(
        root: layout.logsRoot.appendingPathComponent("Audit", isDirectory: true)
      ))
  }
}

public struct ProductionDoctorChecker: HermesBridgeDoctorChecking {
  public static let checkIDs = [
    "installation.layout",
    "installation.activeVersion",
    "binary.executable",
    "binary.signature",
    "binary.hardenedRuntime",
    "plist.validity",
    "launchagent.fixedLabel",
    "launchagent.fixedMachService",
    "launchd.visibility",
    "xpc.handshake",
    "xpc.protocolVersion",
    "xpc.capabilities",
    "hermes.executableDiscovery",
    "backend.processStatus",
    "requestState.rootReadable",
    "runtimeLog.rootPermissions",
    "temporary.staleFiles",
    "signing.mode",
    "notarization.readiness",
    "service.residualState",
  ]

  public init() {}

  public func report(layout: HermesBridgeInstallationLayout, timeout: TimeInterval) async
    -> HermesBridgeDoctorReport
  {
    let state = try? HermesBridgeServiceManager(layout: layout).loadState()
    let active = state?.activeVersion
    let binary = active.map {
      layout.versionsRoot.appendingPathComponent($0, isDirectory: true)
        .appendingPathComponent(HermesBridgeInstallationLayout.serviceBinaryName)
    }
    var checks: [HermesBridgeDoctorCheck] = []
    checks.append(
      check(
        FileManager.default.fileExists(atPath: layout.applicationSupportRoot.path),
        "installation.layout", "installation layout present", "INSTALL_SERVICE"))
    checks.append(
      check(
        active != nil, "installation.activeVersion",
        active == nil ? "no active version" : "active version recorded", "INSTALL_SERVICE"))
    checks.append(
      check(
        binary.map { isExecutable($0) } ?? false, "binary.executable", "service binary executable",
        "REINSTALL_SERVICE"))
    let signing = binary.flatMap { codeSigningSummary($0) }
    checks.append(
      check(
        signing?.signed == true, "binary.signature", "code signature present", "SIGN_SERVICE_BINARY"
      ))
    checks.append(
      check(
        signing?.hardenedRuntime == true, "binary.hardenedRuntime", "hardened runtime enabled",
        "ENABLE_HARDENED_RUNTIME"))
    checks.append(
      check(
        plistIsValid(layout.launchAgentPlist), "plist.validity", "LaunchAgent plist valid",
        "REINSTALL_LAUNCHAGENT"))
    checks.append(
      check(
        plistValue(layout.launchAgentPlist, key: "Label") == layout.label, "launchagent.fixedLabel",
        "fixed LaunchAgent label", "REINSTALL_LAUNCHAGENT"))
    checks.append(
      check(
        plistMachService(layout.launchAgentPlist) == layout.machService,
        "launchagent.fixedMachService", "fixed Mach service", "REINSTALL_LAUNCHAGENT"))
    let launchdVisible = (try? FixedLaunchctlAdapter().printService(layout: layout)) != nil
    let xpc = await xpcHealth(layout: layout, timeout: timeout)
    checks.append(
      check(launchdVisible, "launchd.visibility", "launchd service visibility", "START_SERVICE"))
    checks.append(check(xpc.handshake, "xpc.handshake", "XPC handshake", "START_SERVICE"))
    checks.append(
      check(xpc.protocol, "xpc.protocolVersion", "protocol major compatible", "UPDATE_BRIDGE"))
    checks.append(
      check(xpc.capabilities, "xpc.capabilities", "capabilities available", "CHECK_XPC"))
    checks.append(
      HermesBridgeDoctorCheck(
        id: "hermes.executableDiscovery", status: .warning,
        explanation: "Hermes executable discovery is deferred to service configuration",
        remediationCode: "CHECK_HERMES_INSTALL"))
    checks.append(
      HermesBridgeDoctorCheck(
        id: "backend.processStatus", status: launchdVisible ? .pass : .notApplicable,
        explanation: launchdVisible
          ? "service process is launchd-visible" : "backend process not running",
        remediationCode: nil))
    checks.append(
      check(
        isReadableDirectory(layout.stateRoot), "requestState.rootReadable",
        "request-state root readable", "FIX_STATE_ROOT_PERMISSIONS"))
    checks.append(
      check(
        isWritableDirectory(layout.runtimeRoot) && isWritableDirectory(layout.logsRoot),
        "runtimeLog.rootPermissions", "runtime and log roots writable",
        "FIX_RUNTIME_LOG_PERMISSIONS"))
    checks.append(
      check(
        staleTemporaryFiles(layout.runtimeRoot) == false, "temporary.staleFiles",
        "no stale temporary files", "CLEAN_STALE_TEMPORARY_FILES"))
    let signingStatus: HermesBridgeDoctorCheckStatus =
      signing?.developerID == true ? .pass : .warning
    checks.append(
      HermesBridgeDoctorCheck(
        id: "signing.mode", status: signingStatus,
        explanation: signing?.developerID == true
          ? "Developer ID signing detected" : "non-Developer ID signing mode",
        remediationCode: signing?.developerID == true ? nil : "USE_DEVELOPER_ID_SIGNING"))
    checks.append(
      HermesBridgeDoctorCheck(
        id: "notarization.readiness",
        status: signing?.developerID == true && signing?.hardenedRuntime == true ? .pass : .warning,
        explanation: "notarization readiness metadata evaluated",
        remediationCode: signing?.developerID == true ? nil : "COMPLETE_NOTARIZATION_PREFLIGHT"))
    checks.append(
      check(
        !launchdVisible || xpc.handshake, "service.residualState",
        "no inconsistent residual service state", "RUN_EMERGENCY_STOP"))
    let permissions = await permissionsReport(
      layout: layout,
      binary: binary,
      launchdVisible: launchdVisible,
      xpcVisible: xpc.handshake
    )
    try? await auditStore(layout: layout).append(
      HermesAuditEvent.make(
        kind: .doctorExecuted,
        actor: .controlCLI,
        outcome: checks.contains(where: { $0.status == .fail }) ? .failed : .succeeded,
        reasonCode: "doctor_complete",
        metadata: try HermesAuditMetadata(["permissionChecks": "\(permissions.checks.count)"])
      ))
    return HermesBridgeDoctorReport(checks: checks, permissions: permissions)
  }

  private func permissionsReport(
    layout: HermesBridgeInstallationLayout,
    binary: URL?,
    launchdVisible: Bool,
    xpcVisible: Bool
  ) async -> HermesPermissionsDoctorReport {
    let roots = try? await HermesBridgeXPCClient(
      machServiceName: try HermesBridgeMachServiceName(layout.machService),
      timeout: 1
    ).listAuthorizedRoots()
    let rootCount = roots?.roots.count
    let staleCount = roots?.roots.filter(\.staleAuthorization).count
    let appIntentMetadata =
      Bundle.main.infoDictionary?["NSUserActivityTypes"] != nil
      || Bundle.main.infoDictionary?["NSSupportsLiveActivities"] != nil
    return HermesPermissionsDoctor().report(
      evidence: HermesPermissionsDoctorEvidence(
        executableURL: binary ?? Bundle.main.executableURL,
        launchAgentInstalled: launchdVisible,
        machServiceAvailable: xpcVisible,
        authorizedRootCount: rootCount,
        staleAuthorizedRootCount: staleCount,
        securityScopedBookmarkAvailable: rootCount.map { $0 > 0 },
        appIntentMetadataPresent: appIntentMetadata,
        notificationsRelevant: true
      ))
  }

  private func auditStore(layout: HermesBridgeInstallationLayout) async throws
    -> FileBackedHermesAuditStore
  {
    try FileBackedHermesAuditStore(
      configuration: HermesAuditStoreConfiguration(
        root: layout.logsRoot.appendingPathComponent("Audit", isDirectory: true)
      ))
  }

  private func xpcHealth(
    layout: HermesBridgeInstallationLayout,
    timeout: TimeInterval
  ) async -> (handshake: Bool, protocol: Bool, capabilities: Bool) {
    guard let name = try? HermesBridgeMachServiceName(layout.machService) else {
      return (false, false, false)
    }
    let client = HermesBridgeXPCClient(machServiceName: name, timeout: timeout)
    do {
      let version = try await client.protocolVersion()
      let capabilities = try await client.capabilities()
      await client.close()
      return (
        true,
        version.version.major == HermesBridgeProtocolVersion.current.major,
        capabilities.capabilities.contains(.protocolVersion)
      )
    } catch {
      await client.close()
      return (false, false, false)
    }
  }

  private func check(
    _ passed: Bool,
    _ id: String,
    _ explanation: String,
    _ remediation: String
  ) -> HermesBridgeDoctorCheck {
    HermesBridgeDoctorCheck(
      id: id,
      status: passed ? .pass : .fail,
      explanation: passed ? explanation : "check failed",
      remediationCode: passed ? nil : remediation
    )
  }

  private func isExecutable(_ url: URL) -> Bool {
    var info = stat()
    guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return false }
    return access(url.path, X_OK) == 0
  }

  private func isReadableDirectory(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue && access(url.path, R_OK) == 0
  }

  private func isWritableDirectory(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue && access(url.path, W_OK) == 0
  }

  private func plistIsValid(_ url: URL) -> Bool {
    guard let data = try? Data(contentsOf: url) else { return false }
    return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil))
      != nil
  }

  private func plistValue(_ url: URL, key: String) -> String? {
    guard let data = try? Data(contentsOf: url),
      let dictionary = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil)
        as? [String: Any]
    else { return nil }
    return dictionary[key] as? String
  }

  private func plistMachService(_ url: URL) -> String? {
    guard let data = try? Data(contentsOf: url),
      let dictionary = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil)
        as? [String: Any],
      let mach = dictionary["MachServices"] as? [String: Bool]
    else { return nil }
    return mach.first(where: { $0.value })?.key
  }

  private func staleTemporaryFiles(_ runtimeRoot: URL) -> Bool {
    let candidates = (try? FileManager.default.contentsOfDirectory(atPath: runtimeRoot.path)) ?? []
    return candidates.contains { $0.hasPrefix(".") && $0.contains(".tmp") }
  }

  private struct SigningSummary {
    let signed: Bool
    let hardenedRuntime: Bool
    let developerID: Bool
  }

  private func codeSigningSummary(_ binary: URL) -> SigningSummary? {
    let process = Process()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = ["-dv", "--verbose=4", binary.path]
    process.standardError = stderr
    process.standardOutput = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return nil
    }
    let details =
      String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return SigningSummary(
      signed: process.terminationStatus == 0,
      hardenedRuntime: details.contains("Runtime Version="),
      developerID: details.contains("Authority=Developer ID Application:")
    )
  }
}
