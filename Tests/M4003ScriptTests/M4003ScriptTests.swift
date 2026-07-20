import Foundation
import XCTest

final class M4003ScriptTests: XCTestCase {
  private var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func script(_ relativePath: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
  }

  func testUserApplicationsDestinationIsFixedAndSystemApplicationsRejected() throws {
    let install = try script("Scripts/native/install-hermes-bridge-app.zsh")
    let uninstall = try script("Scripts/native/uninstall-hermes-bridge-app.zsh")

    XCTAssertTrue(install.contains(#""${HOME}/Applications""#))
    XCTAssertTrue(install.contains(#""$root" != "/Applications""#))
    XCTAssertTrue(uninstall.contains(#""$root" != "/Applications""#))
  }

  func testMissingExplicitFlagsAreRejected() throws {
    let install = try script("Scripts/native/install-hermes-bridge-app.zsh")
    let uninstall = try script("Scripts/native/uninstall-hermes-bridge-app.zsh")
    let integration = try script("Scripts/integration/m4-003-shortcuts-runtime-discovery.zsh")

    XCTAssertTrue(install.contains("--install-user-app"))
    XCTAssertTrue(install.contains("exit 2"))
    XCTAssertTrue(uninstall.contains("--uninstall-user-app"))
    XCTAssertTrue(uninstall.contains("exit 2"))
    XCTAssertTrue(integration.contains("--install-user-app --uninstall-user-app"))
  }

  func testSymlinkDestinationRootIsRejected() throws {
    let install = try script("Scripts/native/install-hermes-bridge-app.zsh")
    let uninstall = try script("Scripts/native/uninstall-hermes-bridge-app.zsh")

    XCTAssertTrue(install.contains("[[ -L \"$root\" ]]"))
    XCTAssertTrue(uninstall.contains("[[ ! -L \"$root\" ]]"))
  }

  func testBundleIdentifierMetadataAndSignatureAreValidated() throws {
    let install = try script("Scripts/native/install-hermes-bridge-app.zsh")
    let integration = try script("Scripts/integration/m4-003-shortcuts-runtime-discovery.zsh")

    XCTAssertTrue(install.contains("EXPECTED_BUNDLE_ID=\"com.hermes.bridge.app\""))
    XCTAssertTrue(install.contains("validate_bundle_id"))
    XCTAssertTrue(install.contains("validate_expected_metadata"))
    XCTAssertTrue(install.contains("codesign --verify --deep --strict"))
    XCTAssertTrue(integration.contains("APP_INTENTS_METADATA_PRESENT"))
  }

  func testAtomicInstallAndBoundedBackupAreImplemented() throws {
    let install = try script("Scripts/native/install-hermes-bridge-app.zsh")

    XCTAssertTrue(install.contains("install_atomically"))
    XCTAssertTrue(install.contains("cp -R \"$src\" \"$tmp\""))
    XCTAssertTrue(install.contains("mv \"$tmp\" \"$dest\""))
    XCTAssertTrue(install.contains("last-backup-path.txt"))
    XCTAssertTrue(install.contains("head -n -3"))
  }

  func testExactPathUninstallIsIdempotentAndPreservesUnrelatedApps() throws {
    let uninstall = try script("Scripts/native/uninstall-hermes-bridge-app.zsh")

    XCTAssertTrue(uninstall.contains("installed_app_path"))
    XCTAssertTrue(uninstall.contains("refusing to remove unexpected bundle identifier"))
    XCTAssertTrue(uninstall.contains("rm -rf \"$dest\""))
    XCTAssertFalse(uninstall.contains("rm -rf \"$(user_app_root)\""))
  }

  func testNoKillallPkillPromptSubmissionOrShortcutModification() throws {
    let paths = [
      "Scripts/native/install-hermes-bridge-app.zsh",
      "Scripts/native/uninstall-hermes-bridge-app.zsh",
      "Scripts/integration/m4-003-shortcuts-runtime-discovery.zsh",
    ]
    for path in paths {
      let contents = try script(path)
      XCTAssertFalse(contents.contains("killall"), path)
      XCTAssertFalse(contents.contains("pkill"), path)
      XCTAssertFalse(contents.contains("submitPrompt"), path)
      XCTAssertFalse(contents.contains("shortcuts run"), path)
      XCTAssertFalse(contents.contains("shortcuts import"), path)
    }
  }

  func testBoundedIndexingWaitAndEvidenceCaptureArePresent() throws {
    let integration = try script("Scripts/integration/m4-003-shortcuts-runtime-discovery.zsh")

    XCTAssertTrue(integration.contains("INDEXING_WAIT_SECONDS=20"))
    XCTAssertTrue(integration.contains("sleep \"$INDEXING_WAIT_SECONDS\""))
    XCTAssertTrue(integration.contains("prove_launchservices"))
    XCTAssertTrue(integration.contains("/usr/bin/shortcuts list"))
    XCTAssertTrue(integration.contains("USER_SHORTCUTS_MODIFIED=no"))
  }

  func testResidualProcessCleanupAndMachineReadableResultArePresent() throws {
    let integration = try script("Scripts/integration/m4-003-shortcuts-runtime-discovery.zsh")
    let uninstall = try script("Scripts/native/uninstall-hermes-bridge-app.zsh")

    XCTAssertTrue(uninstall.contains("tell application id"))
    XCTAssertTrue(uninstall.contains("kill -TERM"))
    XCTAssertTrue(integration.contains("RESIDUAL_APP_PROCESS"))
    XCTAssertTrue(integration.contains("M4-003 VERDICT: CONDITIONAL GO"))
    XCTAssertTrue(integration.contains("M4-003 VERDICT: NO-GO"))
  }
}
