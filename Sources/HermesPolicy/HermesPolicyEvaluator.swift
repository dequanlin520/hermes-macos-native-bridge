import Foundation

public struct HermesPolicyEvaluator: Equatable, Sendable {
  public let allowedCategories: Set<HermesPolicyCategory>
  public let sensitivePolicyMarkers: Set<String>

  public init(
    allowedCategories: Set<HermesPolicyCategory> = Set(HermesPolicyCategory.allCases),
    sensitivePolicyMarkers: Set<String> = [
      "credential", "credentials", "identity", "keychain", "password", "privatepath",
      "private-path", "secret", "token", "runtimeobject", "process", "pid",
    ]
  ) {
    self.allowedCategories = allowedCategories
    self.sensitivePolicyMarkers = Set(sensitivePolicyMarkers.map {
      HermesPolicyRedactor.normalized($0)
    })
  }

  public func validate(_ policy: HermesPolicyDefinition) throws {
    guard allowedCategories.contains(policy.category) else {
      throw HermesPolicyValidationError.unsupportedPolicyID(policy.id)
    }
    let searchable = [
      policy.id,
      policy.name,
      policy.version,
      policy.value.description,
    ].joined(separator: " ")
    let normalized = HermesPolicyRedactor.normalized(searchable)
    if sensitivePolicyMarkers.contains(where: { normalized.contains($0) }) {
      throw HermesPolicyValidationError.sensitivePolicyMetadataRejected(
        HermesPolicyRedactor.safeText(searchable, limit: 160)
      )
    }
  }

  public func sanitized(_ policy: HermesPolicyDefinition) throws -> HermesPolicyDefinition {
    try validate(policy)
    return HermesPolicyDefinition(
      id: policy.id,
      name: policy.name,
      category: policy.category,
      value: policy.value,
      source: policy.source,
      version: policy.version,
      timestamp: policy.timestamp
    )
  }

  public func evaluate(
    _ request: HermesPolicyEvaluationRequest,
    policies: [HermesPolicyDefinition],
    now: Date = Date()
  ) -> HermesPolicyEvaluationResult {
    guard let policy = policies.first(where: { $0.id == request.policyID }) else {
      return HermesPolicyEvaluationResult(
        policyID: request.policyID,
        decision: .deny,
        source: .defaultPolicy,
        timestamp: now,
        reason: "unknown policy"
      )
    }

    let decision: HermesPolicyDecision
    switch policy.value {
    case .decision(let value):
      decision = value
    case .boolean(let value):
      decision = value ? .allow : .deny
    case .integer, .text:
      decision = .deny
    }

    return HermesPolicyEvaluationResult(
      policyID: policy.id,
      decision: decision,
      source: policy.source,
      timestamp: now,
      reason: "local policy metadata evaluation"
    )
  }

  public func defaultPolicies(now: Date = Date()) -> [HermesPolicyDefinition] {
    HermesPolicyCategory.allCases.map { category in
      HermesPolicyDefinition(
        id: "hermes.policy.\(category.rawValue)",
        name: defaultName(for: category),
        category: category,
        value: .decision(.deny),
        source: .defaultPolicy,
        version: "1",
        timestamp: now
      )
    }
  }

  public var denyByDefault: Bool { true }
  public var appOwnsRuntime: Bool { false }
  public var arbitraryActionAllowed: Bool { false }
  public var automaticUploadAllowed: Bool { false }

  private func defaultName(for category: HermesPolicyCategory) -> String {
    switch category {
    case .runtimeOperationRestrictions: return "Runtime Operation Restrictions"
    case .updatePolicy: return "Update Policy"
    case .notificationPolicy: return "Notification Policy"
    case .retentionPolicy: return "Retention Policy"
    case .privacyPolicy: return "Privacy Policy"
    case .featureAvailabilityPolicy: return "Feature Availability Policy"
    }
  }
}
