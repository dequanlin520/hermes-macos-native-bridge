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
    .executable(
      name: "HermesBridgeService",
      targets: ["HermesBridgeServiceExecutable"]
    ),
    .executable(
      name: "HermesBridgeServiceLifecycle",
      targets: ["HermesBridgeServiceLifecycle"]
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
  ]
)
