import Foundation

public struct HermesOperationsCenterInputs: Sendable {
  public var runtimeOperations: @Sendable () async -> HermesRuntimeOperationsProviderSnapshot
  public var eventOperations: @Sendable () async -> HermesEventOperationsProviderSnapshot
  public var releaseOperations: @Sendable () async -> HermesReleaseOperationsProviderSnapshot
  public var governanceOperations: @Sendable () async -> HermesGovernanceOperationsProviderSnapshot

  public init(
    runtimeOperations: @escaping @Sendable () async -> HermesRuntimeOperationsProviderSnapshot,
    eventOperations: @escaping @Sendable () async -> HermesEventOperationsProviderSnapshot,
    releaseOperations: @escaping @Sendable () async -> HermesReleaseOperationsProviderSnapshot,
    governanceOperations: @escaping @Sendable () async -> HermesGovernanceOperationsProviderSnapshot
  ) {
    self.runtimeOperations = runtimeOperations
    self.eventOperations = eventOperations
    self.releaseOperations = releaseOperations
    self.governanceOperations = governanceOperations
  }
}

public final class HermesOperationsCenter: @unchecked Sendable {
  private let inputs: HermesOperationsCenterInputs

  public init(inputs: HermesOperationsCenterInputs) {
    self.inputs = inputs
  }

  public func snapshot() async -> HermesOperationsSnapshot {
    let runtimeProvider = await inputs.runtimeOperations()
    let eventProvider = await inputs.eventOperations()
    let releaseProvider = await inputs.releaseOperations()
    let governanceProvider = await inputs.governanceOperations()
    return HermesOperationsSnapshot(
      runtime: HermesRuntimeOperationsSummary(provider: runtimeProvider),
      events: HermesEventOperationsSummary(provider: eventProvider),
      release: HermesReleaseOperationsSummary(provider: releaseProvider),
      governance: HermesGovernanceOperationsSummary(provider: governanceProvider),
      readOnly: true,
      appOwnsRuntime: false,
      processExecutionAvailable: false,
      shellAvailable: false,
      uploadAvailable: false,
      filesystemScanAvailable: false,
      sensitiveDataPersistenceAvailable: false
    )
  }

  public var readOnly: Bool { true }
  public var appOwnsRuntime: Bool { false }
  public var processExecutionAvailable: Bool { false }
  public var shellAvailable: Bool { false }
  public var uploadAvailable: Bool { false }
  public var filesystemScanAvailable: Bool { false }
  public var sensitiveDataPersistenceAvailable: Bool { false }
}
