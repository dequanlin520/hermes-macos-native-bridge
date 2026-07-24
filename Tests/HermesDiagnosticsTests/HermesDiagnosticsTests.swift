import Foundation
@testable import HermesDiagnostics
@testable import HermesRuntimeFoundation
import XCTest

final class HermesDiagnosticsTests: XCTestCase {
  func testHealthAggregationCountsSessionsAndStates() async throws {
    let commandAPI = RecordingDiagnosticsCommandAPI(
      sessions: [
        Self.status(.running, version: "0.18.2", gatewayRunning: true),
        Self.status(.degraded, version: "0.18.1", gatewayRunning: false),
        Self.status(.failed, version: nil, gatewayRunning: nil),
      ]
    )
    let provider = provider(commandAPI: commandAPI, eventBusState: .ready)

    let result = try await provider.runDiagnostics()

    XCTAssertEqual(result.healthSummary.discoveryState, .ready)
    XCTAssertEqual(result.healthSummary.processState, .failed)
    XCTAssertEqual(result.healthSummary.backendState, .failed)
    XCTAssertEqual(result.healthSummary.sessionState, .failed)
    XCTAssertEqual(result.healthSummary.eventBusState, .ready)
    XCTAssertEqual(result.sessionDiagnostics.activeSessions, 3)
    XCTAssertEqual(result.sessionDiagnostics.runningSessions, 2)
    XCTAssertEqual(result.sessionDiagnostics.failedSessions, 1)
    XCTAssertEqual(result.environmentInfo.hermesVersion, "0.18.2")
  }

  func testProviderExecutionUsesRuntimeCommandAPI() async throws {
    let commandAPI = RecordingDiagnosticsCommandAPI(sessions: [Self.status(.running)])
    let provider = provider(commandAPI: commandAPI)

    _ = try await provider.runDiagnostics()

    XCTAssertEqual(commandAPI.commands, [.listSessions])
  }

  func testRefreshUpdatesControllerState() async {
    let provider = RecordingDiagnosticProvider(result: Self.result(backendState: .ready))
    let controller = HermesDiagnosticsController(provider: provider)

    let state = await controller.refresh()

    XCTAssertEqual(state.result?.healthSummary.backendState, .ready)
    XCTAssertFalse(state.isRefreshing)
    XCTAssertNil(state.lastErrorMessage)
    let runCount = await provider.currentRunCount()
    XCTAssertEqual(runCount, 1)
  }

  func testRunDiagnosticsCapturesFailureStates() async {
    let provider = RecordingDiagnosticProvider(
      error: HermesRuntimeCommandAPIError.operationFailed(
        "token=failure-secret at /Users/example/.hermes/backend pid=4242"
      )
    )
    let controller = HermesDiagnosticsController(provider: provider)

    let state = await controller.runDiagnostics()

    XCTAssertNil(state.result)
    XCTAssertFalse(state.isRunningDiagnostics)
    XCTAssertTrue(state.lastErrorMessage?.contains("token=<redacted>") ?? false)
    XCTAssertFalse(state.lastErrorMessage?.contains("failure-secret") ?? true)
    XCTAssertFalse(state.lastErrorMessage?.contains("/Users/") ?? true)
    XCTAssertFalse(state.lastErrorMessage?.contains("4242") ?? true)
  }

  func testSensitiveDataRedaction() async throws {
    let commandAPI = RecordingDiagnosticsCommandAPI(
      sessions: [Self.status(.running, version: "0.18.2", gatewayRunning: true)]
    )
    let permissions = StaticPermissionsReporter(
      states: [
        HermesDiagnosticPermissionState(
          kind: "credential=/Users/example/key",
          state: "misconfigured",
          detailCode: "password=secret"
        )
      ]
    )
    let provider = HermesDiagnosticProvider(
      commandAPI: commandAPI,
      permissions: permissions,
      environment: HermesDiagnosticEnvironmentSource(
        macOSVersion: { "macOS token=env-secret /Users/example/.hermes" },
        architecture: { "arm64" },
        generatedAt: { Date(timeIntervalSince1970: 1_800_000_000) }
      )
    )

    let result = try await provider.runDiagnostics()
    let dump = String(describing: result)

    XCTAssertFalse(dump.contains("env-secret"))
    XCTAssertFalse(dump.contains("secret"))
    XCTAssertFalse(dump.contains("/Users/"))
    XCTAssertFalse(dump.contains("credential=/Users/example/key"))
    XCTAssertTrue(dump.contains("<redacted>") || dump.contains("unknown"))
  }

  private func provider(
    commandAPI: RecordingDiagnosticsCommandAPI,
    eventBusState: HermesDiagnosticComponentState = .unknown
  ) -> HermesDiagnosticProvider {
    HermesDiagnosticProvider(
      commandAPI: commandAPI,
      permissions: StaticPermissionsReporter(
        states: [
          HermesDiagnosticPermissionState(
            kind: HermesPermissionKind.accessibility.rawValue,
            state: HermesPermissionState.granted.rawValue,
            detailCode: "preflight_only"
          )
        ]
      ),
      environment: HermesDiagnosticEnvironmentSource(
        macOSVersion: { "macOS 13.0" },
        architecture: { "arm64" },
        generatedAt: { Date(timeIntervalSince1970: 1_800_000_000) }
      ),
      eventBusState: { eventBusState }
    )
  }

  fileprivate static func result(
    backendState: HermesDiagnosticComponentState
  ) -> HermesDiagnosticResult {
    HermesDiagnosticResult(
      generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
      healthSummary: HermesDiagnosticHealthSummary(
        discoveryState: .ready,
        processState: .ready,
        backendState: backendState,
        sessionState: .ready,
        eventBusState: .ready
      ),
      environmentInfo: HermesDiagnosticEnvironmentInfo(
        macOSVersion: "macOS 13.0",
        architecture: "arm64",
        hermesVersion: "0.18.2"
      ),
      sessionDiagnostics: HermesDiagnosticSessionDiagnostics(activeSessions: 1, runningSessions: 1)
    )
  }

  private static func status(
    _ status: HermesRuntimeSessionStatus,
    version: String? = "0.18.2",
    gatewayRunning: Bool? = true
  ) -> HermesRuntimeCommandSessionStatus {
    HermesRuntimeCommandSessionStatus(
      snapshot: HermesRuntimeSessionSnapshot(
        sessionID: UUID(),
        backendIdentity: version.map {
          HermesRuntimeBackendIdentity(
            executablePath: "/redacted-by-command-api",
            semanticVersion: $0,
            displayVersion: "Hermes \($0)",
            installationMethod: "fixture",
            releaseDate: nil,
            desktopContract: 3
          )
        },
        processIdentity: nil,
        startTime: status == .running ? Date(timeIntervalSince1970: 1_800_000_000) : nil,
        currentStatus: status,
        capabilities: gatewayRunning.map {
          HermesRuntimeCapabilities(
            authMode: .loopbackToken,
            desktopContract: 3,
            gatewayRunning: $0,
            gatewayState: $0 ? "ready" : "degraded",
            gatewayBusy: false,
            gatewayDrainable: true,
            activeAgents: 0
          )
        },
        lastError: status == .failed
          ? HermesRuntimeSessionError(message: "token=session-secret /Users/example/.hermes")
          : nil,
        shutdownReason: status == .failed ? .startupFailed : nil
      )
    )
  }
}

private final class RecordingDiagnosticsCommandAPI: HermesDiagnosticsRuntimeCommandExecuting,
  @unchecked Sendable
{
  private let lock = NSLock()
  private let sessions: [HermesRuntimeCommandSessionStatus]
  private var commandStorage: [HermesRuntimeCommand] = []

  init(sessions: [HermesRuntimeCommandSessionStatus]) {
    self.sessions = sessions
  }

  var commands: [HermesRuntimeCommand] {
    lock.withLock { commandStorage }
  }

  func execute(_ command: HermesRuntimeCommand) async throws -> HermesRuntimeCommandResult {
    lock.withLock {
      commandStorage.append(command)
    }
    switch command {
    case .listSessions:
      return .sessionList(sessions)
    case .createSession, .startSession, .stopSession, .getSessionStatus, .subscribeEvents:
      throw HermesDiagnosticProviderError.unexpectedRuntimeResult
    }
  }
}

private struct StaticPermissionsReporter: HermesPermissionsDiagnosticReporting {
  let states: [HermesDiagnosticPermissionState]

  func permissionStates() async -> [HermesDiagnosticPermissionState] {
    states
  }
}

private actor RecordingDiagnosticProvider: HermesDiagnosticProviding {
  private let result: HermesDiagnosticResult?
  private let error: Error?
  private(set) var runCount = 0

  init(result: HermesDiagnosticResult? = nil, error: Error? = nil) {
    self.result = result
    self.error = error
  }

  func runDiagnostics() async throws -> HermesDiagnosticResult {
    runCount += 1
    if let error {
      throw error
    }
    return result ?? HermesDiagnosticsTests.result(backendState: .ready)
  }

  func currentRunCount() -> Int {
    runCount
  }
}
