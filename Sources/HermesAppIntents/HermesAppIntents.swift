import AppIntents
import Foundation

public struct SubmitHermesRequestIntent: AppIntent {
  public static let title: LocalizedStringResource = "Submit Hermes Request"
  public static let description = IntentDescription(
    "Submits a bounded Prompt to an enabled Hermes binding and returns a Request ID.")
  public static let openAppWhenRun = false

  @Parameter(title: "Binding")
  public var binding: HermesAppIntentBindingEntity

  @Parameter(title: "Prompt")
  public var prompt: String

  public init() {}

  public init(binding: HermesAppIntentBindingEntity, prompt: String) {
    self.binding = binding
    self.prompt = prompt
  }

  public func perform() async throws -> some IntentResult & ProvidesDialog
    & ReturnsValue<HermesAppIntentRequestEntity>
  {
    let request = try await Self.operation(bindingID: binding.id, prompt: prompt)
    return .result(
      value: request,
      dialog: IntentDialog("Hermes request submitted. Request ID \(request.id).")
    )
  }

  public static func operation(bindingID: String, prompt: String) async throws
    -> HermesAppIntentRequestEntity
  {
    let client = try await HermesAppIntentDependencyProvider.shared.client()
    return try await HermesAppIntentOperations(client: client).submit(
      bindingID: bindingID,
      prompt: prompt
    )
  }
}

public struct CheckHermesRequestStatusIntent: AppIntent {
  public static let title: LocalizedStringResource = "Check Hermes Request Status"
  public static let description = IntentDescription(
    "Checks a Hermes Request ID and returns a redacted lifecycle summary.")
  public static let openAppWhenRun = false

  @Parameter(title: "Request ID")
  public var requestID: String

  public init() {}

  public init(requestID: String) {
    self.requestID = requestID
  }

  public func perform() async throws -> some IntentResult & ProvidesDialog
    & ReturnsValue<HermesAppIntentRequestEntity>
  {
    let request = try await Self.operation(requestID: requestID)
    return .result(
      value: request,
      dialog: IntentDialog("Hermes request \(request.id) is \(request.lifecycleState).")
    )
  }

  public static func operation(requestID: String) async throws -> HermesAppIntentRequestEntity {
    let client = try await HermesAppIntentDependencyProvider.shared.client()
    return try await HermesAppIntentOperations(client: client).status(requestID: requestID)
  }
}

public struct CancelHermesRequestIntent: AppIntent {
  public static let title: LocalizedStringResource = "Cancel Hermes Request"
  public static let description = IntentDescription(
    "Requests cancellation for a Hermes Request ID and returns the updated safe state.")
  public static let openAppWhenRun = false

  @Parameter(title: "Request ID")
  public var requestID: String

  public init() {}

  public init(requestID: String) {
    self.requestID = requestID
  }

  public func perform() async throws -> some IntentResult & ProvidesDialog
    & ReturnsValue<HermesAppIntentRequestEntity>
  {
    let request = try await Self.operation(requestID: requestID)
    return .result(
      value: request,
      dialog: IntentDialog("Hermes request \(request.id) is \(request.lifecycleState).")
    )
  }

  public static func operation(requestID: String) async throws -> HermesAppIntentRequestEntity {
    let client = try await HermesAppIntentDependencyProvider.shared.client()
    return try await HermesAppIntentOperations(client: client).cancel(requestID: requestID)
  }
}

public struct RespondToHermesApprovalIntent: AppIntent {
  public static let title: LocalizedStringResource = "Respond to Hermes Approval"
  public static let description = IntentDescription(
    "Sends an allow or deny decision for a Hermes approval request.")
  public static let openAppWhenRun = false

  @Parameter(title: "Request ID")
  public var requestID: String

  @Parameter(title: "Decision")
  public var decision: HermesAppIntentApprovalDecision

  public init() {}

  public init(requestID: String, decision: HermesAppIntentApprovalDecision) {
    self.requestID = requestID
    self.decision = decision
  }

  public func perform() async throws -> some IntentResult & ProvidesDialog
    & ReturnsValue<HermesAppIntentRequestEntity>
  {
    let request = try await Self.operation(requestID: requestID, decision: decision)
    return .result(
      value: request,
      dialog: IntentDialog("Hermes approval response recorded for request \(request.id).")
    )
  }

  public static func operation(
    requestID: String,
    decision: HermesAppIntentApprovalDecision
  ) async throws -> HermesAppIntentRequestEntity {
    let client = try await HermesAppIntentDependencyProvider.shared.client()
    return try await HermesAppIntentOperations(client: client).respondToApproval(
      requestID: requestID,
      decision: decision
    )
  }
}

public struct CheckHermesBridgeHealthIntent: AppIntent {
  public static let title: LocalizedStringResource = "Check Hermes Bridge Health"
  public static let description = IntentDescription(
    "Checks whether Hermes Bridge XPC is available and protocol compatible.")
  public static let openAppWhenRun = false

  public init() {}

  public func perform() async throws -> some IntentResult & ProvidesDialog
    & ReturnsValue<String>
  {
    let health = try await Self.operation()
    let availability = health.available ? "available" : "unavailable"
    let compatibility = health.compatible ? "compatible" : "incompatible"
    let version = health.protocolVersion ?? "unknown"
    return .result(
      value: "\(availability), \(compatibility), protocol \(version)",
      dialog: IntentDialog("Hermes Bridge is \(availability) and \(compatibility).")
    )
  }

  public static func operation() async throws -> HermesAppIntentHealthStatus {
    let client = try await HermesAppIntentDependencyProvider.shared.client()
    return try await HermesAppIntentOperations(client: client).health()
  }
}

public struct HermesAppShortcutsProvider: AppShortcutsProvider {
  public static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: SubmitHermesRequestIntent(),
      phrases: [
        "Submit a Hermes request in \(.applicationName)",
        "Ask Hermes in \(.applicationName)",
      ],
      shortTitle: "Submit Request",
      systemImageName: "paperplane"
    )
    AppShortcut(
      intent: CheckHermesRequestStatusIntent(),
      phrases: [
        "Check Hermes request status in \(.applicationName)",
        "Get Hermes request status in \(.applicationName)",
      ],
      shortTitle: "Request Status",
      systemImageName: "list.bullet.clipboard"
    )
    AppShortcut(
      intent: CancelHermesRequestIntent(),
      phrases: [
        "Cancel a Hermes request in \(.applicationName)",
        "Stop Hermes request in \(.applicationName)",
      ],
      shortTitle: "Cancel Request",
      systemImageName: "xmark.circle"
    )
    AppShortcut(
      intent: RespondToHermesApprovalIntent(),
      phrases: [
        "Respond to Hermes approval in \(.applicationName)",
        "Send Hermes approval decision in \(.applicationName)",
      ],
      shortTitle: "Approval",
      systemImageName: "checkmark.shield"
    )
    AppShortcut(
      intent: CheckHermesBridgeHealthIntent(),
      phrases: [
        "Check Hermes Bridge health in \(.applicationName)",
        "Is Hermes Bridge available in \(.applicationName)",
      ],
      shortTitle: "Bridge Health",
      systemImageName: "heart.text.square"
    )
  }
}
