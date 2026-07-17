import Foundation
import HermesRuntimeFoundation

public struct HermesBridgeProtocolVersion: Codable, Equatable, Sendable,
  CustomStringConvertible
{
  public static let current = HermesBridgeProtocolVersion(major: 1, minor: 1)
  public static let supportedMajor = 1

  public let major: Int
  public let minor: Int

  public init(major: Int, minor: Int) {
    self.major = major
    self.minor = minor
  }

  public var isSupported: Bool {
    major == Self.supportedMajor && minor >= 0
  }

  public func isCompatible(with serviceVersion: HermesBridgeProtocolVersion) -> Bool {
    major == serviceVersion.major && minor >= serviceVersion.minor
  }

  public var description: String {
    "\(major).\(minor)"
  }
}

public enum HermesBridgeCapability: String, Codable, CaseIterable, Equatable, Sendable {
  case submitRequest
  case requestStatus
  case cancelRequest
  case respondToApproval
  case protocolVersion
  case bindingDiscovery
}

public enum HermesBridgeOperation: String, Codable, CaseIterable, Equatable, Sendable {
  case submit
  case status
  case cancel
  case approvalResponse
  case capabilities
  case protocolVersion
  case listEnabledBindings
}

public struct HermesBridgeCorrelationID: Codable, Equatable, Hashable, Sendable,
  CustomStringConvertible
{
  public static let maximumLength = 128
  public static let fallback = try! HermesBridgeCorrelationID(rawValue: "unavailable")

  public let rawValue: String

  public init(rawValue: String) throws {
    guard Self.isValid(rawValue) else {
      throw HermesBridgeXPCError.malformedPayload
    }
    self.rawValue = rawValue
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(rawValue: container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var description: String {
    rawValue
  }

  static func isValid(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= maximumLength else {
      return false
    }
    return value.allSatisfy { character in
      character.isASCII
        && (character.isLetter || character.isNumber || character == "." || character == "_"
          || character == "-")
    }
  }
}

public enum HermesBridgeXPCError: String, Codable, Error, Equatable, Sendable {
  case unsupportedProtocolVersion
  case malformedPayload
  case oversizedPayload
  case unsupportedOperation
  case invalidBinding
  case requestNotFound
  case invalidState
  case serviceUnavailable
  case internalFailure
}

public struct HermesBridgeSubmitPayload: Codable, Equatable, Sendable {
  public let bindingID: String
  public let prompt: String

  public init(bindingID: String, prompt: String) {
    self.bindingID = bindingID
    self.prompt = prompt
  }
}

public struct HermesBridgeRequestIDPayload: Codable, Equatable, Sendable {
  public let requestID: String

  public init(requestID: String) {
    self.requestID = requestID
  }
}

public enum HermesBridgeApprovalDecision: String, Codable, Equatable, Sendable {
  case approve
  case reject

  var orchestratorDecision: HermesApprovalResponseDecision {
    switch self {
    case .approve:
      return .approve
    case .reject:
      return .reject
    }
  }
}

public struct HermesBridgeApprovalResponsePayload: Codable, Equatable, Sendable {
  public let requestID: String
  public let decision: HermesBridgeApprovalDecision

  public init(requestID: String, decision: HermesBridgeApprovalDecision) {
    self.requestID = requestID
    self.decision = decision
  }
}

public struct HermesBridgeBindingSummary: Codable, Equatable, Sendable {
  public static let maximumCount = 128
  public static let maximumPayloadBytes = 64 * 1024
  public static let maximumDisplayNameCharacters = 80
  public static let maximumDescriptionCharacters = 240

  public let bindingID: String
  public let localizedDisplayName: String
  public let safeLocalizedDescription: String
  public let maximumPromptBytes: Int
  public let approvalPolicy: String
  public let enabled: Bool

  public init(
    bindingID: HermesRequestBindingID,
    localizedDisplayName: String,
    safeLocalizedDescription: String,
    maximumPromptBytes: Int,
    approvalPolicy: String,
    enabled: Bool
  ) {
    self.bindingID = bindingID.rawValue
    self.localizedDisplayName = Self.safeText(
      localizedDisplayName,
      maximumCharacters: Self.maximumDisplayNameCharacters
    )
    self.safeLocalizedDescription = Self.safeText(
      safeLocalizedDescription,
      maximumCharacters: Self.maximumDescriptionCharacters
    )
    self.maximumPromptBytes = max(
      0, min(maximumPromptBytes, HermesBridgeRequestEnvelope.maximumPromptBytes))
    self.approvalPolicy = Self.safeToken(approvalPolicy)
    self.enabled = enabled
  }

  private static func safeText(_ value: String, maximumCharacters: Int) -> String {
    let filtered = value.unicodeScalars.filter { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
    }
    return String(String.UnicodeScalarView(filtered)).prefixString(maximumCharacters)
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
    return String(filtered.prefix(40))
  }
}

public struct HermesBridgeBindingListPayload: Codable, Equatable, Sendable {
  public let protocolVersion: HermesBridgeProtocolVersion
  public let bindings: [HermesBridgeBindingSummary]

  public init(
    protocolVersion: HermesBridgeProtocolVersion = .current,
    bindings: [HermesBridgeBindingSummary]
  ) throws {
    let sorted =
      bindings
      .filter(\.enabled)
      .sorted { $0.bindingID.localizedStandardCompare($1.bindingID) == .orderedAscending }
    self.protocolVersion = protocolVersion
    self.bindings = Array(sorted.prefix(HermesBridgeBindingSummary.maximumCount))
    let encoded = (try? JSONEncoder().encode(self)) ?? Data()
    guard encoded.count <= HermesBridgeBindingSummary.maximumPayloadBytes else {
      throw HermesBridgeXPCError.oversizedPayload
    }
  }
}

public struct HermesBridgeRequestEnvelope: Codable, Equatable, Sendable {
  public static let maximumEnvelopeBytes = 128 * 1024
  public static let maximumPromptBytes = 64 * 1024

  public let protocolVersion: HermesBridgeProtocolVersion
  public let correlationID: HermesBridgeCorrelationID
  public let operation: HermesBridgeOperation
  public let submit: HermesBridgeSubmitPayload?
  public let status: HermesBridgeRequestIDPayload?
  public let cancel: HermesBridgeRequestIDPayload?
  public let approvalResponse: HermesBridgeApprovalResponsePayload?

  public init(
    protocolVersion: HermesBridgeProtocolVersion = .current,
    correlationID: HermesBridgeCorrelationID,
    operation: HermesBridgeOperation,
    submit: HermesBridgeSubmitPayload? = nil,
    status: HermesBridgeRequestIDPayload? = nil,
    cancel: HermesBridgeRequestIDPayload? = nil,
    approvalResponse: HermesBridgeApprovalResponsePayload? = nil
  ) {
    self.protocolVersion = protocolVersion
    self.correlationID = correlationID
    self.operation = operation
    self.submit = submit
    self.status = status
    self.cancel = cancel
    self.approvalResponse = approvalResponse
  }
}

public struct HermesBridgeRequestStatusPayload: Codable, Equatable, Sendable {
  public let requestID: String
  public let bindingID: String
  public let lifecycleState: String
  public let cancellationRequested: Bool
  public let resultAvailable: Bool
  public let failureCode: String?
  public let failureRetryable: Bool?

  public init(record: HermesRequestRecord) {
    self.requestID = record.requestID.rawValue
    self.bindingID = record.bindingID.rawValue
    self.lifecycleState = record.lifecycleState.rawValue
    self.cancellationRequested = record.cancellationRequested
    self.resultAvailable = record.result?.availability == .available
    self.failureCode = record.failure?.code
    self.failureRetryable = record.failure?.retryable
  }
}

public struct HermesBridgeProtocolVersionPayload: Codable, Equatable, Sendable {
  public let version: HermesBridgeProtocolVersion

  public init(version: HermesBridgeProtocolVersion) {
    self.version = version
  }
}

public struct HermesBridgeCapabilitiesPayload: Codable, Equatable, Sendable {
  public let protocolVersion: HermesBridgeProtocolVersion
  public let capabilities: [HermesBridgeCapability]

  public init(
    protocolVersion: HermesBridgeProtocolVersion = .current,
    capabilities: [HermesBridgeCapability] = HermesBridgeCapability.allCases
  ) {
    self.protocolVersion = protocolVersion
    self.capabilities = capabilities
  }
}

public enum HermesBridgeSuccessPayload: Codable, Equatable, Sendable {
  case protocolVersion(HermesBridgeProtocolVersionPayload)
  case capabilities(HermesBridgeCapabilitiesPayload)
  case listEnabledBindings(HermesBridgeBindingListPayload)
  case submit(HermesBridgeRequestIDPayload)
  case status(HermesBridgeRequestStatusPayload)
  case cancel(HermesBridgeRequestStatusPayload)
  case approvalResponse(HermesBridgeRequestStatusPayload)
}

public struct HermesBridgeErrorPayload: Codable, Equatable, Sendable {
  public let code: HermesBridgeXPCError
  public let safeMessage: String

  public init(code: HermesBridgeXPCError, safeMessage: String) {
    self.code = code
    self.safeMessage = safeMessage
  }
}

public enum HermesBridgeResponseResult: Codable, Equatable, Sendable {
  case success(HermesBridgeSuccessPayload)
  case failure(HermesBridgeErrorPayload)
}

public struct HermesBridgeResponseEnvelope: Codable, Equatable, Sendable {
  public let protocolVersion: HermesBridgeProtocolVersion
  public let correlationID: HermesBridgeCorrelationID
  public let result: HermesBridgeResponseResult

  public init(
    protocolVersion: HermesBridgeProtocolVersion = .current,
    correlationID: HermesBridgeCorrelationID,
    result: HermesBridgeResponseResult
  ) {
    self.protocolVersion = protocolVersion
    self.correlationID = correlationID
    self.result = result
  }
}

extension String {
  fileprivate func prefixString(_ count: Int) -> String {
    String(prefix(count))
  }
}
