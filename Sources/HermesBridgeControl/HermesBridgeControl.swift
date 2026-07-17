import Foundation
import HermesBridgeControlCore

@main
struct HermesBridgeControlCLI {
  static func main() async {
    let result = await HermesBridgeControlRunner().run(
      arguments: Array(CommandLine.arguments.dropFirst())
    )
    if !result.stdout.isEmpty {
      print(result.stdout, terminator: "")
    }
    if !result.stderr.isEmpty {
      fputs(result.stderr, stderr)
    }
    exit(result.exitCode.rawValue)
  }
}
