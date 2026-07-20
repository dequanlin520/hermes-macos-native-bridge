import Foundation
import XCTest

final class M6001ScriptTests: XCTestCase {
  private let scriptPath = "Scripts/integration/m6-001-permissions-audit.zsh"
  private let requiredKeys = [
    "PERMISSIONS_DOCTOR_PASSED",
    "NO_PERMISSION_PROMPT_TRIGGERED",
    "ACCESSIBILITY_STATE_REPORTED",
    "SCREEN_RECORDING_STATE_REPORTED",
    "SANDBOX_STATE_REPORTED",
    "FILE_AUTHORIZATION_STATE_REPORTED",
    "AUDIT_APPEND_PASSED",
    "AUDIT_ROTATION_PASSED",
    "AUDIT_EXPORT_PASSED",
    "AUDIT_CHECKSUM_VALID",
    "PROMPT_EXPOSED",
    "TOKEN_EXPOSED",
    "BOOKMARK_BYTES_EXPOSED",
    "ABSOLUTE_PATH_EXPOSED",
    "RESIDUAL_PROCESS",
    "M6_001_RESULT",
  ]

  func testScriptDeclaresFixedResultFileAndRequiredKeys() throws {
    let source = try String(contentsOfFile: scriptPath, encoding: .utf8)

    XCTAssertTrue(source.contains("OUTPUT_FILE=\"$ARTIFACT_DIR/result.txt\""))
    XCTAssertTrue(source.contains(">| \"$OUTPUT_FILE\""))
    XCTAssertTrue(source.contains("trap finalize EXIT"))
    XCTAssertTrue(source.contains("write_results()"))
    XCTAssertTrue(source.contains("-name '*.json' -o -name '*.jsonl' -o -name '*.txt'"))

    for key in requiredKeys {
      XCTAssertTrue(source.contains(key), key)
    }
  }

  func testResultWriterEmitsOneFinalValueForEveryRequiredKey() throws {
    let source = try String(contentsOfFile: scriptPath, encoding: .utf8)
    for key in requiredKeys {
      XCTAssertEqual(source.components(separatedBy: "print -r -- \"\(key)=").count - 1, 1, key)
    }

    XCTAssertTrue(source.contains("cat \"$OUTPUT_FILE\""))
    XCTAssertTrue(source.contains("[ \"$M6_001_RESULT\" = PASS ]"))
  }
}
