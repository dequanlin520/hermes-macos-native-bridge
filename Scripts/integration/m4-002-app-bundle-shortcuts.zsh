#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ARTIFACT_ROOT="${ROOT_DIR}/artifacts/m4-002"
APP_NAME="Hermes Bridge.app"
APP_BUNDLE="${ARTIFACT_ROOT}/${APP_NAME}"
INSTALL_APP="/Applications/${APP_NAME}"
INSTALL_LOCAL="no"

for arg in "$@"; do
  case "$arg" in
    --install-local-for-shortcuts-check)
      INSTALL_LOCAL="yes"
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

APP_BUNDLE_BUILT=no
APP_SIGNED=no
APP_INTENTS_METADATA_PRESENT=no
SHORTCUTS_RUNTIME_DISCOVERY_PROVEN=no
BINDING_DISCOVERY_ROUNDTRIP=no

cleanup() {
  if [[ "${INSTALL_LOCAL}" == "yes" && -d "${INSTALL_APP}" ]]; then
    rm -rf "${INSTALL_APP}"
  fi
  pkill -x HermesBridgeApp >/dev/null 2>&1 || true
  pkill -x "Hermes Bridge" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cd "${ROOT_DIR}"
rm -rf "${ARTIFACT_ROOT}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

xcodebuild -scheme HermesBridgeApp -destination 'platform=macOS' build >/dev/null
swift build --product HermesBridgeApp >/dev/null

cp ".build/debug/HermesBridgeApp" "${APP_BUNDLE}/Contents/MacOS/HermesBridgeApp"
cp "Packaging/HermesBridgeApp/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
chmod 755 "${APP_BUNDLE}/Contents/MacOS/HermesBridgeApp"

XCODE_METADATA="$(find "${HOME}/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug/HermesAppIntents.appintents' -type d 2>/dev/null | sort | tail -n 1 || true)"
if [[ -n "${XCODE_METADATA}" ]]; then
  cp -R "${XCODE_METADATA}" "${APP_BUNDLE}/Contents/Resources/"
fi

if [[ -x "${APP_BUNDLE}/Contents/MacOS/HermesBridgeApp" ]]; then
  APP_BUNDLE_BUILT=yes
fi

METADATA_DIR="${APP_BUNDLE}/Contents/Resources/HermesAppIntents.appintents/Metadata.appintents"
mkdir -p "${METADATA_DIR}"
SOURCE_LIST="${ARTIFACT_ROOT}/appintents-sources.txt"
CONST_LIST="${ARTIFACT_ROOT}/appintents-const-values.txt"
find Sources/HermesAppIntents Sources/HermesBridgeApp -name '*.swift' | sort > "${SOURCE_LIST}"
find .build -name '*.swiftconstvalues' | sort > "${CONST_LIST}"

PROCESSOR="$(xcrun --find appintentsmetadataprocessor || true)"
if [[ -n "$(find "${METADATA_DIR}" -type f -print -quit)" ]]; then
  APP_INTENTS_METADATA_PRESENT=yes
elif [[ -n "${PROCESSOR}" && -s "${CONST_LIST}" ]]; then
  set +e
  "${PROCESSOR}" \
    --output "${APP_BUNDLE}/Contents/Resources/HermesAppIntents.appintents" \
    --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
    --module-name HermesBridgeApp \
    --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/ {print $3}')" \
    --platform-family macOS \
    --deployment-target 13.0 \
    --target-triple "$(swift -print-target-info | awk -F'"' '/"triple"/ {print $4; exit}')" \
    --source-file-list "${SOURCE_LIST}" \
    --swift-const-vals-list "${CONST_LIST}" \
    --force-metadata-output \
    --no-app-shortcuts-localization >/dev/null 2>"${ARTIFACT_ROOT}/appintents-metadata.log"
  METADATA_STATUS=$?
  set -e
  if [[ ${METADATA_STATUS} -eq 0 && -n "$(find "${METADATA_DIR}" -type f -print -quit)" ]]; then
    APP_INTENTS_METADATA_PRESENT=yes
  fi
fi

if [[ "${APP_INTENTS_METADATA_PRESENT}" == "no" && -n "$(find "${METADATA_DIR}" -type f -print -quit)" ]]; then
  APP_INTENTS_METADATA_PRESENT=yes
fi

codesign --force --sign - "${APP_BUNDLE}" >/dev/null
if codesign --verify --deep --strict "${APP_BUNDLE}" >/dev/null 2>&1; then
  APP_SIGNED=yes
fi

/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_BUNDLE}/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "${APP_BUNDLE}/Contents/Info.plist" >/dev/null

if swift test --filter HermesBridgeXPCTests/testBindingDiscoveryReturnsEnabledBindingsSorted >/dev/null; then
  BINDING_DISCOVERY_ROUNDTRIP=yes
fi

if [[ "${INSTALL_LOCAL}" == "yes" ]]; then
  rm -rf "${INSTALL_APP}"
  cp -R "${APP_BUNDLE}" "${INSTALL_APP}"
  if command -v shortcuts >/dev/null 2>&1; then
    if shortcuts list 2>/dev/null | grep -q "Hermes"; then
      SHORTCUTS_RUNTIME_DISCOVERY_PROVEN=yes
    fi
  fi
fi

echo "APP_BUNDLE_BUILT=${APP_BUNDLE_BUILT}"
echo "APP_SIGNED=${APP_SIGNED}"
echo "APP_INTENTS_METADATA_PRESENT=${APP_INTENTS_METADATA_PRESENT}"
echo "SHORTCUTS_RUNTIME_DISCOVERY_PROVEN=${SHORTCUTS_RUNTIME_DISCOVERY_PROVEN}"
echo "BINDING_DISCOVERY_ROUNDTRIP=${BINDING_DISCOVERY_ROUNDTRIP}"
