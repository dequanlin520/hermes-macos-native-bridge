import Foundation
import HermesReleaseCandidateAcceptance

@main
struct M8001ReleaseCandidateAcceptance {
  static func main() async {
    do {
      let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      let environment = try HermesReleaseCandidateEnvironment(repositoryRoot: repo)
      let runner = HermesReleaseCandidateAcceptanceRunner(environment: environment)
      let result = try await runner.run()
      print("M8_001_RESULT=\(result.rawValue)")
      exit(result == .fail ? 1 : 0)
    } catch {
      fputs(
        "M8_001_RESULT=FAIL error=\(HermesReleaseCandidateAcceptanceRunner.redact(String(describing: error)))\n",
        stderr
      )
      exit(1)
    }
  }
}
