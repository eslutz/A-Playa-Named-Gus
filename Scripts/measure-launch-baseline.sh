#!/bin/zsh
# Coarse, repeatable cold-launch baseline for the iOS simulator.
#
# Reports wall-time from launch request to process spawn. Precise per-flow
# measurements (server connect, library load, playback startup, search) come from
# the DiagnosticsHub signpost intervals — profile with Instruments using subsystem
# `dev.ericslutz.gus`, category `Diagnostics`. Record results in
# Documentation/AppStore/performance-baselines.md.
#
# Usage: Scripts/measure-launch-baseline.sh ["iPhone 17" | simulator-UDID] [runs]
# GUS_LAUNCH_APP_PATH can reuse an already validated simulator app without building.
set -euo pipefail
zmodload zsh/datetime

DEVICE="${1:-iPhone 17}"
RUNS="${2:-5}"
BUNDLE_ID="dev.ericslutz.gus"

# Simulator names can exist on several runtimes. Resolve a compatible UUID first.
DEVICE=$(python3 - "$DEVICE" <<'PY'
import json, re, subprocess, sys
requested = sys.argv[1]
data = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))
candidates = []
for runtime, devices in data['devices'].items():
    version = re.search(r'iOS-(\d+)-(\d+)', runtime)
    if not version or int(version[1]) < 18:
        continue
    for device in devices:
        if requested in (device['name'], device['udid']) and device.get('isAvailable', True):
            candidates.append(((int(version[1]), int(version[2])), device['udid']))
if not candidates:
    sys.exit('No matching available iOS simulator at or above the deployment target')
print(max(candidates)[1])
PY
)

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

APP_PATH="${GUS_LAUNCH_APP_PATH:-}"
if [[ -z "$APP_PATH" ]]; then
  python3 Scripts/run-warning-free.py xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' \
    -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath build build -quiet
  APP_PATH="build/Build/Products/Debug-iphonesimulator/A Playa Named Gus.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: simulator app not found: $APP_PATH" >&2
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
