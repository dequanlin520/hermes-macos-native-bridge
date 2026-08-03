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

    XCTAssertTrue(install.contains(#"APP_TARGET="$HOME/Applications/$APP_NAME""#))
    XCTAssertTrue(install.contains(#"[[ "$APP_TARGET" != /Applications/* ]]"#))
    XCTAssertTrue(uninstall.contains(#"[[ "$APP_TARGET" != /Applications/* ]]"#))
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

    XCTAssertTrue(install.contains("[[ -L \"$directory\" ]]"))
    XCTAssertTrue(uninstall.contains("[[ -d \"$APP_TARGET\" && ! -L \"$APP_TARGET\" ]]"))
  }

  func testBundleIdentifierVersionAndStagedMetadataAreValidated() throws {
    let install = try script("Scripts/native/install-hermes-bridge-app.zsh")
    let integration = try script("Scripts/integration/m4-003-shortcuts-runtime-discovery.zsh")

    XCTAssertTrue(install.contains("EXPECTED_BUNDLE_ID=\"com.hermes.bridge.app\""))
    XCTAssertTrue(install.contains("EXPECTED_VERSION=\"0.1.0-rc.1\""))
    XCTAssertTrue(install.contains("validate_staged_app"))
    XCTAssertTrue(install.contains("validate_installed_app"))
    XCTAssertTrue(install.contains("plutil -lint"))
    XCTAssertTrue(integration.contains("APP_INTENTS_METADATA_PRESENT"))
  }

  func testStandaloneDittocopyAndLaunchAgentRewriteAreImplemented() throws {
    let install = try script("Scripts/native/install-hermes-bridge-app.zsh")

    XCTAssertTrue(install.contains("replace_directory_with_ditto"))
    XCTAssertTrue(install.contains("/usr/bin/ditto \"$src\" \"$tmp\""))
    XCTAssertTrue(install.contains("mv \"$tmp\" \"$dest\""))
    XCTAssertTrue(install.contains("write_launch_agent"))
    XCTAssertTrue(install.contains("ProgramArguments"))
  }

  func testExactPathUninstallIsIdempotentAndPreservesUnrelatedApps() throws {
    let uninstall = try script("Scripts/native/uninstall-hermes-bridge-app.zsh")

    XCTAssertTrue(uninstall.contains("APP_TARGET=\"$HOME/Applications/$APP_NAME\""))
    XCTAssertTrue(uninstall.contains("refusing to remove unexpected app bundle"))
    XCTAssertTrue(uninstall.contains("rm -rf \"$APP_TARGET\""))
    XCTAssertFalse(uninstall.contains("rm -rf \"$HOME/Applications\""))
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

    XCTAssertTrue(uninstall.contains("pid_for_exact_app"))
    XCTAssertTrue(uninstall.contains("launchctl bootout \"$SERVICE_DOMAIN/$LABEL\""))
    XCTAssertTrue(uninstall.contains("kill -TERM"))
    XCTAssertTrue(integration.contains("RESIDUAL_APP_PROCESS"))
    XCTAssertTrue(integration.contains("M4-003 VERDICT: CONDITIONAL GO"))
    XCTAssertTrue(integration.contains("M4-003 VERDICT: NO-GO"))
  }
}
