import HermesBridgeControlCore
import HermesBridgeMenuBar
import HermesBridgeServiceManager
import HermesBridgeXPC
import HermesRuntimeFoundation
import XCTest

final class HermesBridgeMenuBarTests: XCTestCase {
  func testInitialLoadingState() async {
    let viewModel = HermesBridgeMenuBarViewModel(environment: .fake(serviceStatus: .starting))

    let state = await viewModel.state
    XCTAssertEqual(state.serviceStatus, .loading)
  }

  func testHealthyState() async throws {
    let viewModel = HermesBridgeMenuBarViewModel(environment: .fake(serviceStatus: .runningHealthy))

    await viewModel.load()
    let state = await viewModel.state

    XCTAssertEqual(state.serviceStatus, .runningHealthy)
    XCTAssertTrue(state.healthy)
    XCTAssertTrue(state.protocolCompatible)
    XCTAssertEqual(state.enabledBindingCount, 1)
    XCTAssertTrue(state.capabilities.contains("bindingDiscovery"))
  }

  func testUnavailableState() async {
    let viewModel = HermesBridgeMenuBarViewModel(environment: .fake(serviceStatus: .notInstalled))

    await viewModel.load()
    let state = await viewModel.state

    XCTAssertEqual(state.serviceStatus, .unavailable)
    XCTAssertFalse(state.running)
  }

  func testProtocolIncompatibleState() async {
    let viewModel = HermesBridgeMenuBarViewModel(
      environment: .fake(serviceStatus: .runningHealthy, version: .init(major: 2, minor: 0))
    )

    await viewModel.load()

    let state = await viewModel.state
    XCTAssertEqual(state.serviceStatus, .protocolIncompatible)
  }

  func testStartRestartDoctorActions() async {
    let service = FakeServiceManager(status: .installedStopped)
    let doctor = FakeDoctor()
    let viewModel = HermesBridgeMenuBarViewModel(
      environment: .fake(service: service, doctor: doctor)
    )

    let start = await viewModel.startService()
    let restart = await viewModel.restartService()
    let doctorResult = await viewModel.runDoctor()

    XCTAssertTrue(start.succeeded)
    XCTAssertTrue(restart.succeeded)
    XCTAssertTrue(doctorResult.succeeded)
    let startCount = await service.startCount
    let restartCount = await service.restartCount
    let doctorCount = await doctor.count
    XCTAssertEqual(startCount, 1)
    XCTAssertEqual(restartCount, 1)
    XCTAssertEqual(doctorCount, 1)
  }

  func testRefreshCancellation() async {
    let viewModel = HermesBridgeMenuBarViewModel(environment: .fake(serviceStatus: .runningHealthy))

    await viewModel.refresh()
    await viewModel.cancelRefresh()

    let state = await viewModel.state
    XCTAssertEqual(state.serviceStatus, .runningHealthy)
  }

  func testRecentRequestRedactionAndNoResultBody() async {
    let viewModel = HermesBridgeMenuBarViewModel(environment: .fake(serviceStatus: .runningHealthy))

    await viewModel.load()
    let rendered = String(describing: await viewModel.state.recentRequests)

    XCTAssertFalse(rendered.contains("secret prompt"))
    XCTAssertFalse(rendered.contains("backend-token"))
    XCTAssertFalse(rendered.contains("raw result body"))
    XCTAssertFalse(rendered.contains("/Users/"))
  }
}

extension HermesBridgeMenuBarEnvironment {
  fileprivate static func fake(
    serviceStatus: HermesBridgeServiceStatus = .runningHealthy,
    version: HermesBridgeProtocolVersion = .current
  ) -> HermesBridgeMenuBarEnvironment {
    fake(service: FakeServiceManager(status: serviceStatus), xpc: FakeXPC(version: version))
  }

  fileprivate static func fake(
    service: FakeServiceManager = FakeServiceManager(status: .runningHealthy),
    xpc: FakeXPC = FakeXPC(),
    doctor: FakeDoctor = FakeDoctor()
  ) -> HermesBridgeMenuBarEnvironment {
    HermesBridgeMenuBarEnvironment(
      serviceManager: service,
      xpcClient: xpc,
      requestLister: FakeLister(),
      doctor: doctor
    )
  }
}

private actor FakeServiceManager: HermesBridgeMenuBarServiceManaging {
  private let statusValue: HermesBridgeServiceStatus
  private(set) var startCount = 0
  private(set) var restartCount = 0

  init(status: HermesBridgeServiceStatus) {
    self.statusValue = status
  }

  func status() async -> HermesBridgeServiceStatus {
    statusValue
  }

  func start() async -> HermesBridgeMenuBarActionResult {
    startCount += 1
    return HermesBridgeMenuBarActionResult(succeeded: true, safeMessage: "start requested")
  }

  func restart() async -> HermesBridgeMenuBarActionResult {
    restartCount += 1
    return HermesBridgeMenuBarActionResult(succeeded: true, safeMessage: "restart completed")
  }
}

private actor FakeXPC: HermesBridgeMenuBarXPCClient {
  private let version: HermesBridgeProtocolVersion

  init(version: HermesBridgeProtocolVersion = .current) {
    self.version = version
  }

  func protocolVersion() async throws -> HermesBridgeProtocolVersionPayload {
    HermesBridgeProtocolVersionPayload(version: version)
  }

  func capabilities() async throws -> HermesBridgeCapabilitiesPayload {
    HermesBridgeCapabilitiesPayload(capabilities: HermesBridgeCapability.allCases)
  }

  func listEnabledBindings() async throws -> HermesBridgeBindingListPayload {
    try HermesBridgeBindingListPayload(bindings: [
      HermesBridgeBindingSummary(
        bindingID: try HermesRequestBindingID(rawValue: "binding:v1:test"),
        localizedDisplayName: "Test",
        safeLocalizedDescription: "Safe",
        maximumPromptBytes: 128,
        approvalPolicy: "explicit",
        enabled: true
      )
    ])
  }

  func close() async {}
}

private struct FakeLister: HermesBridgeMenuBarRequestListing {
  func recentRequests() async throws -> [HermesBridgeMenuBarRequestSummary] {
    [
      HermesBridgeMenuBarRequestSummary(
        requestID: "hrq_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        bindingID: "binding:v1:test",
        lifecycleState: "completed",
        resultAvailable: true,
        failureCode: nil
      )
    ]
  }
}

private actor FakeDoctor: HermesBridgeMenuBarDoctorRunning {
  private(set) var count = 0

  func runDoctor() async -> HermesBridgeMenuBarActionResult {
    count += 1
    return HermesBridgeMenuBarActionResult(succeeded: true, safeMessage: "doctor pass")
  }
}
