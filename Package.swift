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
  ],
  targets: [
    .target(
      name: "HermesRuntimeFoundation"
    ),
    .target(
      name: "HermesBridgeXPC",
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
  ]
)
