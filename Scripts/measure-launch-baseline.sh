#!/bin/zsh
# Coarse, repeatable cold-launch baseline for the iOS simulator.
#
# Reports wall-time from launch request to process spawn. Precise per-flow
# measurements (server connect, library load, playback startup, search) come from
# the DiagnosticsHub signpost intervals — profile with Instruments using subsystem
# `dev.ericslutz.gus`, category `Diagnostics`. Record results in
# Documentation/AppStore/performance-baselines.md.
#
# Usage: Scripts/measure-launch-baseline.sh ["iPhone 17"] [runs]
set -euo pipefail
zmodload zsh/datetime

DEVICE="${1:-iPhone 17}"
RUNS="${2:-5}"
BUNDLE_ID="dev.ericslutz.gus"

xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator

xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath build build -quiet

APP_PATH=$(find build/Build/Products/Debug-iphonesimulator -maxdepth 1 -name 'A Playa Named Gus.app' | head -1)
if [[ -z "$APP_PATH" ]]; then
  echo "error: built app not found under build/Build/Products/Debug-iphonesimulator" >&2
  exit 1
fi
xcrun simctl install "$DEVICE" "$APP_PATH"

# Untimed warm-up launch so simulator boot and first-install work don't skew run 1.
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" >/dev/null
sleep 3

echo "Cold-launch baseline on $DEVICE ($RUNS runs):"
total=0
for i in $(seq 1 "$RUNS"); do
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
  sleep 2
  start=$EPOCHREALTIME
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" >/dev/null
  end=$EPOCHREALTIME
  ms=$(( (end - start) * 1000 ))
  printf "  run %d: %.0f ms\n" "$i" "$ms"
  total=$(( total + ms ))
done
printf "  average: %.0f ms\n" $(( total / RUNS ))
