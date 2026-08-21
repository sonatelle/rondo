#!/usr/bin/env bash
#
# build-xcframework.sh: package rondo-ffi for Xcode.
#
# Produces apple/RondoCore/RondoCore.xcframework plus the generated Swift,
# which together are everything the app target needs to import the core.
#
# Usage:
#   scripts/build-xcframework.sh [--release] [--targets "triple triple ..."]
#
# Targets default to the host, which is what the macOS build needs. Adding
# another one (Intel macOS, iOS) requires its standard library in the dev
# shell: add the triple to the Rust toolchain in flake.nix first, or the
# build fails with "target may not be installed".

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LIB_NAME="librondo_ffi.a"
readonly FRAMEWORK_NAME="RondoCore"
readonly OUT_DIR="${REPO_ROOT}/apple/RondoCore"

profile="debug"
cargo_profile_args=()
targets="$(rustc -vV | sed -n 's/^host: //p')"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)
      profile="release"
      cargo_profile_args=(--release)
      shift
      ;;
    --targets)
      targets="${2:?--targets needs a space-separated list of triples}"
      shift 2
      ;;
    -h | --help)
      sed -n '3,15p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

cd "${REPO_ROOT}"

# check_target: fail early and legibly when a target's std is missing.
check_target() {
  local triple="$1"
  if ! rustc --print target-libdir --target "${triple}" >/dev/null 2>&1; then
    echo "error: no standard library for ${triple}." >&2
    echo "       Add it to the Rust toolchain in flake.nix, then reload direnv." >&2
    exit 1
  fi
}

echo "==> Building ${LIB_NAME} (${profile})"
built_libs=()
for triple in ${targets}; do
  check_target "${triple}"
  echo "    ${triple}"
  cargo build -p rondo-ffi --target "${triple}" "${cargo_profile_args[@]}"
  built_libs+=("target/${triple}/${profile}/${LIB_NAME}")
done

# An XCFramework holds one library per platform, so same-platform slices
# (Apple Silicon and Intel macOS) are merged into one fat library first.
staging="$(mktemp -d)"
trap 'rm -rf "${staging}"' EXIT
readonly LIB_PATH="${staging}/${LIB_NAME}"
if [[ ${#built_libs[@]} -gt 1 ]]; then
  echo "==> Merging $((${#built_libs[@]})) slices"
  lipo -create "${built_libs[@]}" -output "${LIB_PATH}"
else
  cp "${built_libs[0]}" "${LIB_PATH}"
fi

# Bindings are generated from the built library rather than from source, so
# what Swift sees always matches what was compiled. The Swift-specific
# generator writes sources, headers, and the module map separately, which
# is exactly how an XCFramework wants them laid out.
readonly SWIFT_DIR="${staging}/swift"
readonly HEADERS_DIR="${staging}/headers"
mkdir -p "${SWIFT_DIR}" "${HEADERS_DIR}"

bindgen_swift() {
  cargo run --quiet --features bindgen -p rondo-ffi --bin uniffi-bindgen-swift -- \
    "${LIB_PATH}" "$@"
}

echo "==> Generating Swift sources"
bindgen_swift "${SWIFT_DIR}" --swift-sources

# `module.modulemap` is the name Clang looks for beside a set of headers.
# The module is declared plain rather than as a `framework` module, because
# this XCFramework carries a static library and a headers directory, not a
# .framework bundle - hence no --xcframework flag here.
echo "==> Generating headers and module map"
bindgen_swift "${HEADERS_DIR}" --headers --modulemap --modulemap-filename module.modulemap

echo "==> Assembling ${FRAMEWORK_NAME}.xcframework"
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
xcodebuild -create-xcframework \
  -library "${LIB_PATH}" \
  -headers "${HEADERS_DIR}" \
  -output "${OUT_DIR}/${FRAMEWORK_NAME}.xcframework" >/dev/null
cp "${SWIFT_DIR}"/*.swift "${OUT_DIR}/"

echo "==> Done: ${OUT_DIR#"${REPO_ROOT}/"}"
ls "${OUT_DIR}"
