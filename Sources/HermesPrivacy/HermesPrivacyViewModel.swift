import Foundation
import SwiftUI

@MainActor
public final class HermesPrivacyViewModel: ObservableObject {
  @Published public private(set) var records: [HermesPrivacyConsentRecord] = []
  @Published public private(set) var auditEvents: [HermesPrivacyAuditEvent] = []
  @Published public private(set) var preferences: HermesPrivacyPreferences
  @Published public private(set) var safeMetadata: HermesPrivacySafeApplicationMetadata
  @Published public private(set) var lastErrorMessage: String?

  private let center: HermesPrivacyCenter
  private let openPolicyCenterAction: @MainActor () -> Void
  private let metadataProvider: @MainActor () -> HermesPrivacySafeApplicationMetadata

  public init(
    center: HermesPrivacyCenter = HermesPrivacyCenter(),
    openPolicyCenter: @escaping @MainActor () -> Void = {},
    metadataProvider: @escaping @MainActor () -> HermesPrivacySafeApplicationMetadata = {
      HermesPrivacySafeApplicationMetadata()
    }
  ) {
    self.center = center
    self.openPolicyCenterAction = openPolicyCenter
    self.metadataProvider = metadataProvider
    self.preferences = (try? center.loadPreferences()) ?? HermesPrivacyPreferences()
    self.safeMetadata = metadataProvider()
  }

  public func load() {
    do {
      records = try center.listConsentRecords()
      auditEvents = try center.loadAuditEvents()
      preferences = try center.loadPreferences()
      safeMetadata = metadataProvider()
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = HermesPrivacyRedactor.safeText(String(describing: error), limit: 180)
    }
  }

  public func setConsent(category: HermesPrivacyConsentCategory, isAllowed: Bool) {
    do {
      _ = try center.updateConsent(
        category: category,
        status: isAllowed ? .allowed : .denied,
        source: .privacyCenter
      )
      load()
    } catch {
      lastErrorMessage = Self.userFacing(error)
    }
  }

  public func setShowPrivacyReminders(_ show: Bool) {
    preferences.showPrivacyReminders = show
    savePreferences()
  }

  public func setRetainLocalHistory(_ retain: Bool) {
    preferences.retainLocalHistory = retain
    do {
      try center.savePreferences(preferences)
      _ = try center.updateConsent(
        category: .localHistoryRetention,
        status: retain ? .allowed : .denied,
        source: .privacyCenter
      )
      load()
    } catch {
      lastErrorMessage = Self.userFacing(error)
    }
  }

  public func clearStoredLocalData() {
    do {
      try center.clearStoredLocalData()
      load()
    } catch {
      lastErrorMessage = Self.userFacing(error)
    }
  }

  public func openPolicyCenter() {
    openPolicyCenterAction()
  }

  public var policySummary: String {
    [
      "explicit consent required",
      "deny by default",
      "no silent enable",
      "sanitized audit only",
      "app owns runtime: no",
    ].joined(separator: " | ")
  }

  public func isAllowed(_ category: HermesPrivacyConsentCategory) -> Bool {
    records.first { $0.category == category }?.status == .allowed
  }

  private func savePreferences() {
    do {
      try center.savePreferences(preferences)
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = Self.userFacing(error)
    }
  }

  private static func userFacing(_ error: Error) -> String {
    switch error {
    case HermesPrivacyValidationError.sensitiveCategoryRejected:
      return "Sensitive privacy category was rejected."
    case HermesPrivacyValidationError.unsupportedCategory:
      return "Privacy category is not supported."
    case HermesPrivacyValidationError.consentRecordNotFound:
      return "Consent record was not found."
    default:
      return HermesPrivacyRedactor.safeText(String(describing: error), limit: 180)
    }
  }
}
