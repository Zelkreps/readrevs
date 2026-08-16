#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_ROOT="${READREVS_BUILD_DIR:-${PROJECT_DIR}/build}"
CONFIGURATION="${1:-${READREVS_CONFIGURATION:-release}}"

case "${CONFIGURATION}" in
  debug)
    APP_NAME="ReadRevs Debug"
    SCRATCH_PATH="${OUTPUT_ROOT}/swiftpm-debug"
    ;;
  release)
    APP_NAME="ReadRevs"
    SCRATCH_PATH="${OUTPUT_ROOT}/swiftpm"
    ;;
  *)
    print -u2 -- "Usage: ${0:t} [debug|release]"
    exit 2
    ;;
esac

APP_BUNDLE="${OUTPUT_ROOT}/${APP_NAME}.app"

BIN_DIR=$(swift build \
  --package-path "${PROJECT_DIR}" \
  --configuration "${CONFIGURATION}" \
  --product ReadRevsApp \
  --scratch-path "${SCRATCH_PATH}" \
  --disable-sandbox \
  --show-bin-path)

swift build \
  --package-path "${PROJECT_DIR}" \
  --configuration "${CONFIGURATION}" \
  --product ReadRevsApp \
  --scratch-path "${SCRATCH_PATH}" \
  --disable-sandbox

rm -rf "${APP_BUNDLE}" "${APP_BUNDLE}.dSYM"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp -f "${BIN_DIR}/ReadRevsApp" "${APP_BUNDLE}/Contents/MacOS/ReadRevsApp"
cp -f "${PROJECT_DIR}/AppBundle/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp -f "${PROJECT_DIR}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
cp -f "${PROJECT_DIR}/Resources/Assets.car" "${APP_BUNDLE}/Contents/Resources/Assets.car"

if [[ "${CONFIGURATION}" == "debug" ]]; then
  plutil -replace CFBundleDisplayName -string "${APP_NAME}" "${APP_BUNDLE}/Contents/Info.plist"
  plutil -replace CFBundleName -string "${APP_NAME}" "${APP_BUNDLE}/Contents/Info.plist"
  plutil -replace CFBundleIdentifier -string "com.zelkreps.ReadRevs.debug" "${APP_BUNDLE}/Contents/Info.plist"
  dsymutil "${APP_BUNDLE}/Contents/MacOS/ReadRevsApp" -o "${APP_BUNDLE}.dSYM"
fi

plutil -lint "${APP_BUNDLE}/Contents/Info.plist"
codesign --force --sign - "${APP_BUNDLE}"
codesign --verify --deep --strict "${APP_BUNDLE}"

print -r -- "${APP_BUNDLE}"
