#!/usr/bin/env bash
# screenshots.sh — Capture App Store screenshots from simulators.
#
# Usage:
#   Scripts/screenshots.sh            # capture all platforms
#   Scripts/screenshots.sh --list     # list resolved destinations and exit
#   Scripts/screenshots.sh iphone     # capture iPhone only
#   Scripts/screenshots.sh ipad       # capture iPad only
#   Scripts/screenshots.sh tv         # capture Apple TV only
#   Scripts/screenshots.sh vision     # capture visionOS only
#   Scripts/screenshots.sh mac        # print macOS manual instructions and exit
#
# Output lands in Screenshots/<platform>/ (git-ignored).
# Run `xcodegen generate` before this script if the project is stale.
#
# Required: Xcode command-line tools, xcodegen, a booted macOS host.
# macOS screenshots are manual (see --mac notes at the end of this file).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="Gus"
PROJECT="$REPO_ROOT/Gus.xcodeproj"
OUT="$REPO_ROOT/Screenshots"
BUNDLE_ID="dev.ericslutz.gus"
SETTLE_SECONDS=4   # seconds to wait after launch before capturing

# ── Simulator UDIDs (App Store required device/size per platform) ─────────────
# iPhone 6.9" (1320×2868 @3x) — required slot in App Store Connect.
IPHONE_NAME="iPhone 17 Pro Max"
IPHONE_UDID="34B03CAA-8205-4170-A0E1-AEA402DA2DEE"

# iPad 13" (2064×2752 @2x) — required slot.
IPAD_NAME="iPad Pro 13-inch (M4)"
IPAD_UDID="FE2199AD-8B3E-46D0-BCF8-6129EF5EF44D"

# Apple TV 4K 1080p (1920×1080) — required slot.
TV_NAME="Apple TV 4K (3rd generation) (at 1080p)"
TV_UDID="F2B6DBDC-629C-4101-A473-5A6A9E77EE3F"

# Apple Vision Pro (2980×2980) — required slot.
VISION_NAME="Apple Vision Pro"
VISION_UDID="1711D519-F8C9-42CA-A705-5F12E87D96F2"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "▶ $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*" >&2; }

list_destinations() {
  echo "Screenshot destinations (App Store required sizes):"
  echo "  iPhone  → $IPHONE_NAME ($IPHONE_UDID)"
  echo "  iPad    → $IPAD_NAME   ($IPAD_UDID)"
  echo "  TV      → $TV_NAME ($TV_UDID)"
  echo "  Vision  → $VISION_NAME ($VISION_UDID)"
  echo "  Mac     → manual (see mac instructions below)"
  echo ""
  echo "Verify UDIDs on this machine with:"
  echo "  xcodebuild -showdestinations -project Gus.xcodeproj -scheme Gus"
}

build_app() {
  local platform="$1" udid="$2" derived_data="$3"
  log "Building for $platform …"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=$platform,id=$udid" \
    -derivedDataPath "$derived_data" \
    -configuration Debug \
    build \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=NO \
    2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -5
}

find_app() {
  local derived_data="$1" suffix="$2"
  find "$derived_data/Build/Products" -maxdepth 3 \
    -name "Gus.app" -path "*$suffix*" | head -1
}

boot_sim() {
  local udid="$1" name="$2"
  local state
  state=$(xcrun simctl list devices 2>/dev/null | grep "$udid" | grep -o "(.*)" | tr -d "()")
  if [[ "$state" != "Booted" ]]; then
    log "Booting $name …"
    xcrun simctl boot "$udid"
    # Give the SpringBoard a moment to become ready
    sleep 3
  else
    ok "$name already booted"
  fi
}

install_and_launch() {
  local udid="$1" app_path="$2"
  log "Installing $(basename "$app_path") …"
  xcrun simctl install "$udid" "$app_path"
  log "Launching $BUNDLE_ID …"
  xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null
  log "Settling for ${SETTLE_SECONDS}s …"
  sleep "$SETTLE_SECONDS"
}

capture() {
  local udid="$1" outdir="$2" label="$3"
  mkdir -p "$outdir"
  local outfile="$outdir/${label}.png"
  xcrun simctl io "$udid" screenshot "$outfile"
  ok "Saved: $outfile"
}

terminate_app() {
  local udid="$1"
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
}

mac_instructions() {
  cat <<'MAC'

macOS Screenshots (manual)
──────────────────────────
App Store Connect requires at least one macOS screenshot at 1280×800, 1440×900,
2560×1600, or 2880×1800.

Steps:
  1. Build and run the Release scheme on macOS in Xcode.
  2. Resize the Gus window to 1280×800 (or drag to a Retina display for 2x).
  3. Use Cmd+Shift+4 → Space → click the Gus window to capture just the window.
  4. Repeat for each required scene (Connect, Home, Item Detail, Player, Downloads).
  5. Save results to Screenshots/mac/.

Tip: System Preferences → Displays → set resolution to 1280×800 for exact sizing.
MAC
}

# ── Platform capture functions ────────────────────────────────────────────────
capture_iphone() {
  local dd="$REPO_ROOT/build-screenshots-iphone"
  build_app "iOS Simulator" "$IPHONE_UDID" "$dd"
  local app
  app=$(find_app "$dd" "iphonesimulator")
  [[ -z "$app" ]] && { warn "Could not locate Gus.app for iPhone"; return 1; }
  boot_sim "$IPHONE_UDID" "$IPHONE_NAME"
  terminate_app "$IPHONE_UDID"
  install_and_launch "$IPHONE_UDID" "$app"
  capture "$IPHONE_UDID" "$OUT/iphone" "01-connect"
  ok "iPhone: captured Connect screen (signed-in scenes require a live server)"
  terminate_app "$IPHONE_UDID"
}

capture_ipad() {
  local dd="$REPO_ROOT/build-screenshots-ipad"
  build_app "iOS Simulator" "$IPAD_UDID" "$dd"
  local app
  app=$(find_app "$dd" "iphonesimulator")
  [[ -z "$app" ]] && { warn "Could not locate Gus.app for iPad"; return 1; }
  boot_sim "$IPAD_UDID" "$IPAD_NAME"
  terminate_app "$IPAD_UDID"
  install_and_launch "$IPAD_UDID" "$app"
  capture "$IPAD_UDID" "$OUT/ipad" "01-connect"
  ok "iPad: captured Connect screen (signed-in scenes require a live server)"
  terminate_app "$IPAD_UDID"
}

capture_tv() {
  local dd="$REPO_ROOT/build-screenshots-tv"
  build_app "tvOS Simulator" "$TV_UDID" "$dd"
  local app
  app=$(find_app "$dd" "appletvsimulator")
  [[ -z "$app" ]] && { warn "Could not locate Gus.app for Apple TV"; return 1; }
  boot_sim "$TV_UDID" "$TV_NAME"
  terminate_app "$TV_UDID"
  install_and_launch "$TV_UDID" "$app"
  capture "$TV_UDID" "$OUT/tv" "01-connect"
  ok "TV: captured Connect screen (signed-in scenes require a live server)"
  terminate_app "$TV_UDID"
}

capture_vision() {
  local dd="$REPO_ROOT/build-screenshots-vision"
  build_app "visionOS Simulator" "$VISION_UDID" "$dd"
  local app
  app=$(find_app "$dd" "xrsimulator")
  [[ -z "$app" ]] && { warn "Could not locate Gus.app for Vision Pro"; return 1; }
  boot_sim "$VISION_UDID" "$VISION_NAME"
  terminate_app "$VISION_UDID"
  install_and_launch "$VISION_UDID" "$app"
  capture "$VISION_UDID" "$OUT/vision" "01-connect"
  ok "Vision Pro: captured Connect screen (signed-in scenes require a live server)"
  terminate_app "$VISION_UDID"
}

# ── Main ──────────────────────────────────────────────────────────────────────
TARGET="${1:-all}"

case "$TARGET" in
  --list)
    list_destinations
    exit 0
    ;;
  mac)
    mac_instructions
    exit 0
    ;;
  iphone) capture_iphone ;;
  ipad)   capture_ipad ;;
  tv)     capture_tv ;;
  vision) capture_vision ;;
  all)
    log "Capturing screenshots for all simulator platforms …"
    log "(macOS screenshots are manual — run: Scripts/screenshots.sh mac)"
    echo ""
    capture_iphone
    echo ""
    capture_ipad
    echo ""
    capture_tv
    echo ""
    capture_vision
    echo ""
    log "Done. Screenshots saved to Screenshots/"
    log "Signed-in scenes (Home, Detail, Player, etc.) require a live Jellyfin"
    log "server. See Documentation/AppStore/screenshots-and-testflight.md."
    ;;
  *)
    echo "Usage: $0 [--list | iphone | ipad | tv | vision | mac | all]"
    exit 1
    ;;
esac
