import Foundation
import HermesBridgeXPC
import HermesRuntimeFoundation

public enum HermesBridgeServiceConfigurationError: Error, Equatable, Sendable {
  case unsupportedSchemaVersion(Int)
  case invalidMachServiceName
  case invalidRoot(String)
  case missingExecutableCandidate
  case invalidExecutableCandidate
  case invalidPortPolicy
  case invalidTimeout
  case invalidMaximumConcurrentRequests
  case duplicateBindingID(String)
  case invalidBinding
}

public struct HermesBridgeLoopbackPortPolicy: Codable, Equatable, Sendable {
  public let fixedPort: Int

  public init(fixedPort: Int) throws {
    guard (1...65535).contains(fixedPort) else {
      throw HermesBridgeServiceConfigurationError.invalidPortPolicy
    }
    self.fixedPort = fixedPort
  }
}

public struct HermesBridgeServiceTimeouts: Codable, Equatable, Sendable {
  public let startup: TimeInterval
  public let gracefulShutdown: TimeInterval
  public let forcedShutdown: TimeInterval
  public let gatewayReady: TimeInterval

  public init(
    startup: TimeInterval,
    gracefulShutdown: TimeInterval,
    forcedShutdown: TimeInterval,
    gatewayReady: TimeInterval
  ) throws {
    for value in [startup, gracefulShutdown, forcedShutdown, gatewayReady] {
      guard value.isFinite, value > 0, value <= 120 else {
        throw HermesBridgeServiceConfigurationError.invalidTimeout
      }
    }
    self.startup = startup
    self.gracefulShutdown = gracefulShutdown
    self.forcedShutdown = forcedShutdown
    self.gatewayReady = gatewayReady
  }
}

public enum HermesBridgeBindingApprovalPolicy: String, Codable, Equatable, Sendable {
  case explicit
  case unavailable
}

public struct HermesBridgeBindingDefinition: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let id: String
  public let enabled: Bool
  public let maximumPromptBytes: Int
  public let timeoutSeconds: TimeInterval?
  public let approvalPolicy: HermesBridgeBindingApprovalPolicy
  public let localizedDisplayName: String
  public let safeLocalizedDescription: String

  public init(
    schemaVersion: Int = currentSchemaVersion,
    id: String,
    enabled: Bool,
    maximumPromptBytes: Int,
    timeoutSeconds: TimeInterval?,
    approvalPolicy: HermesBridgeBindingApprovalPolicy,
    localizedDisplayName: String? = nil,
    safeLocalizedDescription: String = ""
  ) throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw HermesBridgeServiceConfigurationError.unsupportedSchemaVersion(schemaVersion)
    }
    _ = try HermesRequestBindingID(rawValue: id)
    guard maximumPromptBytes > 0,
      maximumPromptBytes <= HermesBridgeRequestEnvelope.maximumPromptBytes
    else {
      throw HermesBridgeServiceConfigurationError.invalidBinding
    }
    if let timeoutSeconds {
      guard timeoutSeconds.isFinite, timeoutSeconds > 0, timeoutSeconds <= 86_400 else {
        throw HermesBridgeServiceConfigurationError.invalidBinding
      }
    }
    self.schemaVersion = schemaVersion
    self.id = id
    self.enabled = enabled
    self.maximumPromptBytes = maximumPromptBytes
    self.timeoutSeconds = timeoutSeconds
    self.approvalPolicy = approvalPolicy
    self.localizedDisplayName = Self.safeText(
      localizedDisplayName ?? id,
      maximumCharacters: HermesBridgeBindingSummary.maximumDisplayNameCharacters
    )
    self.safeLocalizedDescription = Self.safeText(
      safeLocalizedDescription,
      maximumCharacters: HermesBridgeBindingSummary.maximumDescriptionCharacters
    )
  }

  public var requestBinding: HermesRequestBinding {
    let bindingID = try! HermesRequestBindingID(rawValue: id)
    return HermesRequestBinding(
      id: bindingID,
      enabled: enabled,
      maximumPromptBytes: maximumPromptBytes,
      timeoutPolicy: timeoutSeconds.map { HermesRequestExecutionPolicy(timeoutSeconds: $0) },
      approvalPolicy: approvalPolicy.rawValue,
      resultPolicy: nil
    )
  }

  public var bindingSummary: HermesBridgeBindingSummary {
    HermesBridgeBindingSummary(
      bindingID: try! HermesRequestBindingID(rawValue: id),
      localizedDisplayName: localizedDisplayName,
      safeLocalizedDescription: safeLocalizedDescription,
      maximumPromptBytes: maximumPromptBytes,
      approvalPolicy: approvalPolicy.rawValue,
      enabled: enabled
    )
  }

  private static func safeText(_ value: String, maximumCharacters: Int) -> String {
    let filtered = value.unicodeScalars.filter { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
    }
    return String(String.UnicodeScalarView(filtered)).prefixString(maximumCharacters)
  }
}

public struct HermesBridgeServiceConfiguration: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1
  public static let productionMachServiceName = "com.hermes.bridge.xpc"
  public static let productionLabel = "com.hermes.bridge"

  public let schemaVersion: Int
  public let machServiceName: String
  public let runtimeRoot: URL
  public let requestStateRoot: URL
  public let allowlistedHermesExecutableCandidates: [URL]
  public let loopbackPortPolicy: HermesBridgeLoopbackPortPolicy
  public let timeouts: HermesBridgeServiceTimeouts
  public let maximumConcurrentXPCRequests: Int
  public let bindings: [HermesBridgeBindingDefinition]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    machServiceName: String = productionMachServiceName,
    runtimeRoot: URL,
    requestStateRoot: URL,
    allowlistedHermesExecutableCandidates: [URL],
    loopbackPortPolicy: HermesBridgeLoopbackPortPolicy,
    timeouts: HermesBridgeServiceTimeouts,
    maximumConcurrentXPCRequests: Int,
    bindings: [HermesBridgeBindingDefinition] = [],
    allowTestMachServiceName: Bool = false
  ) throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw HermesBridgeServiceConfigurationError.unsupportedSchemaVersion(schemaVersion)
    }
    guard Self.isAllowedMachServiceName(machServiceName, allowTest: allowTestMachServiceName) else {
      throw HermesBridgeServiceConfigurationError.invalidMachServiceName
    }
    guard runtimeRoot.isFileURL, requestStateRoot.isFileURL else {
      throw HermesBridgeServiceConfigurationError.invalidRoot("roots_must_be_file_urls")
    }
    guard !allowlistedHermesExecutableCandidates.isEmpty else {
      throw HermesBridgeServiceConfigurationError.missingExecutableCandidate
    }
    guard
      allowlistedHermesExecutableCandidates.allSatisfy({
        $0.isFileURL && !$0.path.isEmpty && !$0.path.contains("\u{0}")
      })
    else {
      throw HermesBridgeServiceConfigurationError.invalidExecutableCandidate
    }
    guard (1...64).contains(maximumConcurrentXPCRequests) else {
      throw HermesBridgeServiceConfigurationError.invalidMaximumConcurrentRequests
    }
    var seen = Set<String>()
    for binding in bindings {
      guard seen.insert(binding.id).inserted else {
        throw HermesBridgeServiceConfigurationError.duplicateBindingID(binding.id)
      }
    }
    self.schemaVersion = schemaVersion
    self.machServiceName = machServiceName
    self.runtimeRoot = runtimeRoot.standardizedFileURL
    self.requestStateRoot = requestStateRoot.standardizedFileURL
    self.allowlistedHermesExecutableCandidates = allowlistedHermesExecutableCandidates.map {
      $0.standardizedFileURL
    }
    self.loopbackPortPolicy = loopbackPortPolicy
    self.timeouts = timeouts
    self.maximumConcurrentXPCRequests = maximumConcurrentXPCRequests
    self.bindings = bindings
  }

  public static func productionDefault() throws -> HermesBridgeServiceConfiguration {
    let support = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    .appendingPathComponent("HermesBridge", isDirectory: true)
    return try HermesBridgeServiceConfiguration(
      runtimeRoot: support.appendingPathComponent("Runtime", isDirectory: true),
      requestStateRoot: support.appendingPathComponent("RequestState", isDirectory: true),
      allowlistedHermesExecutableCandidates: [
        URL(fileURLWithPath: "/opt/hermes/bin/hermes"),
        URL(fileURLWithPath: "/usr/local/bin/hermes"),
      ],
      loopbackPortPolicy: HermesBridgeLoopbackPortPolicy(fixedPort: 17893),
      timeouts: HermesBridgeServiceTimeouts(
        startup: 20,
        gracefulShutdown: 8,
        forcedShutdown: 4,
        gatewayReady: 8
      ),
      maximumConcurrentXPCRequests: 8
    )
  }

  public static func decodeTrustedConfiguration(
    from url: URL,
    allowTestMachServiceName: Bool = false
  ) throws -> HermesBridgeServiceConfiguration {
    let data = try Data(contentsOf: url)
    let decoded = try JSONDecoder().decode(HermesBridgeServiceConfiguration.self, from: data)
    return try HermesBridgeServiceConfiguration(
      schemaVersion: decoded.schemaVersion,
      machServiceName: decoded.machServiceName,
      runtimeRoot: decoded.runtimeRoot,
      requestStateRoot: decoded.requestStateRoot,
      allowlistedHermesExecutableCandidates: decoded.allowlistedHermesExecutableCandidates,
      loopbackPortPolicy: decoded.loopbackPortPolicy,
      timeouts: decoded.timeouts,
      maximumConcurrentXPCRequests: decoded.maximumConcurrentXPCRequests,
      bindings: decoded.bindings,
      allowTestMachServiceName: allowTestMachServiceName
    )
  }

  public var machService: HermesBridgeMachServiceName {
    get throws {
      try HermesBridgeMachServiceName(machServiceName)
    }
  }

  private static func isAllowedMachServiceName(_ value: String, allowTest: Bool) -> Bool {
    guard (try? HermesBridgeMachServiceName(value)) != nil else {
      return false
    }
    if value == productionMachServiceName {
      return true
    }
    return allowTest && value.hasPrefix("com.hermes.bridge.test.")
  }
}

public struct ConfigurationBackedHermesRequestBindingRegistry: HermesRequestBindingRegistry {
  private let registry: StaticHermesRequestBindingRegistry
  private let summaries: [HermesBridgeBindingSummary]

  public init(definitions: [HermesBridgeBindingDefinition]) throws {
    var seen = Set<String>()
    for definition in definitions {
      guard seen.insert(definition.id).inserted else {
        throw HermesBridgeServiceConfigurationError.duplicateBindingID(definition.id)
      }
    }
    registry = StaticHermesRequestBindingRegistry(bindings: definitions.map(\.requestBinding))
    summaries = try HermesBridgeBindingListPayload(bindings: definitions.map(\.bindingSummary))
      .bindings
  }

  public func binding(for id: HermesRequestBindingID) async throws -> HermesRequestBinding? {
    try await registry.binding(for: id)
  }

  public func listEnabledBindings() async throws -> [HermesBridgeBindingSummary] {
    summaries
  }
}

extension ConfigurationBackedHermesRequestBindingRegistry: HermesBridgeRequestHandling {
  public func submit(bindingID _: HermesRequestBindingID, prompt _: String) async throws
    -> HermesRequestID
  {
    throw HermesBridgeXPCError.unsupportedOperation
  }

  public func status(requestID _: HermesRequestID) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedOperation
  }

  public func cancel(requestID _: HermesRequestID) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedOperation
  }

  public func respondToApproval(
    requestID _: HermesRequestID,
    decision _: HermesApprovalResponseDecision
  ) async throws -> HermesRequestRecord {
    throw HermesBridgeXPCError.unsupportedOperation
  }
}

extension String {
  fileprivate func prefixString(_ count: Int) -> String {
    String(prefix(count))
  }
}
