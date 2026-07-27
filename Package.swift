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
    .library(
      name: "HermesDiagnostics",
      targets: ["HermesDiagnostics"]
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
      targets: ["HermesBridgeAppExecutable"]
    ),
    .executable(
      name: "HermesBridgeAppAcceptanceHarness",
      targets: ["HermesBridgeAppAcceptanceHarness"]
    ),
    .executable(
      name: "HermesMenuBar",
      targets: ["HermesMenuBarExecutable"]
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
    .target(
      name: "HermesDiagnostics",
      dependencies: ["HermesRuntimeFoundation"]
    ),
    .executableTarget(
      name: "HermesBridgeControl",
      dependencies: ["HermesBridgeControlCore"]
    ),
    .executableTarget(
      name: "HermesAppIntentsHost",
      dependencies: ["HermesAppIntents"]
    ),
    .target(
      name: "HermesBridgeApp",
      dependencies: [
        "HermesBridgeXPC",
        "HermesDashboard", "HermesDiagnostics", "HermesLogsViewer", "HermesMenuBar",
        "HermesSettings",
      ]
    ),
    .executableTarget(
      name: "HermesBridgeAppExecutable",
      dependencies: ["HermesBridgeApp"]
    ),
    .target(
      name: "HermesBridgeAppAcceptanceSupport",
      dependencies: [
        "HermesBridgeApp", "HermesBridgeXPC", "HermesRuntimeFoundation",
      ],
      swiftSettings: [
        .define("HERMES_M11_003_ACCEPTANCE_SUPPORT")
      ]
    ),
    .executableTarget(
      name: "HermesBridgeAppAcceptanceHarness",
      dependencies: ["HermesBridgeApp", "HermesBridgeAppAcceptanceSupport"]
    ),
    .target(
      name: "HermesMenuBar",
      dependencies: ["HermesRuntimeFoundation"]
    ),
    .executableTarget(
      name: "HermesMenuBarExecutable",
      dependencies: ["HermesMenuBar", "HermesRuntimeFoundation"]
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
      name: "HermesDiagnosticsTests",
      dependencies: ["HermesDiagnostics", "HermesRuntimeFoundation"]
    ),
    .testTarget(
      name: "HermesBridgeAppTests",
      dependencies: [
        "HermesBridgeApp", "HermesBridgeAppAcceptanceSupport", "HermesBridgeService",
        "HermesBridgeXPC", "HermesDashboard", "HermesDiagnostics", "HermesLogsViewer",
        "HermesMenuBar", "HermesRuntimeFoundation", "HermesSettings",
      ]
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
