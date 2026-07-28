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
    .library(
      name: "HermesOnboarding",
      targets: ["HermesOnboarding"]
    ),
    .library(
      name: "HermesRecovery",
      targets: ["HermesRecovery"]
    ),
    .library(
      name: "HermesUpdate",
      targets: ["HermesUpdate"]
    ),
    .library(
      name: "HermesNotifications",
      targets: ["HermesNotifications"]
    ),
    .library(
      name: "HermesTimeline",
      targets: ["HermesTimeline"]
    ),
    .library(
      name: "HermesSearch",
      targets: ["HermesSearch"]
    ),
    .library(
      name: "HermesFeedback",
      targets: ["HermesFeedback"]
    ),
    .library(
      name: "HermesPrivacy",
      targets: ["HermesPrivacy"]
    ),
    .library(
      name: "HermesPolicy",
      targets: ["HermesPolicy"]
    ),
    .library(
      name: "HermesAdministration",
      targets: ["HermesAdministration"]
    ),
    .library(
      name: "HermesCompliance",
      targets: ["HermesCompliance"]
    ),
    .library(
      name: "HermesHealth",
      targets: ["HermesHealth"]
    ),
    .library(
      name: "HermesOperations",
      targets: ["HermesOperations"]
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
      dependencies: ["HermesBridgeXPC", "HermesRuntimeFoundation", "HermesTimeline"]
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
      dependencies: ["HermesRuntimeFoundation", "HermesTimeline"]
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
      dependencies: ["HermesRecovery", "HermesRuntimeFoundation"]
    ),
    .target(
      name: "HermesOnboarding",
      dependencies: ["HermesBridgeXPC", "HermesRecovery", "HermesRuntimeFoundation"]
    ),
    .target(
      name: "HermesRecovery",
      dependencies: ["HermesBridgeServiceManager", "HermesBridgeXPC", "HermesRuntimeFoundation"]
    ),
    .target(
      name: "HermesUpdate",
      dependencies: ["HermesBridgeXPC", "HermesRuntimeFoundation"]
    ),
    .target(
      name: "HermesNotifications",
      dependencies: ["HermesRuntimeFoundation"]
    ),
    .target(
      name: "HermesTimeline",
      dependencies: ["HermesRuntimeFoundation"]
    ),
    .target(
      name: "HermesSearch",
      dependencies: [
        "HermesDiagnostics", "HermesLogsViewer", "HermesNotifications",
        "HermesRuntimeFoundation", "HermesTimeline",
      ]
    ),
    .target(
      name: "HermesFeedback"
    ),
    .target(
      name: "HermesPrivacy"
    ),
    .target(
      name: "HermesPolicy"
    ),
    .target(
      name: "HermesAdministration",
      dependencies: ["HermesPolicy", "HermesPrivacy", "HermesUpdate"]
    ),
    .target(
      name: "HermesCompliance",
      dependencies: ["HermesPolicy", "HermesPrivacy", "HermesUpdate"]
    ),
    .target(
      name: "HermesHealth"
    ),
    .target(
      name: "HermesOperations"
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
        "HermesAdministration", "HermesCompliance", "HermesDashboard", "HermesDiagnostics", "HermesFeedback", "HermesHealth",
        "HermesOperations",
        "HermesLogsViewer", "HermesMenuBar", "HermesNotifications", "HermesOnboarding", "HermesRecovery", "HermesSearch",
        "HermesPolicy", "HermesPrivacy", "HermesSettings", "HermesTimeline", "HermesUpdate",
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
      dependencies: ["HermesDashboard", "HermesRuntimeFoundation", "HermesTimeline"]
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
      name: "HermesOnboardingTests",
      dependencies: ["HermesOnboarding", "HermesBridgeApp"]
    ),
    .testTarget(
      name: "HermesBridgeAppTests",
      dependencies: [
        "HermesBridgeApp", "HermesBridgeAppAcceptanceSupport", "HermesBridgeService",
        "HermesAdministration", "HermesBridgeXPC", "HermesCompliance", "HermesDashboard", "HermesDiagnostics", "HermesFeedback", "HermesHealth", "HermesLogsViewer",
        "HermesOperations",
        "HermesMenuBar", "HermesNotifications", "HermesPolicy", "HermesRecovery",
        "HermesRuntimeFoundation", "HermesPrivacy", "HermesSearch", "HermesSettings", "HermesUpdate",
      ]
    ),
    .testTarget(
      name: "HermesNotificationsTests",
      dependencies: ["HermesNotifications", "HermesRuntimeFoundation"]
    ),
    .testTarget(
      name: "HermesTimelineTests",
      dependencies: ["HermesBridgeApp", "HermesDashboard", "HermesNotifications", "HermesTimeline"]
    ),
    .testTarget(
      name: "HermesSearchTests",
      dependencies: [
        "HermesBridgeApp", "HermesDashboard", "HermesDiagnostics", "HermesLogsViewer",
        "HermesNotifications", "HermesRuntimeFoundation", "HermesSearch", "HermesTimeline",
      ]
    ),
    .testTarget(
      name: "HermesFeedbackTests",
      dependencies: ["HermesBridgeApp", "HermesFeedback"]
    ),
    .testTarget(
      name: "HermesPrivacyTests",
      dependencies: ["HermesBridgeApp", "HermesPrivacy", "HermesRuntimeFoundation"]
    ),
    .testTarget(
      name: "HermesPolicyTests",
      dependencies: ["HermesBridgeApp", "HermesPolicy", "HermesRuntimeFoundation"]
    ),
    .testTarget(
      name: "HermesUpdateTests",
      dependencies: ["HermesBridgeApp", "HermesBridgeXPC", "HermesUpdate", "HermesRuntimeFoundation"]
    ),
    .testTarget(
      name: "HermesAdministrationTests",
      dependencies: ["HermesAdministration", "HermesBridgeApp", "HermesPolicy", "HermesPrivacy", "HermesRuntimeFoundation", "HermesUpdate"]
    ),
    .testTarget(
      name: "HermesComplianceTests",
      dependencies: ["HermesBridgeApp", "HermesCompliance", "HermesPolicy", "HermesPrivacy", "HermesRuntimeFoundation", "HermesUpdate"]
    ),
    .testTarget(
      name: "HermesHealthTests",
      dependencies: ["HermesBridgeApp", "HermesHealth", "HermesRuntimeFoundation"]
    ),
    .testTarget(
      name: "HermesOperationsTests",
      dependencies: ["HermesBridgeApp", "HermesOperations", "HermesRuntimeFoundation"]
    ),
    .testTarget(
      name: "HermesRecoveryTests",
      dependencies: [
        "HermesBridgeApp", "HermesBridgeServiceManager", "HermesBridgeXPC", "HermesRecovery",
        "HermesRuntimeFoundation",
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
    .testTarget(
      name: "HermesReleaseTests",
      dependencies: []
    ),
    .testTarget(
      name: "HermesInstallerTests",
      dependencies: ["HermesBridgeServiceManager"]
    ),
  ]
)
