import Foundation

public final class HermesPolicyCenter: @unchecked Sendable {
  private let store: any HermesPolicyStoring
  private let evaluator: HermesPolicyEvaluator
  private let clock: @Sendable () -> Date
  private let lock = NSLock()

  public init(
    store: any HermesPolicyStoring = HermesPolicyStore(),
    evaluator: HermesPolicyEvaluator = HermesPolicyEvaluator(),
    clock: @escaping @Sendable () -> Date = Date.init
  ) {
    self.store = store
    self.evaluator = evaluator
    self.clock = clock
  }

  public func listPolicies() throws -> [HermesPolicyDefinition] {
    try lock.withLock {
      let stored = try store.loadPolicyDefinitions()
      if stored.isEmpty {
        let defaults = evaluator.defaultPolicies(now: clock())
        try store.savePolicyDefinitions(defaults)
        return sorted(defaults)
      }
      let safe = try stored.map { try evaluator.sanitized($0) }
      try store.savePolicyDefinitions(safe)
      return sorted(safe)
    }
  }

  public func savePolicy(_ policy: HermesPolicyDefinition) throws -> HermesPolicyDefinition {
    try lock.withLock {
      let safe = try evaluator.sanitized(policy)
      let current = try store.loadPolicyDefinitions().first { $0.id == safe.id }
      try store.upsert(safe)
      try store.recordPolicyChange(
        HermesPolicyAuditEvent(
          policyID: safe.id,
          oldValue: current?.value.description ?? "missing",
          newValue: safe.value.description,
          timestamp: safe.timestamp
        )
      )
      return safe
    }
  }

  public func evaluate(policyID: String) throws -> HermesPolicyEvaluationResult {
    try lock.withLock {
      let request = HermesPolicyEvaluationRequest(policyID: policyID, timestamp: clock())
      let policies = try store.loadPolicyDefinitions()
      let result = evaluator.evaluate(request, policies: policies, now: clock())
      if try store.loadPreferences().recordLocalEvaluationResults {
        try store.recordEvaluationResult(result)
      }
      return result
    }
  }

  public func loadEvaluationResults() throws -> [HermesPolicyEvaluationResult] {
    try store.loadEvaluationResults().sorted {
      if $0.timestamp == $1.timestamp { return $0.id.uuidString < $1.id.uuidString }
      return $0.timestamp > $1.timestamp
    }
  }

  public func loadAuditEvents() throws -> [HermesPolicyAuditEvent] {
    try store.loadPolicyAuditEvents().sorted {
      if $0.timestamp == $1.timestamp { return $0.id.uuidString < $1.id.uuidString }
      return $0.timestamp > $1.timestamp
    }
  }

  public func loadPreferences() throws -> HermesPolicyPreferences {
    try store.loadPreferences()
  }

  public func savePreferences(_ preferences: HermesPolicyPreferences) throws {
    try store.savePreferences(preferences)
  }

  public func clearStoredLocalPolicyData() throws {
    try store.clearStoredLocalPolicyData()
  }

  public var denyByDefault: Bool { evaluator.denyByDefault }
  public var appOwnsRuntime: Bool { evaluator.appOwnsRuntime }
  public var arbitraryActionAllowed: Bool { evaluator.arbitraryActionAllowed }
  public var automaticUploadAllowed: Bool { evaluator.automaticUploadAllowed }

  private func sorted(_ policies: [HermesPolicyDefinition]) -> [HermesPolicyDefinition] {
    policies.sorted {
      if $0.category == $1.category { return $0.id < $1.id }
      return categoryOrder($0.category) < categoryOrder($1.category)
    }
  }

  private func categoryOrder(_ category: HermesPolicyCategory) -> Int {
    HermesPolicyCategory.allCases.firstIndex(of: category) ?? Int.max
  }
}
