import Foundation
import HermesRuntimeFoundation

public actor HermesAppIntentDependencyProvider {
  public static let shared = HermesAppIntentDependencyProvider()

  private var clientFactory: any HermesAppIntentClientFactory =
    HermesAppIntentProductionClientFactory()
  private var bindingProvider: any HermesAppIntentBindingProviding =
    HermesAppIntentProductionBindingProvider()

  public func client() async throws -> any HermesAppIntentClient {
    try await clientFactory.makeClient()
  }

  public func enabledBindings() async throws -> [HermesAppIntentBindingEntity] {
    try await bindingProvider.enabledBindings().map {
      try HermesAppIntentBindingEntity(
        id: $0.id.rawValue,
        displayName: $0.displayName,
        safeDescription: $0.safeDescription
      )
    }
  }

  public func replaceForTesting(
    clientFactory: any HermesAppIntentClientFactory,
    bindingProvider: any HermesAppIntentBindingProviding
  ) {
    self.clientFactory = clientFactory
    self.bindingProvider = bindingProvider
  }

  public func resetTestingOverrides() {
    clientFactory = HermesAppIntentProductionClientFactory()
    bindingProvider = HermesAppIntentProductionBindingProvider()
  }
}

public struct HermesAppIntentOperations: Sendable {
  public static let maximumPromptBytes = 64 * 1024

  private let client: any HermesAppIntentClient

  public init(client: any HermesAppIntentClient) {
    self.client = client
  }

  public func submit(bindingID: String, prompt: String) async throws
    -> HermesAppIntentRequestEntity
  {
    let bindingID = try parseBindingID(bindingID)
    try validate(prompt: prompt)
    let requestID = try await client.submit(bindingID: bindingID, prompt: prompt)
    return HermesAppIntentRequestEntity(requestID: requestID)
  }

  public func status(requestID: String) async throws -> HermesAppIntentRequestEntity {
    let requestID = try parseRequestID(requestID)
    return HermesAppIntentRequestEntity(status: try await client.status(requestID: requestID))
  }

  public func cancel(requestID: String) async throws -> HermesAppIntentRequestEntity {
    let requestID = try parseRequestID(requestID)
    return HermesAppIntentRequestEntity(status: try await client.cancel(requestID: requestID))
  }

  public func respondToApproval(
    requestID: String,
    decision: HermesAppIntentApprovalDecision
  ) async throws -> HermesAppIntentRequestEntity {
    let requestID = try parseRequestID(requestID)
    return HermesAppIntentRequestEntity(
      status: try await client.respondToApproval(requestID: requestID, decision: decision)
    )
  }

  public func health() async throws -> HermesAppIntentHealthStatus {
    try await client.health()
  }

  public static func validate(prompt: String) throws {
    guard !prompt.isEmpty, prompt.utf8.count <= maximumPromptBytes else {
      throw HermesAppIntentError.oversizedPrompt
    }
  }

  private func validate(prompt: String) throws {
    try Self.validate(prompt: prompt)
  }

  private func parseBindingID(_ value: String) throws -> HermesRequestBindingID {
    do {
      return try HermesRequestBindingID(rawValue: value)
    } catch {
      throw HermesAppIntentError.invalidBinding
    }
  }

  private func parseRequestID(_ value: String) throws -> HermesRequestID {
    do {
      return try HermesRequestID(rawValue: value)
    } catch {
      throw HermesAppIntentError.requestNotFound
    }
  }
}
