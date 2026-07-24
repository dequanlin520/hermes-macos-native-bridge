// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "HermesMacOSNativeBridge",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(
      name: "HermesRuntimeFoundation",
      targets: ["HermesRuntimeFoundation"]
    ),
    .library(
      name: "HermesBridgeXPC",
      targets: ["HermesBridgeXPC"]
    ),
    .library(
      name: "HermesBridgeServiceManager",
      targets: ["HermesBridgeServiceManager"]
    ),
    .library(
      name: "HermesAppIntents",
      targets: ["HermesAppIntents"]
    ),
    .library(
      name: "HermesBridgeMenuBar",
      targets: ["HermesBridgeMenuBar"]
    ),
    .library(
      name: "HermesDashboard",
      targets: ["HermesDashboard"]
    ),
    .library(
      name: "HermesLogsViewer",
      targets: ["HermesLogsViewer"]
    ),
    .library(
      name: "HermesSettings",
      targets: ["HermesSettings"]
    ),
    .executable(
      name: "HermesBridgeService",
      targets: ["HermesBridgeServiceExecutable"]
    ),
    .executable(
      name: "HermesBridgeServiceLifecycle",
      targets: ["HermesBridgeServiceLifecycle"]
    ),
    .executable(
      name: "HermesBridgeControl",
      targets: ["HermesBridgeControl"]
    ),
    .executable(
      name: "HermesAppIntentsHost",
      targets: ["HermesAppIntentsHost"]
    ),
    .executable(
      name: "HermesBridgeApp",
      targets: ["HermesBridgeApp"]
    ),
    .executable(
      name: "HermesMenuBar",
      targets: ["HermesMenuBar"]
    ),
    .executable(
      name: "M8001ReleaseCandidateAcceptance",
      targets: ["M8001ReleaseCandidateAcceptance"]
    ),
  ],
  targets: [
    .target(
      name: "HermesRuntimeFoundation"
    ),
    .target(
      name: "HermesBridgeXPC",
      dependencies: ["HermesRuntimeFoundation"]
    ),
    .target(
      name: "HermesBridgeService",
      dependencies: ["HermesBridgeXPC", "HermesRuntimeFoundation"]
    ),
    .target(
      name: "HermesBridgeServiceManager",
      dependencies: ["HermesBridgeService", "HermesBridgeXPC"]
    ),
    .executableTarget(
      name: "HermesBridgeServiceExecutable",
      dependencies: ["HermesBridgeService"]
    ),
    .executableTarget(
      name: "HermesBridgeServiceLifecycle",
      dependencies: ["HermesBridgeServiceManager"]
    ),
    .target(
      name: "HermesBridgeControlCore",
      dependencies: ["HermesBridgeServiceManager", "HermesBridgeXPC", "HermesRuntimeFoundation"]
    ),
    .target(
      name: "HermesAppIntents",
      dependencies: ["HermesBridgeServiceManager", "HermesBridgeXPC", "HermesRuntimeFoundation"]
    ),
    .target(
      name: "HermesBridgeMenuBar",
      dependencies: [
        "HermesAppIntents", "HermesBridgeControlCore", "HermesBridgeServiceManager",
        "HermesBridgeXPC", "HermesRuntimeFoundation",
      ]
    ),
    .target(
      name: "HermesDashboard",
      dependencies: ["HermesRuntimeFoundation"]
    ),
    .target(
      name: "HermesLogsViewer",
      dependencies: ["HermesRuntimeFoundation"]
    ),
    .target(
      name: "HermesSettings"
    ),
    .executableTarget(
      name: "HermesBridgeControl",
      dependencies: ["HermesBridgeControlCore"]
    ),
    .executableTarget(
      name: "HermesAppIntentsHost",
      dependencies: ["HermesAppIntents"]
    ),
    .executableTarget(
      name: "HermesBridgeApp",
      dependencies: ["HermesAppIntents", "HermesBridgeMenuBar", "HermesRuntimeFoundation"]
    ),
    .executableTarget(
      name: "HermesMenuBar",
      dependencies: ["HermesRuntimeFoundation"]
    ),
    .executableTarget(
      name: "M6001AuditFixture",
      dependencies: ["HermesRuntimeFoundation"]
    ),
    .executableTarget(
      name: "M6003AuditSigningFixture",
      dependencies: ["HermesRuntimeFoundation"]
    ),
    .executableTarget(
      name: "M6004AuditSigningOperationsFixture",
      dependencies: ["HermesRuntimeFoundation"]
    ),
    .target(
      name: "HermesReleaseCandidateAcceptance",
      dependencies: [
        "HermesBridgeMenuBar", "HermesBridgeService", "HermesBridgeServiceManager",
        "HermesBridgeXPC", "HermesRuntimeFoundation",
      ]
    ),
    .executableTarget(
      name: "M8001ReleaseCandidateAcceptance",
      dependencies: ["HermesReleaseCandidateAcceptance"]
    ),
    .testTarget(
      name: "HermesRuntimeFoundationTests",
      dependencies: ["HermesRuntimeFoundation"],
      exclude: ["Fixtures"]
    ),
    .testTarget(
      name: "HermesBridgeXPCTests",
      dependencies: ["HermesBridgeXPC", "HermesRuntimeFoundation"]
    ),
    .testTarget(
      name: "HermesBridgeServiceTests",
      dependencies: ["HermesBridgeService", "HermesBridgeXPC", "HermesRuntimeFoundation"]
    ),
    .testTarget(
      name: "HermesBridgeServiceManagerTests",
      dependencies: ["HermesBridgeServiceManager", "HermesBridgeService", "HermesBridgeXPC"]
    ),
    .testTarget(
      name: "HermesBridgeControlTests",
      dependencies: ["HermesBridgeControlCore"]
    ),
    .testTarget(
      name: "HermesAppIntentsTests",
      dependencies: ["HermesAppIntents", "HermesBridgeXPC", "HermesRuntimeFoundation"]
    ),
    .testTarget(
      name: "HermesBridgeMenuBarTests",
      dependencies: ["HermesBridgeMenuBar"]
    ),
    .testTarget(
      name: "HermesMenuBarTests",
      dependencies: ["HermesMenuBar", "HermesRuntimeFoundation"]
    ),
    .testTarget(
      name: "HermesDashboardTests",
      dependencies: ["HermesDashboard", "HermesRuntimeFoundation"]
    ),
    .testTarget(
      name: "HermesLogsViewerTests",
      dependencies: ["HermesLogsViewer", "HermesRuntimeFoundation"]
    ),
    .testTarget(
      name: "HermesSettingsTests",
      dependencies: ["HermesSettings"]
    ),
    .testTarget(
      name: "M4003ScriptTests",
      dependencies: []
    ),
    .testTarget(
      name: "M5004SandboxedBookmarkLifecycleTests",
      dependencies: []
    ),
    .testTarget(
      name: "M6001ScriptTests",
      dependencies: []
    ),
    .testTarget(
      name: "HermesReleaseCandidateAcceptanceTests",
      dependencies: ["HermesReleaseCandidateAcceptance"]
    ),
    .testTarget(
      name: "M8002ReleasePipelineTests",
      dependencies: []
    ),
  ]
)
