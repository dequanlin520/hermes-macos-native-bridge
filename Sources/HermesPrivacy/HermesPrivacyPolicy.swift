import Foundation

public struct HermesPrivacyPolicy: Equatable, Sendable {
  public let allowedCategories: Set<HermesPrivacyConsentCategory>
  public let sensitiveCategoryMarkers: Set<String>

  public init(
    allowedCategories: Set<HermesPrivacyConsentCategory> = Set(HermesPrivacyConsentCategory.allCases),
    sensitiveCategoryMarkers: Set<String> = [
      "credential", "credentials", "identity", "keychain", "password", "privatepath",
      "private-path", "secret", "token", "runtimeobject", "process", "pid",
    ]
  ) {
    self.allowedCategories = allowedCategories
    self.sensitiveCategoryMarkers = Set(sensitiveCategoryMarkers.map {
      Self.normalized($0)
    })
  }

  public func validate(category: HermesPrivacyConsentCategory) throws {
    guard allowedCategories.contains(category) else {
      throw HermesPrivacyValidationError.unsupportedCategory(category.rawValue)
    }
  }

  public func category(from rawValue: String) throws -> HermesPrivacyConsentCategory {
    let normalized = Self.normalized(rawValue)
    if sensitiveCategoryMarkers.contains(where: { normalized.contains($0) }) {
      throw HermesPrivacyValidationError.sensitiveCategoryRejected(
        HermesPrivacyRedactor.safeText(rawValue, limit: 120)
      )
    }
    guard let category = HermesPrivacyConsentCategory(rawValue: rawValue) else {
      throw HermesPrivacyValidationError.unsupportedCategory(
        HermesPrivacyRedactor.safeText(rawValue, limit: 120)
      )
    }
    try validate(category: category)
    return category
  }

  public func sanitized(_ record: HermesPrivacyConsentRecord) throws
    -> HermesPrivacyConsentRecord
  {
    try validate(category: record.category)
    return HermesPrivacyConsentRecord(
      id: record.id,
      category: record.category,
      status: record.status == .unknown ? .denied : record.status,
      updatedAt: record.updatedAt,
      source: record.source
    )
  }

  public func defaultConsentRecords(now: Date = Date()) -> [HermesPrivacyConsentRecord] {
    HermesPrivacyConsentCategory.allCases.map {
      HermesPrivacyConsentRecord(
        category: $0,
        status: .denied,
        updatedAt: now,
        source: .defaultPolicy
      )
    }
  }

  public var explicitConsentRequired: Bool { true }
  public var denyByDefault: Bool { true }
  public var automaticUploadAllowed: Bool { false }
  public var arbitraryActionAllowed: Bool { false }
  public var appOwnsRuntime: Bool { false }

  private static func normalized(_ value: String) -> String {
    value
      .lowercased()
      .filter { $0.isLetter || $0.isNumber || $0 == "-" }
  }
}
