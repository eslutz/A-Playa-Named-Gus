#!/bin/sh
set -eu

if [ "${CI_XCODE_CLOUD:-}" != TRUE ]; then
  exit 0
fi
# Simulator validation belongs on the local machine. Check before the separate
# test-runner exit so an old Cloud workflow cannot execute simulator products.
case "${CI_PRODUCT_PLATFORM:-}:${CI_XCODEBUILD_ACTION:-}" in
  macOS:build|macOS:build-for-testing|macOS:test|macOS:test-without-building|\
  macOS:archive|macOS:analyze|iOS:archive|iOS:analyze|tvOS:archive|tvOS:analyze|\
  xrOS:archive|xrOS:analyze|watchOS:archive|watchOS:analyze)
    ;;
  *)
    printf 'Rejected Cloud platform/action: %s/%s\n' "${CI_PRODUCT_PLATFORM:-<unset>}" "${CI_XCODEBUILD_ACTION:-<unset>}" >&2
    echo "Simulator builds and tests must run locally. Xcode Cloud permits only native macOS builds/tests and known-platform device archives/analysis." >&2
    exit 65
    ;;
esac
# Test runners execute the already-built products in a separate environment.
# Only ci_scripts is guaranteed there; the source checkout and its build-time
# xcconfig may be absent. Architecture enforcement belongs to compilation.
if [ "${CI_XCODEBUILD_ACTION:-}" = test-without-building ]; then
  exit 0
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repository_dir="${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$script_dir")}"
cd "$repository_dir"
# A shell export here cannot affect Apple's parent xcodebuild invocation.
# The workflow must supply this global configuration before launching any action.
expected_architecture_config="$repository_dir/Config/Architecture.xcconfig"
if [ "${XCODE_XCCONFIG_FILE:-}" != "$expected_architecture_config" ] ||
   [ ! -f "$expected_architecture_config" ]; then
  echo "Apple Silicon enforcement missing: set workflow XCODE_XCCONFIG_FILE to $expected_architecture_config." >&2
  exit 65
fi

# Cloud builds unit hosts ad hoc. Preserve sandbox/network permissions.
if [ "${CI_PRODUCT_PLATFORM:-}" != macOS ] ||
   [ "${CI_XCODEBUILD_ACTION:-}" != build-for-testing ]; then
  exit 0
fi
test_entitlements="$script_dir/gus-macos-unit.entitlements"
/usr/bin/plutil -lint "$test_entitlements"
if [ ! -f Config/Local.xcconfig ]; then
  echo "Cloud post-clone signing configuration is missing." >&2
  exit 66
fi
printf '\nCODE_SIGN_ENTITLEMENTS[sdk=macosx*] = %s\n' "$test_entitlements" >> Config/Local.xcconfig
