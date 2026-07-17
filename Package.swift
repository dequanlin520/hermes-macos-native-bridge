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
    )
  ],
  targets: [
    .target(
      name: "HermesRuntimeFoundation"
    ),
    .testTarget(
      name: "HermesRuntimeFoundationTests",
      dependencies: ["HermesRuntimeFoundation"],
      exclude: ["Fixtures"]
    ),
  ]
)
