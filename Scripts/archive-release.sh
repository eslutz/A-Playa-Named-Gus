#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: Scripts/archive-release.sh [ios] [tvos] [visionos] [macos] [-- <xcodebuild args>]

Creates Release .xcarchive bundles under build/archives.
If no platform is provided, archives all platforms.
EOF
}

scheme="A Playa Named Gus"
project="A Playa Named Gus.xcodeproj"
archive_root="build/archives"
platforms=()
xcodebuild_args=()

while (($#)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      xcodebuild_args=("$@")
      break
      ;;
    ios|tvos|visionos|macos)
      platforms+=("$1")
      shift
      ;;
    *)
      echo "Unknown platform or option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if ((${#platforms[@]} == 0)); then
  platforms=(ios tvos visionos macos)
fi

destination_for() {
  case "$1" in
    ios) echo "generic/platform=iOS" ;;
    tvos) echo "generic/platform=tvOS" ;;
    visionos) echo "generic/platform=visionOS" ;;
    macos) echo "generic/platform=macOS" ;;
    *) return 1 ;;
  esac
}

archive_name_for() {
  case "$1" in
    ios) echo "Gus-iOS.xcarchive" ;;
    tvos) echo "Gus-tvOS.xcarchive" ;;
    visionos) echo "Gus-visionOS.xcarchive" ;;
    macos) echo "Gus-macOS.xcarchive" ;;
    *) return 1 ;;
  esac
}

command -v xcodegen >/dev/null || {
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 69
}

xcodegen generate
xcodebuild -resolvePackageDependencies -project "$project" -scheme "$scheme"
mkdir -p "$archive_root"

for platform in "${platforms[@]}"; do
  destination="$(destination_for "$platform")"
  archive_path="$archive_root/$(archive_name_for "$platform")"
  echo "Archiving $platform to $archive_path"
  xcodebuild archive \
    -project "$project" \
    -scheme "$scheme" \
    -configuration Release \
    -destination "$destination" \
    -archivePath "$archive_path" \
    "${xcodebuild_args[@]}"
done
