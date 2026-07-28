import Foundation

public struct HermesAnalyticsCenterInputs: Sendable {
  public var runtimeAnalytics: @Sendable () async -> HermesRuntimeAnalyticsProviderSnapshot
  public var operationsAnalytics: @Sendable () async -> HermesOperationsAnalyticsProviderSnapshot
  public var governanceAnalytics: @Sendable () async -> HermesGovernanceAnalyticsProviderSnapshot

  public init(
    runtimeAnalytics: @escaping @Sendable () async -> HermesRuntimeAnalyticsProviderSnapshot,
    operationsAnalytics: @escaping @Sendable () async -> HermesOperationsAnalyticsProviderSnapshot,
    governanceAnalytics: @escaping @Sendable () async -> HermesGovernanceAnalyticsProviderSnapshot
  ) {
    self.runtimeAnalytics = runtimeAnalytics
    self.operationsAnalytics = operationsAnalytics
    self.governanceAnalytics = governanceAnalytics
  }
}

public final class HermesAnalyticsCenter: @unchecked Sendable {
  private let inputs: HermesAnalyticsCenterInputs

  public init(inputs: HermesAnalyticsCenterInputs) {
    self.inputs = inputs
  }

  public func snapshot() async -> HermesAnalyticsSnapshot {
    let runtimeProvider = await inputs.runtimeAnalytics()
    let operationsProvider = await inputs.operationsAnalytics()
    let governanceProvider = await inputs.governanceAnalytics()
    return HermesAnalyticsSnapshot(
      runtime: HermesRuntimeAnalyticsSummary(provider: runtimeProvider),
      operations: HermesOperationsAnalyticsSummary(provider: operationsProvider),
      governance: HermesGovernanceAnalyticsSummary(provider: governanceProvider),
      readOnly: true,
      appOwnsRuntime: false,
      processExecutionAvailable: false,
      shellAvailable: false,
      uploadAvailable: false,
      filesystemScanAvailable: false
    )
  }

  public var readOnly: Bool { true }
  public var appOwnsRuntime: Bool { false }
  public var processExecutionAvailable: Bool { false }
  public var shellAvailable: Bool { false }
  public var uploadAvailable: Bool { false }
  public var filesystemScanAvailable: Bool { false }
}
