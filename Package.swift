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
  ]
)
