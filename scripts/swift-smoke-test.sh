#!/usr/bin/env bash
#
# swift-smoke-test.sh: prove the bridge works from Swift, not just that
# bindings can be generated.
#
# Compiles apple/smoke against the generated bindings and the Rust static
# library, then runs it. Build the XCFramework first:
#
#   scripts/build-xcframework.sh
#   scripts/swift-smoke-test.sh

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly FRAMEWORK="${REPO_ROOT}/apple/RondoCore/RondoCore.xcframework"
readonly SWIFT_SOURCES="${REPO_ROOT}/apple/RondoCore/rondo_ffi.swift"
readonly SMOKE_SOURCE="${REPO_ROOT}/apple/smoke/main.swift"

if [[ ! -d "${FRAMEWORK}" ]]; then
  echo "error: ${FRAMEWORK#"${REPO_ROOT}/"} is missing." >&2
  echo "       Run scripts/build-xcframework.sh first." >&2
  exit 1
fi

# The XCFramework names its slices after the platform and architectures it
# was built for, so find the one matching this machine rather than assuming.
readonly ARCH="$(uname -m)"
slice="$(find "${FRAMEWORK}" -maxdepth 1 -type d -name "macos-*${ARCH}*" | head -n 1)"
if [[ -z "${slice}" ]]; then
  echo "error: the XCFramework has no macos slice for ${ARCH}." >&2
  echo "       Rebuild it on this machine, or pass --targets to include it." >&2
  exit 1
fi

build_dir="$(mktemp -d)"
trap 'rm -rf "${build_dir}"' EXIT

echo "==> Compiling the smoke test against $(basename "${slice}")"
swiftc \
  -I "${slice}/Headers" \
  -L "${slice}" \
  -lrondo_ffi \
  "${SWIFT_SOURCES}" "${SMOKE_SOURCE}" \
  -o "${build_dir}/smoke"

echo "==> Running"
"${build_dir}/smoke"
