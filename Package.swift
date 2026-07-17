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
    .executable(
      name: "HermesBridgeService",
      targets: ["HermesBridgeServiceExecutable"]
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
    .executableTarget(
      name: "HermesBridgeServiceExecutable",
      dependencies: ["HermesBridgeService"]
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
  ]
)
