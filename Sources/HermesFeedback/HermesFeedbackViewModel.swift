import Foundation
import SwiftUI

@MainActor
public final class HermesFeedbackViewModel: ObservableObject {
  @Published public private(set) var records: [HermesFeedbackRecord] = []
  @Published public var selectedCategory: HermesFeedbackCategory
  @Published public var title: String = ""
  @Published public var description: String = ""
  @Published public var severity: HermesFeedbackSeverity
  @Published public var relatedFeature: String
  @Published public private(set) var lastErrorMessage: String?
  @Published public private(set) var lastCreatedID: UUID?

  private let center: HermesFeedbackCenter
  private let contextProvider: @MainActor () -> HermesFeedbackSafeRuntimeContext?
  private var preferences: HermesFeedbackPreferences

  public init(
    center: HermesFeedbackCenter = HermesFeedbackCenter(),
    contextProvider: @escaping @MainActor () -> HermesFeedbackSafeRuntimeContext? = { nil }
  ) {
    self.center = center
    self.contextProvider = contextProvider
    self.preferences = (try? center.loadPreferences()) ?? HermesFeedbackPreferences()
    self.selectedCategory = preferences.defaultCategory
    self.severity = preferences.defaultSeverity
    self.relatedFeature = ""
  }

  public func load() {
    do {
      records = try center.listFeedback()
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = HermesFeedbackRedactor.safeText(String(describing: error), limit: 180)
    }
  }

  public func createDraft() {
    do {
      let context = preferences.includeSafeRuntimeContext ? contextProvider() : nil
      let record = try center.createFeedback(
        category: selectedCategory,
        title: title,
        description: description,
        severity: severity,
        relatedFeature: relatedFeature.isEmpty ? nil : relatedFeature,
        safeRuntimeContext: context
      )
      lastCreatedID = record.id
      title = ""
      description = ""
      relatedFeature = ""
      preferences.defaultCategory = selectedCategory
      preferences.defaultSeverity = severity
      try center.savePreferences(preferences)
      load()
    } catch {
      lastErrorMessage = Self.userFacing(error)
    }
  }

  public func transition(_ record: HermesFeedbackRecord, to status: HermesFeedbackStatus) {
    do {
      _ = try center.transition(id: record.id, to: status)
      load()
    } catch {
      lastErrorMessage = Self.userFacing(error)
    }
  }

  public func setIncludeSafeRuntimeContext(_ include: Bool) {
    preferences.includeSafeRuntimeContext = include
    do {
      try center.savePreferences(preferences)
      lastErrorMessage = nil
    } catch {
      lastErrorMessage = Self.userFacing(error)
    }
  }

  public var includeSafeRuntimeContext: Bool {
    preferences.includeSafeRuntimeContext
  }

  private static func userFacing(_ error: Error) -> String {
    switch error {
    case HermesFeedbackValidationError.descriptionTooShort(let minimum):
      return "Description must be at least \(minimum) characters."
    case HermesFeedbackValidationError.duplicateFeedback:
      return "A matching feedback item already exists."
    case HermesFeedbackValidationError.unsupportedCategory:
      return "Feedback category is not supported."
    case HermesFeedbackValidationError.invalidLifecycleTransition(let from, let to):
      return "Cannot move feedback from \(from.rawValue) to \(to.rawValue)."
    case HermesFeedbackValidationError.feedbackNotFound:
      return "Feedback item was not found."
    default:
      return HermesFeedbackRedactor.safeText(String(describing: error), limit: 180)
    }
  }
}
