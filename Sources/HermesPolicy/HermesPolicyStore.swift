import Foundation

public protocol HermesPolicyAuditRecording: Sendable {
  func recordPolicyChange(_ event: HermesPolicyAuditEvent) throws
  func loadPolicyAuditEvents() throws -> [HermesPolicyAuditEvent]
}

public protocol HermesPolicyStoring: HermesPolicyAuditRecording {
  func loadPolicyDefinitions() throws -> [HermesPolicyDefinition]
  func savePolicyDefinitions(_ policies: [HermesPolicyDefinition]) throws
  func upsert(_ policy: HermesPolicyDefinition) throws
  func loadEvaluationResults() throws -> [HermesPolicyEvaluationResult]
  func recordEvaluationResult(_ result: HermesPolicyEvaluationResult) throws
  func loadPreferences() throws -> HermesPolicyPreferences
  func savePreferences(_ preferences: HermesPolicyPreferences) throws
  func clearStoredLocalPolicyData() throws
}

public final class HermesPolicyStore: HermesPolicyStoring, @unchecked Sendable {
  public enum Namespace {
    public static let suiteName = "com.hermes.policy.v1"
  }

  private enum Keys {
    static let prefix = "com.hermes.policy.v1."
    static let policyDefinitions = prefix + "policyDefinitions"
    static let evaluationResults = prefix + "evaluationResults"
    static let preferences = prefix + "preferences"
    static let auditEvents = prefix + "auditEvents"
  }

  private let userDefaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  private let lock = NSLock()

  public init(userDefaults: UserDefaults? = nil) {
    self.userDefaults = userDefaults ?? UserDefaults(suiteName: Namespace.suiteName) ?? .standard
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  public func loadPolicyDefinitions() throws -> [HermesPolicyDefinition] {
    try lock.withLock {
      try loadPolicyDefinitionsUnlocked()
    }
  }

  public func savePolicyDefinitions(_ policies: [HermesPolicyDefinition]) throws {
    try lock.withLock {
      let data = try encoder.encode(policies.map(HermesPolicyStore.sanitizedPolicy))
      userDefaults.set(data, forKey: Keys.policyDefinitions)
    }
  }

  public func upsert(_ policy: HermesPolicyDefinition) throws {
    try lock.withLock {
      var policies = try loadPolicyDefinitionsUnlocked()
      policies.removeAll { $0.id == policy.id }
      policies.append(HermesPolicyStore.sanitizedPolicy(policy))
      let data = try encoder.encode(policies)
      userDefaults.set(data, forKey: Keys.policyDefinitions)
    }
  }

  public func loadEvaluationResults() throws -> [HermesPolicyEvaluationResult] {
    try lock.withLock {
      guard let data = userDefaults.data(forKey: Keys.evaluationResults) else { return [] }
      return try decoder.decode([HermesPolicyEvaluationResult].self, from: data)
    }
  }

  public func recordEvaluationResult(_ result: HermesPolicyEvaluationResult) throws {
    try lock.withLock {
      var results = try loadEvaluationResultsUnlocked()
      results.insert(result, at: 0)
      let data = try encoder.encode(Array(results.prefix(100)))
      userDefaults.set(data, forKey: Keys.evaluationResults)
    }
  }

  public func loadPreferences() throws -> HermesPolicyPreferences {
    try lock.withLock {
      guard let data = userDefaults.data(forKey: Keys.preferences) else {
        return HermesPolicyPreferences()
      }
      return try decoder.decode(HermesPolicyPreferences.self, from: data)
    }
  }

  public func savePreferences(_ preferences: HermesPolicyPreferences) throws {
    try lock.withLock {
      let data = try encoder.encode(preferences)
      userDefaults.set(data, forKey: Keys.preferences)
    }
  }

  public func recordPolicyChange(_ event: HermesPolicyAuditEvent) throws {
    try lock.withLock {
      var events = try loadPolicyAuditEventsUnlocked()
      events.insert(event, at: 0)
      let data = try encoder.encode(Array(events.prefix(100)))
      userDefaults.set(data, forKey: Keys.auditEvents)
    }
  }

  public func loadPolicyAuditEvents() throws -> [HermesPolicyAuditEvent] {
    try lock.withLock {
      try loadPolicyAuditEventsUnlocked()
    }
  }

  public func clearStoredLocalPolicyData() throws {
    lock.withLock {
      userDefaults.removeObject(forKey: Keys.policyDefinitions)
      userDefaults.removeObject(forKey: Keys.evaluationResults)
      userDefaults.removeObject(forKey: Keys.preferences)
      userDefaults.removeObject(forKey: Keys.auditEvents)
    }
  }

  private func loadPolicyDefinitionsUnlocked() throws -> [HermesPolicyDefinition] {
    guard let data = userDefaults.data(forKey: Keys.policyDefinitions) else { return [] }
    return try decoder.decode([HermesPolicyDefinition].self, from: data)
  }

  private func loadEvaluationResultsUnlocked() throws -> [HermesPolicyEvaluationResult] {
    guard let data = userDefaults.data(forKey: Keys.evaluationResults) else { return [] }
    return try decoder.decode([HermesPolicyEvaluationResult].self, from: data)
  }

  private func loadPolicyAuditEventsUnlocked() throws -> [HermesPolicyAuditEvent] {
    guard let data = userDefaults.data(forKey: Keys.auditEvents) else { return [] }
    return try decoder.decode([HermesPolicyAuditEvent].self, from: data)
  }

  private static func sanitizedPolicy(_ policy: HermesPolicyDefinition) -> HermesPolicyDefinition {
    HermesPolicyDefinition(
      id: policy.id,
      name: policy.name,
      category: policy.category,
      value: policy.value,
      source: policy.source,
      version: policy.version,
      timestamp: policy.timestamp
    )
  }
}
