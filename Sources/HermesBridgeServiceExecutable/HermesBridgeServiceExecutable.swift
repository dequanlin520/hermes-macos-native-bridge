import Darwin
import Foundation
import HermesBridgeService

@main
struct HermesBridgeServiceExecutable {
  private static let signalSourceRegistry = SignalSourceRegistry()

  static func main() {
    exit(runHermesBridgeService())
  }

  private static func runHermesBridgeService() -> Int32 {
    do {
      let configuration = try HermesBridgeServiceMain.loadTrustedConfiguration(
        environment: ProcessInfo.processInfo.environment)
      let host = try HermesBridgeServiceHost(configuration: configuration)
      try host.start()
      print(HermesBridgeServiceMain.readinessMarker(serviceName: configuration.machServiceName))
      fflush(stdout)

      installSignalHandler(signalNumber: SIGTERM, host: host)
      installSignalHandler(signalNumber: SIGINT, host: host)
      host.waitUntilStopped()
      return 0
    } catch {
      fputs(HermesBridgeServiceMain.redactedStartupFailure(error) + "\n", stderr)
      return 1
    }
  }

  private static func installSignalHandler(signalNumber: Int32, host: HermesBridgeServiceHost) {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
    source.setEventHandler {
      Task {
        await host.stop()
      }
    }
    source.resume()
    signalSourceRegistry.append(source)
  }
}

private final class SignalSourceRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var sources: [DispatchSourceSignal] = []

  func append(_ source: DispatchSourceSignal) {
    lock.withLock {
      sources.append(source)
    }
  }
}
