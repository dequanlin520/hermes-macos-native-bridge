import Foundation

public enum HermesPolicyCategory: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case runtimeOperationRestrictions
  case updatePolicy
  case notificationPolicy
  case retentionPolicy
  case privacyPolicy
  case featureAvailabilityPolicy
}

public enum HermesPolicyDecision: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case allow
  case deny
  case requireConfirmation
}

public enum HermesPolicyValue: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
  case decision(HermesPolicyDecision)
  case boolean(Bool)
  case integer(Int)
  case text(String)

  private enum CodingKeys: String, CodingKey {
    case kind
    case value
  }

  private enum Kind: String, Codable {
    case decision
    case boolean
    case integer
    case text
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .decision:
      self = .decision(try container.decode(HermesPolicyDecision.self, forKey: .value))
    case .boolean:
      self = .boolean(try container.decode(Bool.self, forKey: .value))
    case .integer:
      self = .integer(try container.decode(Int.self, forKey: .value))
    case .text:
      self = .text(HermesPolicyRedactor.safeText(try container.decode(String.self, forKey: .value)))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .decision(let decision):
      try container.encode(Kind.decision, forKey: .kind)
      try container.encode(decision, forKey: .value)
    case .boolean(let value):
      try container.encode(Kind.boolean, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .integer(let value):
      try container.encode(Kind.integer, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .text(let value):
      try container.encode(Kind.text, forKey: .kind)
      try container.encode(HermesPolicyRedactor.safeText(value), forKey: .value)
    }
  }

  public var description: String {
    switch self {
    case .decision(let decision): return decision.rawValue
    case .boolean(let value): return value ? "true" : "false"
    case .integer(let value): return String(value)
    case .text(let value): return HermesPolicyRedactor.safeText(value, limit: 120)
    }
  }
}

public enum HermesPolicySource: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case defaultPolicy
  case enterprisePolicyCenter
  case settings
  case diagnostics
  case privacyCenter
  case managedProfile
}

public struct HermesPolicyDefinition: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public var name: String
  public var category: HermesPolicyCategory
  public var value: HermesPolicyValue
  public var source: HermesPolicySource
  public var version: String
  public var timestamp: Date

  public init(
    id: String,
    name: String,
    category: HermesPolicyCategory,
    value: HermesPolicyValue,
    source: HermesPolicySource = .enterprisePolicyCenter,
    version: String = "1",
    timestamp: Date = Date()
  ) {
    self.id = HermesPolicyRedactor.safeToken(id, limit: 120)
    self.name = HermesPolicyRedactor.safeText(name, limit: 160)
    self.category = category
    self.value = HermesPolicyRedactor.safeValue(value)
    self.source = source
    self.version = HermesPolicyRedactor.safeToken(version, limit: 40)
    self.timestamp = timestamp
  }
}

public struct HermesPolicyEvaluationRequest: Codable, Equatable, Sendable {
  public let policyID: String
  public let timestamp: Date

  public init(policyID: String, timestamp: Date = Date()) {
    self.policyID = HermesPolicyRedactor.safeToken(policyID, limit: 120)
    self.timestamp = timestamp
  }
}

public struct HermesPolicyEvaluationResult: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let policyID: String
  public let decision: HermesPolicyDecision
  public let source: HermesPolicySource
  public let timestamp: Date
  public let reason: String

  public init(
    id: UUID = UUID(),
    policyID: String,
    decision: HermesPolicyDecision,
    source: HermesPolicySource = .defaultPolicy,
    timestamp: Date = Date(),
    reason: String = ""
  ) {
    self.id = id
    self.policyID = HermesPolicyRedactor.safeToken(policyID, limit: 120)
    self.decision = decision
    self.source = source
    self.timestamp = timestamp
    self.reason = HermesPolicyRedactor.safeText(reason, limit: 180)
  }
}

public struct HermesPolicyPreferences: Codable, Equatable, Sendable {
  public var showManagedPolicyMetadata: Bool
  public var recordLocalEvaluationResults: Bool

  public init(
    showManagedPolicyMetadata: Bool = true,
    recordLocalEvaluationResults: Bool = true
  ) {
    self.showManagedPolicyMetadata = showManagedPolicyMetadata
    self.recordLocalEvaluationResults = recordLocalEvaluationResults
  }
}

public struct HermesPolicyAuditEvent: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let policyID: String
  public let oldValue: String
  public let newValue: String
  public let timestamp: Date

  public init(
    id: UUID = UUID(),
    policyID: String,
    oldValue: String,
    newValue: String,
    timestamp: Date = Date()
  ) {
    self.id = id
    self.policyID = HermesPolicyRedactor.safeToken(policyID, limit: 120)
    self.oldValue = HermesPolicyRedactor.safeText(oldValue, limit: 160)
    self.newValue = HermesPolicyRedactor.safeText(newValue, limit: 160)
    self.timestamp = timestamp
  }
}

public enum HermesPolicyValidationError: Error, Equatable, Sendable {
  case unsupportedPolicyID(String)
  case sensitivePolicyMetadataRejected(String)
  case policyNotFound
}

public enum HermesPolicyRedactor {
  public static func safeValue(_ value: HermesPolicyValue) -> HermesPolicyValue {
    switch value {
    case .text(let text): return .text(safeText(text))
    default: return value
    }
  }

  public static func safeText(_ value: String, limit: Int = 320) -> String {
    var output = String(value.prefix(limit))
    let replacements: [(String, String)] = [
      (#"(?i)\b(token|password|api[_ -]?key|credential|secret|private[_ -]?key)\s*[:=]\s*[^,\s]+"#, "$1=<redacted>"),
      (#"(?i)\bbearer\s+[A-Za-z0-9._~+/\-=]+"#, "bearer <redacted>"),
      (#"(?is)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----"#, "<redacted-private-key>"),
      (#"/(?:Applications|Users|Volumes|System|Library|private|var|tmp|usr|bin|sbin|opt)/[^\s,"')]+"#, "<redacted-path>"),
      (#"(?i)\bpid(?:\s*[=:]\s*|\s+)[0-9]+\b"#, "pid=<redacted>"),
      (#"(?i)\bprocess id(?:\s*[=:]\s*|\s+)[0-9]+\b"#, "process id=<redacted>"),
    ]
    for (pattern, replacement) in replacements {
      output = output.replacingOccurrences(
        of: pattern,
        with: replacement,
        options: [.regularExpression, .caseInsensitive]
      )
    }
    return String(output.prefix(limit))
  }

  public static func safeToken(_ value: String, limit: Int = 80) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(limit))
  }

  static func normalized(_ value: String) -> String {
    value.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
  }
}
