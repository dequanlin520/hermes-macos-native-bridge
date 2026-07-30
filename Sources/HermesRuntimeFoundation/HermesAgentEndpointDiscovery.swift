import Foundation

public enum HermesAgentListenerOwnershipStatus: String, Codable, Equatable, Sendable {
  case provenRoot = "proven-root"
  case provenDescendant = "proven-descendant"
  case ambiguous
  case unavailable
  case identityMismatch = "identity-mismatch"
  case multipleCandidates = "multiple-candidates"
  case nonLoopbackRejected = "non-loopback-rejected"
}

public enum HermesAgentEndpointDiscoveryError: Error, Equatable, Sendable {
  case listenerMissing
  case multipleCandidates
  case identityMismatch
  case nonLoopback
  case outputSocketMismatch
  case unavailable

  public var reasonCode: String {
    switch self {
    case .listenerMissing: "endpoint.listener-missing"
    case .multipleCandidates: "endpoint.multiple-candidates"
    case .identityMismatch: "endpoint.identity-mismatch"
    case .nonLoopback: "endpoint.non-loopback"
    case .outputSocketMismatch: "endpoint.output-socket-mismatch"
    case .unavailable: "endpoint.unavailable"
    }
  }
}

public struct HermesAgentListenerIdentity: Codable, Equatable, Sendable {
  public enum Transport: String, Codable, Equatable, Sendable {
    case tcp
    case unix
  }

  public let transport: Transport
  public let address: String
  public let port: Int?
  public let socketPathCategory: String?
  public let owningPID: pid_t
  public let owningUID: uid_t
  public let owningProcessStartTime: String
  public let appearedAfterLaunchCheckpoint: Bool

  public init(
    transport: Transport,
    address: String,
    port: Int?,
    socketPathCategory: String?,
    owningPID: pid_t,
    owningUID: uid_t,
    owningProcessStartTime: String,
    appearedAfterLaunchCheckpoint: Bool
  ) {
    self.transport = transport
    self.address = address
    self.port = port
    self.socketPathCategory = Self.safeToken(socketPathCategory)
    self.owningPID = owningPID
    self.owningUID = owningUID
    self.owningProcessStartTime = owningProcessStartTime
    self.appearedAfterLaunchCheckpoint = appearedAfterLaunchCheckpoint
  }

  public var isLoopback: Bool {
    if transport == .unix {
      return socketPathCategory == "acceptance-owned"
    }
    return address == "127.0.0.1" || address == "::1" || address == "localhost"
  }

  private static func safeToken(_ value: String?) -> String? {
    guard let value else { return nil }
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
    }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(96))
  }
}

public struct HermesAgentEndpointDescriptor: Codable, Equatable, Sendable {
  public enum RequestedPortCategory: String, Codable, Equatable, Sendable {
    case dynamic
    case fixed
    case none
  }

  public let requestedPortCategory: RequestedPortCategory
  public let observedAssignedPort: Int?
  public let loopbackAddressFamily: String
  public let discoveryTimestamp: String
  public let listener: HermesAgentListenerIdentity

  public init(
    requestedPortCategory: RequestedPortCategory,
    observedAssignedPort: Int?,
    loopbackAddressFamily: String,
    discoveryTimestamp: String,
    listener: HermesAgentListenerIdentity
  ) {
    self.requestedPortCategory = requestedPortCategory
    self.observedAssignedPort = observedAssignedPort
    self.loopbackAddressFamily = Self.safeToken(loopbackAddressFamily)
    self.discoveryTimestamp = discoveryTimestamp
    self.listener = listener
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
    }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(96))
  }
}

public struct HermesAgentEndpointOwnershipEvidence: Codable, Equatable, Sendable {
  public let status: HermesAgentListenerOwnershipStatus
  public let ownerRelationship: String
  public let endpointUnique: Bool
  public let startupOutputEndpointMatch: String
  public let descriptor: HermesAgentEndpointDescriptor?
  public let reasonCode: String

  public init(
    status: HermesAgentListenerOwnershipStatus,
    ownerRelationship: String,
    endpointUnique: Bool,
    startupOutputEndpointMatch: String,
    descriptor: HermesAgentEndpointDescriptor?,
    reasonCode: String
  ) {
    self.status = status
    self.ownerRelationship = Self.safeToken(ownerRelationship)
    self.endpointUnique = endpointUnique
    self.startupOutputEndpointMatch = Self.safeToken(startupOutputEndpointMatch)
    self.descriptor = descriptor
    self.reasonCode = Self.safeToken(reasonCode)
  }

  public var ownershipProven: Bool {
    status == .provenRoot || status == .provenDescendant
  }

  private static func safeToken(_ value: String) -> String {
    let filtered = value.filter {
      $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
    }
    return filtered.isEmpty ? "unknown" : String(filtered.prefix(128))
  }
}

public protocol HermesAgentSocketOwnershipInspecting: Sendable {
  func listeners(for identities: [HermesAgentProcessIdentity]) throws -> [HermesAgentListenerIdentity]
}

public struct UnavailableHermesAgentSocketOwnershipInspector: HermesAgentSocketOwnershipInspecting {
  public init() {}
  public func listeners(for _: [HermesAgentProcessIdentity]) throws -> [HermesAgentListenerIdentity] {
    throw HermesAgentEndpointDiscoveryError.unavailable
  }
}

public struct HermesAgentEndpointDiscovery: Sendable {
  private let inspector: HermesAgentSocketOwnershipInspecting
  private let now: @Sendable () -> String

  public init(
    inspector: HermesAgentSocketOwnershipInspecting,
    now: @escaping @Sendable () -> String = { ISO8601DateFormatter().string(from: Date()) }
  ) {
    self.inspector = inspector
    self.now = now
  }

  public func discover(
    root: HermesAgentProcessIdentity,
    processTree: HermesAgentProcessTree,
    requestedPortCategory: HermesAgentEndpointDescriptor.RequestedPortCategory,
    startupOutputCandidatePort: Int? = nil
  ) -> HermesAgentEndpointOwnershipEvidence {
    let identities = processTree.acceptanceOwnedIdentities.isEmpty
      ? [root]
      : processTree.acceptanceOwnedIdentities

    let listeners: [HermesAgentListenerIdentity]
    do {
      listeners = try inspector.listeners(for: identities)
    } catch {
      return evidence(.unavailable, relationship: "unavailable", reason: "endpoint.unavailable")
    }

    guard !listeners.isEmpty else {
      return evidence(.unavailable, relationship: "none", reason: "endpoint.listener-missing")
    }
    guard listeners.allSatisfy(\.isLoopback) else {
      return evidence(
        .nonLoopbackRejected,
        relationship: "non-loopback",
        unique: false,
        reason: "endpoint.non-loopback"
      )
    }

    let validated = listeners.compactMap { listener -> (HermesAgentListenerIdentity, String)? in
      guard listener.appearedAfterLaunchCheckpoint else { return nil }
      if listener.owningPID == root.pid {
        return listenerMatches(listener, identity: root) ? (listener, "acceptance-owned-root") : nil
      }
      guard let descendant = identities.first(where: { $0.pid == listener.owningPID }),
        listenerMatches(listener, identity: descendant),
        HermesAgentProcessTopology.isProvenDescendant(descendant, parent: root)
      else {
        return nil
      }
      return (listener, "acceptance-owned-descendant")
    }

    guard !validated.isEmpty else {
      return evidence(
        .identityMismatch,
        relationship: "identity-mismatch",
        unique: false,
        reason: "endpoint.identity-mismatch"
      )
    }
    guard validated.count == 1 else {
      return evidence(
        .multipleCandidates,
        relationship: "multiple-candidates",
        unique: false,
        reason: "endpoint.multiple-candidates"
      )
    }

    let (listener, relationship) = validated[0]
    if let startupOutputCandidatePort, listener.port != startupOutputCandidatePort {
      return evidence(
        .ambiguous,
        relationship: relationship,
        unique: true,
        reason: "endpoint.output-socket-mismatch"
      )
    }
    let descriptor = HermesAgentEndpointDescriptor(
      requestedPortCategory: requestedPortCategory,
      observedAssignedPort: listener.port,
      loopbackAddressFamily: listener.address.contains(":") ? "ipv6" : "ipv4",
      discoveryTimestamp: now(),
      listener: listener
    )
    return HermesAgentEndpointOwnershipEvidence(
      status: relationship == "acceptance-owned-root" ? .provenRoot : .provenDescendant,
      ownerRelationship: relationship,
      endpointUnique: true,
      startupOutputEndpointMatch: startupOutputCandidatePort == nil ? "not-emitted" : "matched",
      descriptor: descriptor,
      reasonCode: "endpoint.ownership-proven"
    )
  }

  private func listenerMatches(
    _ listener: HermesAgentListenerIdentity,
    identity: HermesAgentProcessIdentity
  ) -> Bool {
    listener.owningPID == identity.pid
      && listener.owningUID == identity.uid
      && listener.owningProcessStartTime == identity.processStartTime
  }

  private func evidence(
    _ status: HermesAgentListenerOwnershipStatus,
    relationship: String,
    unique: Bool = false,
    reason: String
  ) -> HermesAgentEndpointOwnershipEvidence {
    HermesAgentEndpointOwnershipEvidence(
      status: status,
      ownerRelationship: relationship,
      endpointUnique: unique,
      startupOutputEndpointMatch: "not-evaluated",
      descriptor: nil,
      reasonCode: reason
    )
  }
}

public struct LsofHermesAgentSocketOwnershipInspector: HermesAgentSocketOwnershipInspecting {
  private let executableURL: URL
  private let launchCheckpointStartTime: String
  private let runner: @Sendable ([String]) throws -> String

  public init(
    executableURL: URL,
    launchCheckpointStartTime: String,
    runner: (@Sendable ([String]) throws -> String)? = nil
  ) {
    self.executableURL = executableURL
    self.launchCheckpointStartTime = launchCheckpointStartTime
    self.runner = runner ?? LsofHermesAgentSocketOwnershipInspector.runLsof
  }

  public func listeners(for identities: [HermesAgentProcessIdentity]) throws -> [HermesAgentListenerIdentity] {
    let validated = identities.filter { DarwinHermesAgentProcessIdentityValidator().validate($0) }
    guard !validated.isEmpty else { return [] }
    var listeners: [HermesAgentListenerIdentity] = []
    for identity in validated {
      let output = try runner(["-nP", "-a", "-p", "\(identity.pid)", "-iTCP", "-sTCP:LISTEN", "-FpcnPT"])
      listeners.append(contentsOf: Self.parseLsof(output, identity: identity, checkpoint: launchCheckpointStartTime))
    }
    _ = executableURL
    return listeners
  }

  static func parseLsof(
    _ output: String,
    identity: HermesAgentProcessIdentity,
    checkpoint: String
  ) -> [HermesAgentListenerIdentity] {
    var result: [HermesAgentListenerIdentity] = []
    var currentPID: pid_t?
    var protocolName: String?

    for rawLine in output.split(whereSeparator: \.isNewline) {
      let line = String(rawLine)
      guard let tag = line.first else { continue }
      let value = String(line.dropFirst())
      switch tag {
      case "p":
        currentPID = pid_t(value)
      case "P":
        protocolName = value.lowercased()
      case "n":
        guard currentPID == identity.pid, protocolName == "tcp",
          let parsed = parseTCPName(value)
        else { continue }
        result.append(
          HermesAgentListenerIdentity(
            transport: .tcp,
            address: parsed.address,
            port: parsed.port,
            socketPathCategory: nil,
            owningPID: identity.pid,
            owningUID: identity.uid,
            owningProcessStartTime: identity.processStartTime,
            appearedAfterLaunchCheckpoint: startTime(identity.processStartTime) >= startTime(checkpoint)
          ))
      default:
        continue
      }
    }
    return result
  }

  private static func parseTCPName(_ value: String) -> (address: String, port: Int)? {
    let stripped = value.replacingOccurrences(of: "TCP ", with: "")
    if stripped.hasPrefix("[::1]:"),
      let port = Int(stripped.replacingOccurrences(of: "[::1]:", with: ""))
    {
      return ("::1", port)
    }
    guard let colon = stripped.lastIndex(of: ":"),
      let port = Int(stripped[stripped.index(after: colon)...])
    else { return nil }
    let address = String(stripped[..<colon])
    return (address, port)
  }

  private static func startTime(_ value: String) -> Double {
    Double(value) ?? 0
  }

  private static func runLsof(arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
      throw HermesAgentEndpointDiscoveryError.unavailable
    }
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  }
}
