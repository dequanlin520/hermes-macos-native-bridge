#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/artifacts/m5-003"
FIXTURE_DIR="$ARTIFACT_DIR/AuthorizedRootUIFixture"
APP_NAME="Hermes Bridge.app"
APP_BUNDLE="$ARTIFACT_DIR/${APP_NAME}"
OUTPUT_FILE="$ARTIFACT_DIR/result.txt"
MANUAL_MODE=no

for arg in "$@"; do
  case "$arg" in
    --manual-nsopenpanel-validation)
      MANUAL_MODE=yes
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

APP_BUILD_PASSED=no
NSOPENPANEL_IMPLEMENTED=no
DIRECTORY_ONLY_SELECTION_VALIDATED=no
BOOKMARK_CREATED=no
ROOT_REGISTERED_OVER_XPC=no
ROOT_LISTED_REDACTED=no
DEACTIVATE_REACTIVATE_PASSED=no
ROOT_REMOVAL_PASSED=no
ABSOLUTE_PATH_EXPOSED=no
BOOKMARK_BYTES_EXPOSED=no
FILE_CONTENT_EXPOSED=no
SECURITY_SCOPED_RUNTIME_PROVEN=no
RESIDUAL_APP_PROCESS=yes
M5_003_RESULT=FAIL

cleanup() {
  pkill -x HermesBridgeApp >/dev/null 2>&1 || true
  pkill -x "Hermes Bridge" >/dev/null 2>&1 || true
  if pgrep -x HermesBridgeApp >/dev/null 2>&1 || pgrep -x "Hermes Bridge" >/dev/null 2>&1; then
    RESIDUAL_APP_PROCESS=yes
  else
    RESIDUAL_APP_PROCESS=no
  fi
}
trap cleanup EXIT

cd "$ROOT_DIR"
rm -rf "$ARTIFACT_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" \
  "$FIXTURE_DIR/Sources/AuthorizedRootUIFixture"

xcodebuild -scheme HermesBridgeApp -destination 'platform=macOS' build >/dev/null
swift build --product HermesBridgeApp >/dev/null
cp ".build/debug/HermesBridgeApp" "$APP_BUNDLE/Contents/MacOS/HermesBridgeApp"
cp "Packaging/HermesBridgeApp/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
chmod 755 "$APP_BUNDLE/Contents/MacOS/HermesBridgeApp"
codesign --force --sign - "$APP_BUNDLE" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP_BUNDLE/Contents/Info.plist" >/dev/null
APP_BUILD_PASSED=yes

if otool -L "$APP_BUNDLE/Contents/MacOS/HermesBridgeApp" | grep -q AppKit \
  && rg -q 'NSOpenPanel|NSOpenPanelHermesAuthorizedRootSelector' Sources/HermesBridgeMenuBar Sources/HermesBridgeApp
then
  NSOPENPANEL_IMPLEMENTED=yes
fi

if [[ "$MANUAL_MODE" == "yes" ]]; then
  mkdir -p "$ARTIFACT_DIR/authorized-root"
  echo "Manual validation mode."
  echo "Artifact folder prepared for user selection."
  echo "Use Hermes Bridge.app > Authorized Folders > Add Folder and choose the prepared artifact folder."
  open "$APP_BUNDLE"
  echo "APP_BUILD_PASSED=${APP_BUILD_PASSED}"
  echo "NSOPENPANEL_IMPLEMENTED=${NSOPENPANEL_IMPLEMENTED}"
  echo "DIRECTORY_ONLY_SELECTION_VALIDATED=manual"
  echo "M5_003_RESULT=PARTIAL"
  exit 0
fi

cat > "$FIXTURE_DIR/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AuthorizedRootUIFixture",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(path: "$ROOT_DIR")
  ],
  targets: [
    .executableTarget(
      name: "AuthorizedRootUIFixture",
      dependencies: [
        .product(name: "HermesBridgeMenuBar", package: "hermes-macos-native-bridge"),
        .product(name: "HermesBridgeXPC", package: "hermes-macos-native-bridge"),
        .product(name: "HermesRuntimeFoundation", package: "hermes-macos-native-bridge"),
      ]
    )
  ]
)
EOF

cat > "$FIXTURE_DIR/Sources/AuthorizedRootUIFixture/main.swift" <<'EOF'
import Foundation
import HermesBridgeMenuBar
import HermesBridgeXPC
import HermesRuntimeFoundation

final class Fixture: NSObject, NSXPCListenerDelegate {
  let listener = NSXPCListener.anonymous()
  let service: HermesBridgeXPCService

  init(service: HermesBridgeXPCService) {
    self.service = service
    super.init()
    listener.delegate = self
    listener.resume()
  }

  func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    connection.exportedInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
    connection.exportedObject = service
    connection.resume()
    return true
  }

  func close() {
    service.invalidate()
    listener.invalidate()
  }
}

func result(_ value: Bool) -> String { value ? "yes" : "no" }

let artifactRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let selectedRoot = artifactRoot.appendingPathComponent("authorized-root", isDirectory: true)
try FileManager.default.createDirectory(at: selectedRoot, withIntermediateDirectories: true)
try "file-secret".write(
  to: selectedRoot.appendingPathComponent("sample.txt"),
  atomically: true,
  encoding: .utf8
)

let panelConfig = HermesAuthorizedRootOpenPanelConfiguration.newDirectory()
let directoryOnly = panelConfig.canChooseDirectories
  && !panelConfig.canChooseFiles
  && !panelConfig.allowsMultipleSelection
  && !panelConfig.canCreateDirectories
  && panelConfig.resolvesAliases

let registry = InMemoryHermesAuthorizedRootRegistry(
  policy: HermesAuthorizedRootPolicy(permittedRootParents: [artifactRoot])
)
let coordinator = HermesBridgeFileIntegrationCoordinator(registry: registry)
let service = HermesBridgeXPCService(handler: coordinator)
let fixture = Fixture(service: service)
let connection = NSXPCConnection(listenerEndpoint: fixture.listener.endpoint)
connection.remoteObjectInterface = NSXPCInterface(with: HermesBridgeXPCProtocol.self)
connection.resume()

let creator = ProductionHermesAuthorizedRootBookmarkCreator()
let bookmark = try creator.createBookmark(for: selectedRoot)
let bookmarkCreated = !bookmark.bookmarkData.isEmpty
let securityScopedRuntimeProven = bookmark.securityScopeState == .securityScopeStarted

let registeredResponse = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("register"),
    operation: .registerAuthorizedRoot,
    registerAuthorizedRoot: HermesBridgeRegisterAuthorizedRootPayload(
      displayName: bookmark.displayName,
      bookmarkData: bookmark.bookmarkData
    )
  ),
  connection: connection
)
guard case .registerAuthorizedRoot(let registered)? = success(registeredResponse) else {
  throw NSError(domain: "fixture", code: 1)
}
let rootID = try HermesAuthorizedRootID(rawValue: registered.root.rootID)
let listedResponse = try await send(
  HermesBridgeRequestEnvelope(correlationID: correlation("list"), operation: .listAuthorizedRoots),
  connection: connection
)
guard case .listAuthorizedRoots(let listed)? = success(listedResponse) else {
  throw NSError(domain: "fixture", code: 2)
}
let listText = String(data: try JSONEncoder().encode(listed), encoding: .utf8) ?? ""
let bookmarkText = bookmark.bookmarkData.base64EncodedString()
let absolutePathExposed = listText.contains(selectedRoot.path) || listText.contains(artifactRoot.path)
let bookmarkBytesExposed = listText.contains(bookmarkText) || listText.contains("bookmarkData")
let fileContentExposed = listText.contains("file-secret")
let rootListedRedacted = listed.roots.contains { $0.rootID == rootID.rawValue }
  && !absolutePathExposed
  && !bookmarkBytesExposed
  && !fileContentExposed

let deactivatedResponse = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("deactivate"),
    operation: .deactivateAuthorizedRoot,
    deactivateAuthorizedRoot: HermesBridgeRootIDPayload(
      rootID: rootID.rawValue,
      expectedRevision: registered.root.revision
    )
  ),
  connection: connection
)
guard case .deactivateAuthorizedRoot(let deactivated)? = success(deactivatedResponse) else {
  throw NSError(domain: "fixture", code: 3)
}
let replacement = try creator.createBookmark(for: selectedRoot)
let reactivatedResponse = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("reactivate"),
    operation: .reactivateAuthorizedRoot,
    reactivateAuthorizedRoot: HermesBridgeReactivateAuthorizedRootPayload(
      rootID: rootID.rawValue,
      bookmarkData: replacement.bookmarkData,
      expectedRevision: deactivated.root.revision
    )
  ),
  connection: connection
)
guard case .reactivateAuthorizedRoot(let reactivated)? = success(reactivatedResponse) else {
  throw NSError(domain: "fixture", code: 4)
}
let removedResponse = try await send(
  HermesBridgeRequestEnvelope(
    correlationID: correlation("remove"),
    operation: .removeAuthorizedRoot,
    removeAuthorizedRoot: HermesBridgeRootIDPayload(
      rootID: rootID.rawValue,
      expectedRevision: reactivated.root.revision
    )
  ),
  connection: connection
)
guard case .removeAuthorizedRoot(let removed)? = success(removedResponse) else {
  throw NSError(domain: "fixture", code: 5)
}
let deactivateReactivatePassed = !deactivated.root.active && reactivated.root.active
let removalPassed = removed.root.rootID == rootID.rawValue

await coordinator.shutdown()
connection.invalidate()
fixture.close()

print("DIRECTORY_ONLY_SELECTION_VALIDATED=\(result(directoryOnly))")
print("BOOKMARK_CREATED=\(result(bookmarkCreated))")
print("ROOT_REGISTERED_OVER_XPC=yes")
print("ROOT_LISTED_REDACTED=\(result(rootListedRedacted))")
print("DEACTIVATE_REACTIVATE_PASSED=\(result(deactivateReactivatePassed))")
print("ROOT_REMOVAL_PASSED=\(result(removalPassed))")
print("ABSOLUTE_PATH_EXPOSED=\(result(absolutePathExposed))")
print("BOOKMARK_BYTES_EXPOSED=\(result(bookmarkBytesExposed))")
print("FILE_CONTENT_EXPOSED=\(result(fileContentExposed))")
print("SECURITY_SCOPED_RUNTIME_PROVEN=\(result(securityScopedRuntimeProven))")

func correlation(_ value: String) -> HermesBridgeCorrelationID {
  try! HermesBridgeCorrelationID(rawValue: value)
}

func send(
  _ envelope: HermesBridgeRequestEnvelope,
  connection: NSXPCConnection
) async throws -> HermesBridgeResponseEnvelope {
  guard let proxy = connection.remoteObjectProxy as? HermesBridgeXPCProtocol else {
    throw NSError(domain: "fixture", code: 9)
  }
  let requestData = try JSONEncoder().encode(envelope)
  let responseData = await withCheckedContinuation { continuation in
    proxy.handleRequest(requestData) { continuation.resume(returning: $0) }
  }
  return try JSONDecoder().decode(HermesBridgeResponseEnvelope.self, from: responseData)
}

func success(_ response: HermesBridgeResponseEnvelope) -> HermesBridgeSuccessPayload? {
  if case .success(let payload) = response.result { return payload }
  return nil
}
EOF

set +e
swift run --package-path "$FIXTURE_DIR" AuthorizedRootUIFixture "$ARTIFACT_DIR" > "$OUTPUT_FILE"
fixture_status=$?
set -e

if [[ $fixture_status -eq 0 ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      DIRECTORY_ONLY_SELECTION_VALIDATED) DIRECTORY_ONLY_SELECTION_VALIDATED="$value" ;;
      BOOKMARK_CREATED) BOOKMARK_CREATED="$value" ;;
      ROOT_REGISTERED_OVER_XPC) ROOT_REGISTERED_OVER_XPC="$value" ;;
      ROOT_LISTED_REDACTED) ROOT_LISTED_REDACTED="$value" ;;
      DEACTIVATE_REACTIVATE_PASSED) DEACTIVATE_REACTIVATE_PASSED="$value" ;;
      ROOT_REMOVAL_PASSED) ROOT_REMOVAL_PASSED="$value" ;;
      ABSOLUTE_PATH_EXPOSED) ABSOLUTE_PATH_EXPOSED="$value" ;;
      BOOKMARK_BYTES_EXPOSED) BOOKMARK_BYTES_EXPOSED="$value" ;;
      FILE_CONTENT_EXPOSED) FILE_CONTENT_EXPOSED="$value" ;;
      SECURITY_SCOPED_RUNTIME_PROVEN) SECURITY_SCOPED_RUNTIME_PROVEN="$value" ;;
    esac
  done < "$OUTPUT_FILE"
fi

rm -rf "$FIXTURE_DIR" "$ARTIFACT_DIR/authorized-root"
cleanup

if [[ "$APP_BUILD_PASSED" == "yes" \
  && "$NSOPENPANEL_IMPLEMENTED" == "yes" \
  && "$DIRECTORY_ONLY_SELECTION_VALIDATED" == "yes" \
  && "$BOOKMARK_CREATED" == "yes" \
  && "$ROOT_REGISTERED_OVER_XPC" == "yes" \
  && "$ROOT_LISTED_REDACTED" == "yes" \
  && "$DEACTIVATE_REACTIVATE_PASSED" == "yes" \
  && "$ROOT_REMOVAL_PASSED" == "yes" \
  && "$ABSOLUTE_PATH_EXPOSED" == "no" \
  && "$BOOKMARK_BYTES_EXPOSED" == "no" \
  && "$FILE_CONTENT_EXPOSED" == "no" \
  && "$RESIDUAL_APP_PROCESS" == "no" ]]; then
  M5_003_RESULT=PASS
elif [[ $fixture_status -eq 0 ]]; then
  M5_003_RESULT=PARTIAL
else
  M5_003_RESULT=FAIL
fi

echo "APP_BUILD_PASSED=${APP_BUILD_PASSED}"
echo "NSOPENPANEL_IMPLEMENTED=${NSOPENPANEL_IMPLEMENTED}"
echo "DIRECTORY_ONLY_SELECTION_VALIDATED=${DIRECTORY_ONLY_SELECTION_VALIDATED}"
echo "BOOKMARK_CREATED=${BOOKMARK_CREATED}"
echo "ROOT_REGISTERED_OVER_XPC=${ROOT_REGISTERED_OVER_XPC}"
echo "ROOT_LISTED_REDACTED=${ROOT_LISTED_REDACTED}"
echo "DEACTIVATE_REACTIVATE_PASSED=${DEACTIVATE_REACTIVATE_PASSED}"
echo "ROOT_REMOVAL_PASSED=${ROOT_REMOVAL_PASSED}"
echo "ABSOLUTE_PATH_EXPOSED=${ABSOLUTE_PATH_EXPOSED}"
echo "BOOKMARK_BYTES_EXPOSED=${BOOKMARK_BYTES_EXPOSED}"
echo "FILE_CONTENT_EXPOSED=${FILE_CONTENT_EXPOSED}"
echo "SECURITY_SCOPED_RUNTIME_PROVEN=${SECURITY_SCOPED_RUNTIME_PROVEN}"
echo "RESIDUAL_APP_PROCESS=${RESIDUAL_APP_PROCESS}"
echo "M5_003_RESULT=${M5_003_RESULT}"
