import Foundation
import HermesPolicy

public struct HermesAdminPolicySummary: Codable, Equatable, Sendable {
  public let activePolicies: Int
  public let deniedPolicies: Int
  public let policyVersion: String
  public let policyIDs: [String]

  public init(policies: [HermesPolicyDefinition]) {
    activePolicies = policies.count
    deniedPolicies = policies.filter { policy in
      switch policy.value {
      case .decision(.deny):
        return true
      case .boolean(false):
        return true
      case .decision, .boolean, .integer, .text:
        return false
      }
    }.count
    policyVersion = HermesAdminPolicySummary.version(from: policies)
    policyIDs = policies.map { HermesAdminRedactor.safeToken($0.id) }.sorted()
  }

  public init(activePolicies: Int, deniedPolicies: Int, policyVersion: String, policyIDs: [String] = []) {
    self.activePolicies = max(0, activePolicies)
    self.deniedPolicies = max(0, deniedPolicies)
    self.policyVersion = HermesAdminRedactor.safeToken(policyVersion, fallback: "unknown", limit: 40)
    self.policyIDs = policyIDs.map { HermesAdminRedactor.safeToken($0) }.sorted()
  }

  private static func version(from policies: [HermesPolicyDefinition]) -> String {
    let versions = Set(policies.map { HermesAdminRedactor.safeToken($0.version, fallback: "unknown", limit: 40) })
    guard !versions.isEmpty else { return "unknown" }
    if versions.count == 1 { return versions.first ?? "unknown" }
    return versions.sorted().joined(separator: ",")
  }
}
