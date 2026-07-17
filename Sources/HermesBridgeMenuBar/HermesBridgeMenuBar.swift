import Foundation
import HermesBridgeControlCore
import HermesBridgeServiceManager
import HermesBridgeXPC

public enum HermesBridgeMenuBarServiceStatus: String, Codable, Equatable, Sendable {
  case loading
  case unavailable
  case installedStopped
  case runningHealthy
  case runningUnhealthy
  case protocolIncompatible
}

public struct HermesBridgeMenuBarRequestSummary: Codable, Equatable, Sendable {
  public let requestID: String
  public let bindingID: String
  public let lifecycleState: String
  public let resultAvailable: Bool
  public let failureCode: String?

  public init(summary: HermesBridgeRequestSummary) {
    self.requestID = Self.safeID(summary.requestID)
    self.bindingID = Self.safeID(summary.bindingID)
    self.lifecycleState = Self.safeToken(summary.lifecycleState)
    self.resultAvailable = summary.resultAvailable
    self.failureCode = summary.failureCode.map(Self.safeToken)
  }

  public init(
    requestID: String,
    bindingID: String,
    lifecycleState: String,
    resultAvailable: Bool,
    failureCode: String? = nil
  ) {
    self.requestID = Self.safeID(requestID)
    self.bindingID = Self.safeID(bindingID)
    self.lifecycleState = Self.safeToken(lifecycleState)
    self.resultAvailable = resultAvailable
    self.failureCode = failureCode.map(Self.safeToken)
  }

  private static func safeID(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ":" || $0 == "." || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(128))
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(64))
  }
}

public struct HermesBridgeMenuBarState: Codable, Equatable, Sendable {
  public var serviceStatus: HermesBridgeMenuBarServiceStatus
  public var installed: Bool
  public var running: Bool
  public var healthy: Bool
  public var protocolCompatible: Bool
  public var protocolVersion: String?
  public var capabilities: [String]
  public var enabledBindingCount: Int
  public var recentRequests: [HermesBridgeMenuBarRequestSummary]
  public var lastActionMessage: String?

  public init(
    serviceStatus: HermesBridgeMenuBarServiceStatus = .loading,
    installed: Bool = false,
    running: Bool = false,
    healthy: Bool = false,
    protocolCompatible: Bool = false,
    protocolVersion: String? = nil,
    capabilities: [String] = [],
    enabledBindingCount: Int = 0,
    recentRequests: [HermesBridgeMenuBarRequestSummary] = [],
    lastActionMessage: String? = nil
  ) {
    self.serviceStatus = serviceStatus
    self.installed = installed
    self.running = running
    self.healthy = healthy
    self.protocolCompatible = protocolCompatible
    self.protocolVersion = protocolVersion
    self.capabilities = capabilities.sorted()
    self.enabledBindingCount = min(
      max(0, enabledBindingCount), HermesBridgeBindingSummary.maximumCount)
    self.recentRequests = Array(recentRequests.prefix(8))
    self.lastActionMessage = lastActionMessage.map { String($0.prefix(120)) }
  }
}

public struct HermesBridgeMenuBarActionResult: Codable, Equatable, Sendable {
  public let succeeded: Bool
  public let safeMessage: String

  public init(succeeded: Bool, safeMessage: String) {
    self.succeeded = succeeded
    self.safeMessage = String(safeMessage.prefix(120))
  }
}

public protocol HermesBridgeMenuBarServiceManaging: Sendable {
  func status() async -> HermesBridgeServiceStatus
  func start() async -> HermesBridgeMenuBarActionResult
  func restart() async -> HermesBridgeMenuBarActionResult
}

public protocol HermesBridgeMenuBarXPCClient: Sendable {
  func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload
  func capabilities() async throws -> HermesBridgeCapabilitiesPayload
  func listEnabledBindings() async throws -> HermesBridgeBindingListPayload
  func close() async
}

public protocol HermesBridgeMenuBarRequestListing: Sendable {
  func recentRequests() async throws -> [HermesBridgeMenuBarRequestSummary]
}

public protocol HermesBridgeMenuBarDoctorRunning: Sendable {
  func runDoctor() async -> HermesBridgeMenuBarActionResult
}

public struct HermesBridgeMenuBarEnvironment: Sendable {
  public let serviceManager: any HermesBridgeMenuBarServiceManaging
  public let xpcClient: any HermesBridgeMenuBarXPCClient
  public let requestLister: any HermesBridgeMenuBarRequestListing
  public let doctor: any HermesBridgeMenuBarDoctorRunning

  public init(
    serviceManager: any HermesBridgeMenuBarServiceManaging,
    xpcClient: any HermesBridgeMenuBarXPCClient,
    requestLister: any HermesBridgeMenuBarRequestListing,
    doctor: any HermesBridgeMenuBarDoctorRunning
  ) {
    self.serviceManager = serviceManager
    self.xpcClient = xpcClient
    self.requestLister = requestLister
    self.doctor = doctor
  }

  public static func production() -> HermesBridgeMenuBarEnvironment {
    let layout = HermesBridgeInstallationLayout.production()
    return HermesBridgeMenuBarEnvironment(
      serviceManager: ProductionMenuBarServiceManager(layout: layout),
      xpcClient: ProductionMenuBarXPCClient(layout: layout),
      requestLister: ProductionMenuBarRequestLister(layout: layout),
      doctor: ProductionMenuBarDoctor(layout: layout)
    )
  }
}

public actor HermesBridgeMenuBarViewModel {
  private let environment: HermesBridgeMenuBarEnvironment
  private var refreshTask: Task<Void, Never>?
  public private(set) var state = HermesBridgeMenuBarState()

  public init(environment: HermesBridgeMenuBarEnvironment) {
    self.environment = environment
  }

  public func load() async {
    await refresh()
  }

  public func refresh() async {
    refreshTask?.cancel()
    let task = Task { await self.performRefresh() }
    refreshTask = task
    await task.value
  }

  public func cancelRefresh() {
    refreshTask?.cancel()
    refreshTask = nil
  }

  public func startService() async -> HermesBridgeMenuBarActionResult {
    let result = await environment.serviceManager.start()
    await refresh()
    state.lastActionMessage = result.safeMessage
    return result
  }

  public func restartService() async -> HermesBridgeMenuBarActionResult {
    let result = await environment.serviceManager.restart()
    await refresh()
    state.lastActionMessage = result.safeMessage
    return result
  }

  public func runDoctor() async -> HermesBridgeMenuBarActionResult {
    let result = await environment.doctor.runDoctor()
    state.lastActionMessage = result.safeMessage
    return result
  }

  private func performRefresh() async {
    if Task.isCancelled { return }
    let serviceStatus = await environment.serviceManager.status()
    var next = HermesBridgeMenuBarState(
      serviceStatus: menuStatus(for: serviceStatus),
      installed: serviceStatus != .notInstalled,
      running: [.starting, .runningHealthy, .runningUnhealthy].contains(serviceStatus),
      healthy: serviceStatus == .runningHealthy
    )
    guard next.running else {
      state = next
      return
    }
    do {
      let version = try await environment.xpcClient.protocolVersion()
      let capabilities = try await environment.xpcClient.capabilities()
      let compatible = version.version.major == HermesBridgeProtocolVersion.current.major
      let bindings =
        capabilities.capabilities.contains(.bindingDiscovery)
        ? (try? await environment.xpcClient.listEnabledBindings().bindings) ?? [] : []
      let requests = (try? await environment.requestLister.recentRequests()) ?? []
      next.protocolCompatible = compatible
      next.serviceStatus = compatible ? next.serviceStatus : .protocolIncompatible
      next.protocolVersion = version.version.description
      next.capabilities = capabilities.capabilities.map(\.rawValue).sorted()
      next.enabledBindingCount = bindings.count
      next.recentRequests = Array(requests.prefix(8))
      state = next
    } catch {
      next.serviceStatus = .unavailable
      state = next
    }
  }

  private func menuStatus(for status: HermesBridgeServiceStatus) -> HermesBridgeMenuBarServiceStatus
  {
    switch status {
    case .notInstalled:
      return .unavailable
    case .installedStopped, .rollbackAvailable, .upgradePending, .invalidInstallation:
      return .installedStopped
    case .starting:
      return .loading
    case .runningHealthy:
      return .runningHealthy
    case .runningUnhealthy:
      return .runningUnhealthy
    }
  }
}

public final class ProductionMenuBarServiceManager: HermesBridgeMenuBarServiceManaging,
  @unchecked Sendable
{
  private let manager: HermesBridgeServiceManager

  public init(layout: HermesBridgeInstallationLayout) {
    self.manager = HermesBridgeServiceManager(layout: layout)
  }

  public func status() async -> HermesBridgeServiceStatus {
    await manager.status()
  }

  public func start() async -> HermesBridgeMenuBarActionResult {
    do {
      try manager.bootstrap()
      return HermesBridgeMenuBarActionResult(succeeded: true, safeMessage: "start requested")
    } catch {
      return HermesBridgeMenuBarActionResult(succeeded: false, safeMessage: "start failed")
    }
  }

  public func restart() async -> HermesBridgeMenuBarActionResult {
    do {
      let health = try await manager.restart()
      return HermesBridgeMenuBarActionResult(
        succeeded: health.isHealthy,
        safeMessage: health.isHealthy ? "restart completed" : "restart unhealthy"
      )
    } catch {
      return HermesBridgeMenuBarActionResult(succeeded: false, safeMessage: "restart failed")
    }
  }
}

public actor ProductionMenuBarXPCClient: HermesBridgeMenuBarXPCClient {
  private let client: HermesBridgeXPCClient

  public init(layout: HermesBridgeInstallationLayout, timeout: TimeInterval = 5) {
    let name = try! HermesBridgeMachServiceName(layout.machService)
    self.client = HermesBridgeXPCClient(machServiceName: name, timeout: timeout)
  }

  public func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload {
    try await client.protocolVersion()
  }

  public func capabilities() async throws -> HermesBridgeCapabilitiesPayload {
    try await client.capabilities()
  }

  public func listEnabledBindings() async throws -> HermesBridgeBindingListPayload {
    try await client.listEnabledBindings()
  }

  public func close() async {
    await client.close()
  }
}

public struct ProductionMenuBarRequestLister: HermesBridgeMenuBarRequestListing {
  private let lister: HermesBridgeRequestListing

  public init(layout: HermesBridgeInstallationLayout) {
    self.lister = ProductionRequestLister(layout: layout)
  }

  public func recentRequests() async throws -> [HermesBridgeMenuBarRequestSummary] {
    try await lister.listRequests().prefix(8).map(HermesBridgeMenuBarRequestSummary.init(summary:))
  }
}

public struct ProductionMenuBarDoctor: HermesBridgeMenuBarDoctorRunning {
  private let layout: HermesBridgeInstallationLayout
  private let doctor = ProductionDoctorChecker()

  public init(layout: HermesBridgeInstallationLayout) {
    self.layout = layout
  }

  public func runDoctor() async -> HermesBridgeMenuBarActionResult {
    let report = await doctor.report(layout: layout, timeout: 5)
    return HermesBridgeMenuBarActionResult(
      succeeded: report.overallStatus != .fail,
      safeMessage: "doctor \(report.overallStatus.rawValue)"
    )
  }
}
