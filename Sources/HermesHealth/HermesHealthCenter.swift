import Foundation

public struct HermesHealthCenterInputs: Sendable {
  public var systemHealth: @Sendable () async -> HermesHealthSystemProviderSnapshot
  public var runtimeHealth: @Sendable () async -> HermesHealthRuntimeProviderSnapshot
  public var operationalHealth: @Sendable () async -> HermesHealthOperationalProviderSnapshot
  public var complianceHealth: @Sendable () async -> HermesHealthComplianceProviderSnapshot

  public init(
    systemHealth: @escaping @Sendable () async -> HermesHealthSystemProviderSnapshot,
    runtimeHealth: @escaping @Sendable () async -> HermesHealthRuntimeProviderSnapshot,
    operationalHealth: @escaping @Sendable () async -> HermesHealthOperationalProviderSnapshot,
    complianceHealth: @escaping @Sendable () async -> HermesHealthComplianceProviderSnapshot
  ) {
    self.systemHealth = systemHealth
    self.runtimeHealth = runtimeHealth
    self.operationalHealth = operationalHealth
    self.complianceHealth = complianceHealth
  }
}

public final class HermesHealthCenter: @unchecked Sendable {
  private let inputs: HermesHealthCenterInputs

  public init(inputs: HermesHealthCenterInputs) {
    self.inputs = inputs
  }

  public func snapshot() async -> HermesHealthSnapshot {
    let systemProvider = await inputs.systemHealth()
    let runtimeProvider = await inputs.runtimeHealth()
    let operationalProvider = await inputs.operationalHealth()
    let complianceProvider = await inputs.complianceHealth()
    let system = HermesHealthSystemSummary(provider: systemProvider)
    let runtime = HermesHealthRuntimeSummary(provider: runtimeProvider)
    let operational = HermesHealthOperationalSummary(provider: operationalProvider)
    let compliance = HermesHealthComplianceSummary(provider: complianceProvider)
    return HermesHealthSnapshot(
      system: system,
      runtime: runtime,
      operational: operational,
      compliance: compliance,
      readOnly: true,
      appOwnsRuntime: false,
      automaticRepairAvailable: false,
      processExecutionAvailable: false,
      shellAvailable: false,
      uploadAvailable: false,
      filesystemScanAvailable: false
    )
  }

  public var readOnly: Bool { true }
  public var appOwnsRuntime: Bool { false }
  public var automaticRepairAvailable: Bool { false }
  public var processExecutionAvailable: Bool { false }
  public var shellAvailable: Bool { false }
  public var uploadAvailable: Bool { false }
  public var filesystemScanAvailable: Bool { false }
}
