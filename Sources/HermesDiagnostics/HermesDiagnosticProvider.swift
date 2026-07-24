import Foundation
import HermesRuntimeFoundation

public protocol HermesDiagnosticsRuntimeCommandExecuting: Sendable {
  @discardableResult
  func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult
}

extension HermesRuntimeCommandAPI: HermesDiagnosticsRuntimeCommandExecuting {}

public protocol HermesPermissionsDiagnosticReporting: Sendable {
  func permissionStates() async -> [HermesDiagnosticPermissionState]
}

public struct HermesPermissionsDoctorDiagnosticReporter: HermesPermissionsDiagnosticReporting {
  private let doctor: HermesPermissionsDoctor
  private let evidence: @Sendable () -> HermesPermissionsDoctorEvidence

  public init(
    doctor: HermesPermissionsDoctor = HermesPermissionsDoctor(),
    evidence: @escaping @Sendable () -> HermesPermissionsDoctorEvidence = {
      HermesPermissionsDoctorEvidence(executableURL: Bundle.main.executableURL)
    }
  ) {
    self.doctor = doctor
    self.evidence = evidence
  }

  public func permissionStates() async -> [HermesDiagnosticPermissionState] {
    doctor.report(evidence: evidence()).checks.map(HermesDiagnosticPermissionState.init(check:))
  }
}

public struct HermesDiagnosticEnvironmentSource: Sendable {
  public let macOSVersion: @Sendable () -> String
  public let architecture: @Sendable () -> String
  public let generatedAt: @Sendable () -> Date

  public init(
    macOSVersion: @escaping @Sendable () -> String = {
      ProcessInfo.processInfo.operatingSystemVersionString
    },
    architecture: @escaping @Sendable () -> String = {
      #if arch(arm64)
        return "arm64"
      #elseif arch(x86_64)
        return "x86_64"
      #else
        return "unknown"
      #endif
    },
    generatedAt: @escaping @Sendable () -> Date = Date.init
  ) {
    self.macOSVersion = macOSVersion
    self.architecture = architecture
    self.generatedAt = generatedAt
  }
}

public protocol HermesDiagnosticProviding: Sendable {
  func runDiagnostics() async throws -> HermesDiagnosticResult
}

public final class HermesDiagnosticProvider: HermesDiagnosticProviding, @unchecked Sendable {
  private let commandAPI: HermesDiagnosticsRuntimeCommandExecuting
  private let permissions: HermesPermissionsDiagnosticReporting
  private let environment: HermesDiagnosticEnvironmentSource
  private let eventBusState: @Sendable () async -> HermesDiagnosticComponentState

  public init(
    commandAPI: HermesDiagnosticsRuntimeCommandExecuting,
    permissions: HermesPermissionsDiagnosticReporting = HermesPermissionsDoctorDiagnosticReporter(),
    environment: HermesDiagnosticEnvironmentSource = HermesDiagnosticEnvironmentSource(),
    eventBusState: @escaping @Sendable () async -> HermesDiagnosticComponentState = { .unknown }
  ) {
    self.commandAPI = commandAPI
    self.permissions = permissions
    self.environment = environment
    self.eventBusState = eventBusState
  }

  public func runDiagnostics() async throws -> HermesDiagnosticResult {
    let sessions = try await sessionList(from: commandAPI.execute(.listSessions))
    let permissionStates = await permissions.permissionStates()
    let health = await healthSummary(from: sessions)
    let environmentInfo = HermesDiagnosticEnvironmentInfo(
      macOSVersion: environment.macOSVersion(),
      architecture: environment.architecture(),
      hermesVersion: latestHermesVersion(from: sessions),
      permissionStates: permissionStates
    )

    return HermesDiagnosticResult(
      generatedAt: environment.generatedAt(),
      healthSummary: health,
      environmentInfo: environmentInfo,
      sessionDiagnostics: sessionDiagnostics(from: sessions),
      issues: issues(from: health, permissionStates: permissionStates)
    )
  }

  private func healthSummary(
    from sessions: [HermesRuntimeCommandSessionStatus]
  ) async -> HermesDiagnosticHealthSummary {
    HermesDiagnosticHealthSummary(
      discoveryState: sessions.contains { $0.backendVersion != nil } ? .ready : .unavailable,
      processState: processState(from: sessions),
      backendState: backendState(from: sessions),
      sessionState: sessionState(from: sessions),
      eventBusState: await eventBusState()
    )
  }

  private func processState(from sessions: [HermesRuntimeCommandSessionStatus]) -> HermesDiagnosticComponentState {
    guard !sessions.isEmpty else { return .unavailable }
    if sessions.contains(where: { $0.currentStatus == .failed }) { return .failed }
    if sessions.contains(where: { [.running, .degraded, .starting, .stopping].contains($0.currentStatus) }) {
      return .ready
    }
    return .stopped
  }

  private func backendState(from sessions: [HermesRuntimeCommandSessionStatus]) -> HermesDiagnosticComponentState {
    guard !sessions.isEmpty else { return .unavailable }
    if sessions.contains(where: { $0.currentStatus == .failed }) { return .failed }
    if sessions.contains(where: { $0.capabilities?.gatewayRunning == false }) { return .degraded }
    if sessions.contains(where: { $0.capabilities?.gatewayRunning == true }) { return .ready }
    return .unavailable
  }

  private func sessionState(from sessions: [HermesRuntimeCommandSessionStatus]) -> HermesDiagnosticComponentState {
    guard !sessions.isEmpty else { return .unavailable }
    if sessions.contains(where: { $0.currentStatus == .failed }) { return .failed }
    if sessions.contains(where: { $0.currentStatus == .degraded }) { return .degraded }
    if sessions.contains(where: { $0.currentStatus == .running }) { return .ready }
    return .stopped
  }

  private func sessionDiagnostics(
    from sessions: [HermesRuntimeCommandSessionStatus]
  ) -> HermesDiagnosticSessionDiagnostics {
    HermesDiagnosticSessionDiagnostics(
      activeSessions: sessions.filter { $0.currentStatus != .stopped }.count,
      runningSessions: sessions.filter { $0.currentStatus == .running || $0.currentStatus == .degraded }.count,
      failedSessions: sessions.filter { $0.currentStatus == .failed }.count
    )
  }

  private func latestHermesVersion(from sessions: [HermesRuntimeCommandSessionStatus]) -> String {
    sessions.compactMap(\.backendVersion).sorted().last ?? "unknown"
  }

  private func issues(
    from health: HermesDiagnosticHealthSummary,
    permissionStates: [HermesDiagnosticPermissionState]
  ) -> [String] {
    var output: [String] = []
    if health.backendState == .failed {
      output.append("Backend failed")
    } else if health.backendState == .degraded {
      output.append("Backend degraded")
    }
    let deniedPermissions = permissionStates.filter {
      $0.state == HermesPermissionState.denied.rawValue
        || $0.state == HermesPermissionState.misconfigured.rawValue
        || $0.state == HermesPermissionState.restricted.rawValue
    }
    output.append(contentsOf: deniedPermissions.map { "\($0.kind) \($0.state)" })
    return output
  }

  private func sessionList(
    from result: HermesRuntimeCommandResult
  ) throws -> [HermesRuntimeCommandSessionStatus] {
    guard case .sessionList(let sessions) = result else {
      throw HermesDiagnosticProviderError.unexpectedRuntimeResult
    }
    return sessions
  }
}

public enum HermesDiagnosticProviderError: Error, Equatable, CustomStringConvertible {
  case unexpectedRuntimeResult

  public var description: String {
    "Runtime command returned an unexpected result"
  }
}
