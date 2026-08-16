#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
INFO_PLIST="${PROJECT_DIR}/AppBundle/Info.plist"
APP_NAME="ReadRevs"
EXECUTABLE_NAME="ReadRevsApp"
PRODUCT_SLUG="ReadRevs"
MINIMUM_MACOS="14.0"

VERSION="${READREVS_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")}"
BUILD_NUMBER="${READREVS_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")}"
BUILD_BASE="${READREVS_BUILD_DIR:-${PROJECT_DIR}/build/release}"
DIST_ROOT="${READREVS_RELEASE_DIR:-${PROJECT_DIR}/dist}"
SIGNING_IDENTITY="${READREVS_SIGNING_IDENTITY:--}"
NOTARY_PROFILE="${READREVS_NOTARY_PROFILE:-}"

if [[ "${SIGNING_IDENTITY}" != "-" && -z "${NOTARY_PROFILE}" ]]; then
  print -u2 -- "READREVS_SIGNING_IDENTITY requires READREVS_NOTARY_PROFILE for a public release."
  exit 2
fi
if [[ -n "${NOTARY_PROFILE}" && "${SIGNING_IDENTITY}" == "-" ]]; then
  print -u2 -- "READREVS_NOTARY_PROFILE requires a Developer ID signing identity."
  exit 2
fi

APP_BUNDLE="${DIST_ROOT}/${APP_NAME}.app"
DSYM_BUNDLE="${DIST_ROOT}/${APP_NAME}.app.dSYM"
APP_ARCHIVE="${DIST_ROOT}/${PRODUCT_SLUG}-v${VERSION}-universal.zip"
APP_CHECKSUM_FILE="${APP_ARCHIVE}.sha256"
LEGACY_CHECKSUM_FILE="${DIST_ROOT}/SHA256SUMS"
LEGACY_SYMBOLS_ARCHIVE="${DIST_ROOT}/${PRODUCT_SLUG}-v${VERSION}-symbols.zip"
LEGACY_SYMBOLS_CHECKSUM_FILE="${LEGACY_SYMBOLS_ARCHIVE}.sha256"

if [[ -z "${BUILD_BASE}" || "${BUILD_BASE}" == "/" || "${BUILD_BASE}" == "${PROJECT_DIR}" ]]; then
  print -u2 -- "Refusing unsafe READREVS_BUILD_DIR: ${BUILD_BASE}"
  exit 2
fi

mkdir -p "${BUILD_BASE}"
BUILD_ROOT=$(mktemp -d "${BUILD_BASE}/run.XXXXXX")
trap 'rm -rf "${BUILD_ROOT}"' EXIT
if [[ -z "${DIST_ROOT}" || "${DIST_ROOT}" == "/" || "${DIST_ROOT}" == "${PROJECT_DIR}" ]]; then
  print -u2 -- "Refusing unsafe READREVS_RELEASE_DIR: ${DIST_ROOT}"
  exit 2
fi
if [[ "${BUILD_NUMBER}" != <-> ]]; then
  print -u2 -- "READREVS_BUILD_NUMBER must contain digits only."
  exit 2
fi

build_architecture() {
  local architecture="$1"
  local triple="${architecture}-apple-macosx${MINIMUM_MACOS}"
  local scratch_path="${BUILD_ROOT}/swiftpm-${architecture}"
  local bin_path

  bin_path=$(swift build \
    --package-path "${PROJECT_DIR}" \
    --configuration release \
    --product "${EXECUTABLE_NAME}" \
    --triple "${triple}" \
    --scratch-path "${scratch_path}" \
    --disable-sandbox \
    --show-bin-path)

  swift build \
    --package-path "${PROJECT_DIR}" \
    --configuration release \
    --product "${EXECUTABLE_NAME}" \
    --triple "${triple}" \
    --scratch-path "${scratch_path}" \
    --disable-sandbox >&2

  print -r -- "${bin_path}/${EXECUTABLE_NAME}"
}

rm -rf "${APP_BUNDLE}" "${DSYM_BUNDLE}"
rm -f \
  "${APP_ARCHIVE}" \
  "${APP_CHECKSUM_FILE}" \
  "${LEGACY_CHECKSUM_FILE}" \
  "${LEGACY_SYMBOLS_ARCHIVE}" \
  "${LEGACY_SYMBOLS_CHECKSUM_FILE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

ARM64_BINARY=$(build_architecture arm64)
X86_64_BINARY=$(build_architecture x86_64)

lipo -create \
  "${ARM64_BINARY}" \
  "${X86_64_BINARY}" \
  -output "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"
chmod 755 "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"

cp -f "${INFO_PLIST}" "${APP_BUNDLE}/Contents/Info.plist"
cp -f "${PROJECT_DIR}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
cp -f "${PROJECT_DIR}/Resources/Assets.car" "${APP_BUNDLE}/Contents/Resources/Assets.car"
plutil -replace CFBundleShortVersionString -string "${VERSION}" "${APP_BUNDLE}/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${BUILD_NUMBER}" "${APP_BUNDLE}/Contents/Info.plist"
plutil -lint "${APP_BUNDLE}/Contents/Info.plist"

dsymutil "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}" -o "${DSYM_BUNDLE}"
xcrun strip -S -x "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"

if LC_ALL=C grep -aFq "${PROJECT_DIR}" "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"; then
  print -u2 -- "Release executable still contains the local project path after stripping."
  exit 2
fi

if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
  codesign --force --sign - "${APP_BUNDLE}"
  print -u2 -- "Warning: using an ad-hoc signature. This build is for local testing, not a public notarized release."
else
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "${SIGNING_IDENTITY}" \
    "${APP_BUNDLE}"
fi

codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
ditto -c -k --keepParent --sequesterRsrc "${APP_BUNDLE}" "${APP_ARCHIVE}"

if [[ -n "${NOTARY_PROFILE}" ]]; then
  xcrun notarytool submit "${APP_ARCHIVE}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait
  xcrun stapler staple "${APP_BUNDLE}"
  xcrun stapler validate "${APP_BUNDLE}"
  rm -f "${APP_ARCHIVE}"
  ditto -c -k --keepParent --sequesterRsrc "${APP_BUNDLE}" "${APP_ARCHIVE}"
fi

(
  cd "${DIST_ROOT}"
  shasum -a 256 "${APP_ARCHIVE:t}" > "${APP_CHECKSUM_FILE:t}"
)

print -r -- "${APP_BUNDLE}"
print -r -- "${APP_ARCHIVE}"
print -r -- "${APP_CHECKSUM_FILE}"
