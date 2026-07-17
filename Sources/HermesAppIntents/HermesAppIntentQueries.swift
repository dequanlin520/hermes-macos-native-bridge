import AppIntents
import Foundation

public struct HermesAppIntentBindingQuery: EntityQuery {
  public init() {}

  public func entities(for identifiers: [HermesAppIntentBindingEntity.ID]) async throws
    -> [HermesAppIntentBindingEntity]
  {
    let bindings = try await HermesAppIntentDependencyProvider.shared.enabledBindings()
    let allowed = Set(identifiers)
    return bindings.filter { allowed.contains($0.id) }
  }

  public func suggestedEntities() async throws -> [HermesAppIntentBindingEntity] {
    try await HermesAppIntentDependencyProvider.shared.enabledBindings()
  }
}

public struct HermesAppIntentRequestQuery: EntityQuery {
  public init() {}

  public func entities(for identifiers: [HermesAppIntentRequestEntity.ID]) async throws
    -> [HermesAppIntentRequestEntity]
  {
    let client = try await HermesAppIntentDependencyProvider.shared.client()
    let operations = HermesAppIntentOperations(client: client)
    var entities: [HermesAppIntentRequestEntity] = []
    for identifier in identifiers {
      if let entity = try? await operations.status(requestID: identifier) {
        entities.append(entity)
      }
    }
    return entities
  }
}
