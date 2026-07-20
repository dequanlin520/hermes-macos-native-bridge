import Foundation
import HermesRuntimeFoundation

@main
struct M6004AuditSigningOperationsFixture {
  static func main() async throws {
    guard CommandLine.arguments.count >= 3 else {
      FileHandle.standardError.write(
        Data("usage: M6004AuditSigningOperationsFixture <command> <audit-root>\n".utf8))
      Foundation.exit(64)
    }
    let command = CommandLine.arguments[1]
    let auditRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let coordinator = HermesAuditKeychainSetupCoordinator(auditRoot: auditRoot)
    switch command {
    case "setup":
      let status = try await coordinator.configureAuditSigningAccess()
      print(status.nonInteractiveSigningProven ? "SETUP=yes" : "SETUP=no")
    case "sign":
      let provider = try coordinator.signingProvider(policy: .signingRequired)
      let digest = HermesAuditDigest(Data("m6-004-sign".utf8))!
      guard let signature = try provider.sign(manifestDigest: digest),
        try provider.verify(signature: signature, manifestDigest: digest)
      else {
        print("SIGNATURE=no")
        Foundation.exit(1)
      }
      _ = try coordinator.verifyAuditSigning()
      print("SIGNATURE=yes")
    case "status":
      let status = coordinator.status()
      print("ACCESS_POLICY=\(status.accessPolicyState.rawValue)")
      print("NONINTERACTIVE=\(status.nonInteractiveSigningProven ? "yes" : "no")")
      print("RECOVERY=\(status.recoveryRequired?.rawValue ?? "none")")
      print(
        "RELEASE_VALIDATION=\(status.releaseIdentityValidation.validationPassed ? "yes" : "no")")
      print("DEVELOPER_ID=\(status.releaseIdentityValidation.developerIDAvailable ? "yes" : "no")")
    case "interrupt-rotation":
      _ = try coordinator.prepareRotationTransaction(interruptAt: .newKeyCreated)
      print("INTERRUPTED=yes")
    case "resume-rotation":
      let status = try await coordinator.resumeInterruptedRotation(auditActor: .testFixture)
      print(status.rotationTransactionState == nil ? "ROTATION_RESUMED=yes" : "ROTATION_RESUMED=no")
    case "export-anchors":
      guard CommandLine.arguments.count >= 4 else { Foundation.exit(64) }
      let output = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
      let count = try coordinator.exportPublicTrustAnchors(to: output)
      print("ANCHORS_EXPORTED=\(count)")
    case "import-anchors":
      guard CommandLine.arguments.count >= 4 else { Foundation.exit(64) }
      let file = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: false)
      let count = try coordinator.importPublicTrustAnchors(from: file)
      print("ANCHORS_IMPORTED=\(count)")
    case "reset":
      try coordinator.resetAuditSigningConfiguration(confirm: true)
      print("RESET=yes")
    default:
      FileHandle.standardError.write(Data("unknown command\n".utf8))
      Foundation.exit(64)
    }
  }
}
