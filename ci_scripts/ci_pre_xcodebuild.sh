#!/bin/sh
set -eu

# Cloud builds unit hosts ad hoc. Provisioned production capabilities cannot be
# used by that host; preserve its sandbox and network permissions, as in GitHub CI.
if [ "${CI_XCODE_CLOUD:-}" != TRUE ] ||
   [ "${CI_PRODUCT_PLATFORM:-}" != macOS ] ||
   [ "${CI_XCODEBUILD_ACTION:-}" != build-for-testing ]; then
  exit 0
fi
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repository_dir="${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$script_dir")}"
cd "$repository_dir"
test_entitlements="$script_dir/gus-macos-unit.entitlements"
/usr/bin/plutil -lint "$test_entitlements"
if [ ! -f Config/Local.xcconfig ]; then
  echo "Cloud post-clone signing configuration is missing." >&2
  exit 66
fi
printf '\nCODE_SIGN_ENTITLEMENTS[sdk=macosx*] = %s\n' "$test_entitlements" >> Config/Local.xcconfig
