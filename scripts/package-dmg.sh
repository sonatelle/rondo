#!/usr/bin/env bash
#
# package-dmg.sh: build Rondo for release and put it in a disk image.
#
# Produces dist/Rondo-<version>.dmg, where the version is read from the app
# that was actually built rather than from any file that claims one.
#
# Usage:
#   scripts/package-dmg.sh [--output-dir DIR]
#
# The app is ad-hoc signed and not notarized, so Gatekeeper stops the first
# launch of a downloaded copy; the README says how to get past it. Signing
# it properly needs a paid Developer ID, which this project does not have.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly APP_NAME="Rondo"
readonly VOLUME_NAME="Rondo"

output_dir="${REPO_ROOT}/dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="${2:?--output-dir needs a path}"
      shift 2
      ;;
    -h | --help)
      sed -n '3,14p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

cd "${REPO_ROOT}"

echo "==> Packaging the core for Xcode (release)"
scripts/build-xcframework.sh --release

echo "==> Generating the Xcode project"
xcodegen generate --spec apple/project.yml --project apple

# Built into a directory this script names, rather than hunting for it in
# DerivedData afterwards. Xcode's own layout is not a stable interface, and
# the path it prints has been read wrong here before.
staging="$(mktemp -d)"
trap 'rm -rf "${staging}"' EXIT
readonly BUILD_DIR="${staging}/build"

echo "==> Building ${APP_NAME} (Release)"
xcodebuild build \
  -project apple/Rondo.xcodeproj \
  -scheme "${APP_NAME}" \
  -configuration Release \
  CONFIGURATION_BUILD_DIR="${BUILD_DIR}" \
  >/dev/null

readonly APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: no ${APP_NAME}.app in ${BUILD_DIR}" >&2
  exit 1
fi

# The version the disk image is named for comes from the bundle, so the
# file name cannot disagree with what the app reports about itself.
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "${APP_PATH}/Contents/Info.plist")"
readonly VERSION="${version}"

echo "    version ${VERSION}, $(lipo -archs "${APP_PATH}/Contents/MacOS/${APP_NAME}")"

# The image holds the app beside a link to /Applications, which is the
# gesture every Mac user already knows: drag one onto the other.
readonly IMAGE_ROOT="${staging}/image"
mkdir -p "${IMAGE_ROOT}"
cp -R "${APP_PATH}" "${IMAGE_ROOT}/"
ln -s /Applications "${IMAGE_ROOT}/Applications"

mkdir -p "${output_dir}"
readonly DMG_PATH="${output_dir}/${APP_NAME}-${VERSION}.dmg"
rm -f "${DMG_PATH}"

echo "==> Creating $(basename "${DMG_PATH}")"
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${IMAGE_ROOT}" \
  -fs HFS+ \
  -format UDZO \
  "${DMG_PATH}" \
  >/dev/null

echo "==> Done: ${DMG_PATH#"${REPO_ROOT}/"}"
ls -lh "${DMG_PATH}"
