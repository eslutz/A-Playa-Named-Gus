#!/bin/sh
set -eu

if [ "${CI_XCODE_CLOUD:-}" != TRUE ] ||
   [ "${CI_WORKFLOW:-}" != "Gus Internal TestFlight" ] ||
   [ "${CI_XCODEBUILD_ACTION:-}" != archive ] ||
   [ "${CI_XCODEBUILD_EXIT_CODE:-}" != 0 ]; then
  exit 0
fi

case "${CI_PRODUCT_PLATFORM:-}" in
  iOS|macOS|xrOS|watchOS) ;;
  *) exit 0 ;;
esac

archive="${CI_ARCHIVE_PATH:?Missing Xcode Cloud archive path}"
app_path=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:ApplicationPath' "$archive/Info.plist")
app="$archive/Products/$app_path"
evidence=$(mktemp -d)
trap 'rm -rf "$evidence"' EXIT
pcc_key='com\.apple\.developer\.private-cloud-compute'

verify_pcc() {
  bundle=$1
  info=$2
  profile=$3
  identifier=$4
  if [ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$info")" != "$identifier" ] ||
     [ "$(/usr/bin/plutil -extract GusPrivateCloudComputeEntitled raw "$info")" != YES ]; then
    echo "PCC bundle or runtime configuration mismatch for $identifier." >&2
    exit 65
  fi
  /usr/bin/codesign --verify --strict "$bundle"
  /usr/bin/codesign --display --entitlements - "$bundle" > "$evidence/entitlements.plist"
  /usr/bin/security cms -D -i "$profile" -o "$evidence/profile.plist"
  if [ "$(/usr/bin/plutil -extract "$pcc_key" raw "$evidence/entitlements.plist")" != true ] ||
     [ "$(/usr/bin/plutil -extract "Entitlements.$pcc_key" raw "$evidence/profile.plist")" != true ]; then
    echo "PCC is missing from the signature or profile for $identifier." >&2
    exit 65
  fi
  echo "Verified signed PCC entitlement and provisioning profile for $identifier."
}

case "$CI_PRODUCT_PLATFORM" in
  macOS) verify_pcc "$app" "$app/Contents/Info.plist" "$app/Contents/embedded.provisionprofile" dev.ericslutz.gus ;;
  watchOS) verify_pcc "$app" "$app/Info.plist" "$app/embedded.mobileprovision" dev.ericslutz.gus.watchkitapp ;;
  iOS|xrOS) verify_pcc "$app" "$app/Info.plist" "$app/embedded.mobileprovision" dev.ericslutz.gus ;;
esac
if [ "$CI_PRODUCT_PLATFORM" = iOS ]; then
  watch="$app/Watch/GusWatch.app"
  verify_pcc "$watch" "$watch/Info.plist" "$watch/embedded.mobileprovision" dev.ericslutz.gus.watchkitapp
fi
