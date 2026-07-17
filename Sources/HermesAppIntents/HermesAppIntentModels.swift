import AppIntents
import Foundation
import HermesBridgeXPC
import HermesRuntimeFoundation

public struct HermesAppIntentBindingEntity: AppEntity, Equatable, Sendable,
  CustomStringConvertible, CustomDebugStringConvertible
{
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Hermes Binding")
  public static let defaultQuery = HermesAppIntentBindingQuery()

  public let id: String
  public let displayName: String
  public let safeDescription: String

  public init(id: String, displayName: String, safeDescription: String) throws {
    _ = try HermesRequestBindingID(rawValue: id)
    self.id = id
    self.displayName = String(displayName.prefix(Self.maximumDisplayNameCharacters))
    self.safeDescription = Self.redactedDescription(safeDescription)
  }

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: LocalizedStringResource(stringLiteral: displayName),
      subtitle: LocalizedStringResource(stringLiteral: safeDescription)
    )
  }

  public var description: String {
    "HermesAppIntentBindingEntity(id: \(id), displayName: \(displayName))"
  }

  public var debugDescription: String {
    description
  }

  private static let maximumDisplayNameCharacters = 80
  private static let maximumDescriptionCharacters = 160

  static func redactedDescription(_ value: String) -> String {
    let filtered = value.unicodeScalars.filter { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
    }
    return String(String.UnicodeScalarView(filtered)).prefixString(maximumDescriptionCharacters)
  }
}

public struct HermesAppIntentRequestEntity: AppEntity, Equatable, Sendable,
  CustomStringConvertible, CustomDebugStringConvertible
{
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Hermes Request")
  public static let defaultQuery = HermesAppIntentRequestQuery()

  public let id: String
  public let lifecycleState: String
  public let cancellationRequested: Bool
  public let resultAvailable: Bool
  public let failureCode: String?

  public init(
    id: String,
    lifecycleState: String,
    cancellationRequested: Bool = false,
    resultAvailable: Bool = false,
    failureCode: String? = nil
  ) throws {
    _ = try HermesRequestID(rawValue: id)
    self.id = id
    self.lifecycleState = lifecycleState
    self.cancellationRequested = cancellationRequested
    self.resultAvailable = resultAvailable
    self.failureCode = failureCode
  }

  public init(requestID: HermesRequestID) {
    self.id = requestID.rawValue
    self.lifecycleState = HermesAppIntentLifecycleState.accepted.rawValue
    self.cancellationRequested = false
    self.resultAvailable = false
    self.failureCode = nil
  }

  public init(status: HermesAppIntentRequestStatus) {
    self.id = status.requestID
    self.lifecycleState = status.lifecycleState.rawValue
    self.cancellationRequested = status.cancellationRequested
    self.resultAvailable = status.resultAvailable
    self.failureCode = status.failureCode
  }

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: LocalizedStringResource(stringLiteral: id),
      subtitle: LocalizedStringResource(stringLiteral: lifecycleState)
    )
  }

  public var description: String {
    "HermesAppIntentRequestEntity(id: \(id), lifecycleState: \(lifecycleState), resultAvailable: \(resultAvailable))"
  }

  public var debugDescription: String {
    description
  }
}

public enum HermesAppIntentLifecycleState: String, AppEnum, Codable, CaseIterable, Sendable {
  case accepted
  case queued
  case starting
  case running
  case waitingForApproval
  case cancelling
  case cancelled
  case completed
  case failed
  case interrupted
  case unknown

  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Hermes State")
  public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .accepted: "Accepted",
    .queued: "Queued",
    .starting: "Starting",
    .running: "Running",
    .waitingForApproval: "Waiting for Approval",
    .cancelling: "Cancelling",
    .cancelled: "Cancelled",
    .completed: "Completed",
    .failed: "Failed",
    .interrupted: "Interrupted",
    .unknown: "Unknown",
  ]

  init(rawBridgeValue: String) {
    self = HermesAppIntentLifecycleState(rawValue: rawBridgeValue) ?? .unknown
  }
}

public enum HermesAppIntentApprovalDecision: String, AppEnum, Codable, CaseIterable, Sendable {
  case allow
  case deny

  public static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: "Hermes Approval Decision")
  public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .allow: "Allow",
    .deny: "Deny",
  ]

  var bridgeDecision: HermesBridgeApprovalDecision {
    switch self {
    case .allow:
      return .approve
    case .deny:
      return .reject
    }
  }
}

public struct HermesAppIntentRequestStatus: Equatable, Sendable {
  public let requestID: String
  public let lifecycleState: HermesAppIntentLifecycleState
  public let cancellationRequested: Bool
  public let resultAvailable: Bool
  public let failureCode: String?
  public let failureRetryable: Bool?

  public init(payload: HermesBridgeRequestStatusPayload) {
    self.requestID = payload.requestID
    self.lifecycleState = HermesAppIntentLifecycleState(rawBridgeValue: payload.lifecycleState)
    self.cancellationRequested = payload.cancellationRequested
    self.resultAvailable = payload.resultAvailable
    self.failureCode = payload.failureCode
    self.failureRetryable = payload.failureRetryable
  }

  public init(
    requestID: String,
    lifecycleState: HermesAppIntentLifecycleState,
    cancellationRequested: Bool,
    resultAvailable: Bool,
    failureCode: String? = nil,
    failureRetryable: Bool? = nil
  ) {
    self.requestID = requestID
    self.lifecycleState = lifecycleState
    self.cancellationRequested = cancellationRequested
    self.resultAvailable = resultAvailable
    self.failureCode = failureCode
    self.failureRetryable = failureRetryable
  }
}

public struct HermesAppIntentHealthStatus: Equatable, Sendable {
  public let available: Bool
  public let compatible: Bool
  public let protocolVersion: String?
  public let supportedCapabilities: [String]

  public init(
    available: Bool,
    compatible: Bool,
    protocolVersion: String?,
    supportedCapabilities: [String]
  ) {
    self.available = available
    self.compatible = compatible
    self.protocolVersion = protocolVersion
    self.supportedCapabilities = supportedCapabilities
  }
}

public struct HermesAppIntentBindingDefinition: Equatable, Sendable {
  public let id: HermesRequestBindingID
  public let enabled: Bool
  public let displayName: String
  public let safeDescription: String

  public init(
    id: HermesRequestBindingID,
    enabled: Bool,
    displayName: String,
    safeDescription: String
  ) {
    self.id = id
    self.enabled = enabled
    self.displayName = displayName
    self.safeDescription = safeDescription
  }

  public init(summary: HermesBridgeBindingSummary) throws {
    self.init(
      id: try HermesRequestBindingID(rawValue: summary.bindingID),
      enabled: summary.enabled,
      displayName: summary.localizedDisplayName,
      safeDescription: summary.safeLocalizedDescription
    )
  }
}

extension String {
  fileprivate func prefixString(_ count: Int) -> String {
    String(prefix(count))
  }
}
