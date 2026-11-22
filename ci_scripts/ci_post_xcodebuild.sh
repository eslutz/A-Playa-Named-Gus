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

export_dir="${CI_APP_STORE_SIGNED_APP_PATH:?Missing signed TestFlight export}"
evidence=$(mktemp -d)
trap 'rm -rf "$evidence"' EXIT
if [ "$CI_PRODUCT_PLATFORM" = macOS ]; then
  set -- "$export_dir"/*.pkg
  if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    echo "Expected one macOS installer in the signed TestFlight export." >&2
    exit 65
  fi
  /usr/sbin/pkgutil --expand-full "$1" "$evidence/expanded"
  set -- "$evidence"/expanded/*.pkg/Payload/*.app
else
  set -- "$export_dir"/*.ipa
  if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    echo "Expected one IPA in the signed TestFlight export." >&2
    exit 65
  fi
  /usr/bin/ditto -x -k "$1" "$evidence/expanded"
  set -- "$evidence"/expanded/Payload/*.app
fi
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  echo "Expected one app bundle in the signed TestFlight export." >&2
  exit 65
fi
app=$1
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
  /usr/bin/codesign --verify --strict -R='entitlement["com.apple.developer.private-cloud-compute"] exists' "$bundle"
  /usr/bin/security cms -D -i "$profile" -o "$evidence/profile.plist"
  if [ "$(/usr/bin/plutil -extract "Entitlements.$pcc_key" raw "$evidence/profile.plist")" != true ]; then
    echo "PCC is missing from the provisioning profile for $identifier." >&2
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
  /usr/bin/codesign -d --xml --entitlements - "$app" > "$evidence/app-entitlements.plist" 2>/dev/null
  for key in 'com\.apple\.developer\.carplay-audio' 'com\.apple\.developer\.siri'; do
    if [ "$(/usr/bin/plutil -extract "$key" raw "$evidence/app-entitlements.plist")" != true ] ||
       [ "$(/usr/bin/plutil -extract "Entitlements.$key" raw "$evidence/profile.plist")" != true ]; then
      echo "The iOS TestFlight export is missing a required CarPlay or Siri entitlement." >&2
      exit 65
    fi
  done
  echo "Verified signed CarPlay and Siri entitlements and provisioning profile for the iOS app."
  watch="$app/Watch/GusWatch.app"
  verify_pcc "$watch" "$watch/Info.plist" "$watch/embedded.mobileprovision" dev.ericslutz.gus.watchkitapp
fi
