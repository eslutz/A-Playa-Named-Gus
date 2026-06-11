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
#   Scripts/screenshots.sh watch      # capture watchOS companion only
#   Scripts/screenshots.sh mac        # print macOS manual instructions and exit
#
# Each platform captures the Connect screen, then — if Scripts/demo-server.sh is
# running — signed-in scenes over the local demo Jellyfin server: Home, Libraries,
# Settings, plus content deep-link scenes (movie detail, music album, book detail, and
# video playback via gus://item/<id> and gus://play/<id>). Home shows the Winter Chill
# theme + Liquid Glass; Settings shows the Appearance, Navigation, and Content
# Restrictions controls. The watch captures its Connect screen plus the signed-in
# Remote glance. TV-series and Live TV scenes need demo data the sample library
# doesn't have yet (no series, no tuner) — tracked in the ROADMAP.
#
# Output lands in Screenshots/<platform>/ (git-ignored).
# Run `xcodegen generate` before this script if the project is stale.
#
# Required: Xcode command-line tools, xcodegen, a booted macOS host.
# macOS screenshots are manual (see --mac notes at the end of this file).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="A Playa Named Gus"
SCHEME="$APP_NAME"
PROJECT="$REPO_ROOT/$APP_NAME.xcodeproj"
OUT="$REPO_ROOT/Screenshots"
BUNDLE_ID="dev.ericslutz.gus"
# The watch companion is a separate scheme/target/bundle id.
WATCH_SCHEME="Gus watchOS"
WATCH_BUNDLE_ID="dev.ericslutz.gus.watchkitapp"
SETTLE_SECONDS=4   # seconds to wait after launch before capturing

# ── Simulator devices (App Store required device/size per platform) ───────────
# UDIDs are resolved at runtime by name, preferring the newest runtime — the same
# device name often exists on multiple installed runtimes, and older runtimes can
# sit below the app's deployment target.
IPHONE_NAME="iPhone 17 Pro Max"               # iPhone 6.9" (1320×2868 @3x) slot
IPAD_NAME="iPad Pro 13-inch (M5)"             # iPad 13" (2064×2752 @2x) slot
TV_NAME="Apple TV 4K (3rd generation) (at 1080p)"  # Apple TV 1080p slot
VISION_NAME="Apple Vision Pro"                # Vision Pro (2980×2980) slot
WATCH_NAME="Apple Watch Ultra 3 (49mm)"       # Apple Watch Ultra (410×502) slot

resolve_udid() {
  xcrun simctl list -j devices available | python3 -c '
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)["devices"]
def runtime_key(rt):
    parts = rt.rsplit(".", 1)[-1].split("-")[1:]
    return tuple(int(p) for p in parts if p.isdigit())
best = None
for rt, devs in data.items():
    for d in devs:
        if d.get("name") == name and d.get("isAvailable", False):
            key = runtime_key(rt)
            if best is None or key > best[0]:
                best = (key, d["udid"])
print(best[1] if best else "")
' "$1"
}

IPHONE_UDID="$(resolve_udid "$IPHONE_NAME")"
IPAD_UDID="$(resolve_udid "$IPAD_NAME")"
TV_UDID="$(resolve_udid "$TV_NAME")"
VISION_UDID="$(resolve_udid "$VISION_NAME")"
WATCH_UDID="$(resolve_udid "$WATCH_NAME")"

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
  echo "  Watch   → $WATCH_NAME ($WATCH_UDID)"
  echo "  Mac     → manual (see mac instructions below)"
  echo ""
  echo "Verify UDIDs on this machine with:"
  echo "  xcodebuild -showdestinations -project '$APP_NAME.xcodeproj' -scheme '$SCHEME'"
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
    -name "$APP_NAME.app" -path "*$suffix*" | head -1
}

boot_sim() {
  local udid="$1" name="$2"
  if xcrun simctl list devices 2>/dev/null | grep "$udid" | grep -q "(Booted)"; then
    ok "$name already booted"
  else
    log "Booting $name …"
    xcrun simctl boot "$udid"
  fi
  # Block until the device has fully finished booting. Launching into a half-booted
  # SpringBoard can wedge `simctl launch` indefinitely, so this replaces a fixed sleep.
  log "Waiting for $name to finish booting …"
  xcrun simctl bootstatus "$udid" >/dev/null 2>&1 || true
}

install_and_launch() {
  local udid="$1" app_path="$2"
  shift 2
  log "Installing $(basename "$app_path") …"
  xcrun simctl install "$udid" "$app_path"
  log "Launching $BUNDLE_ID $* …"
  xcrun simctl launch "$udid" "$BUNDLE_ID" "$@" >/dev/null
  log "Settling for ${SETTLE_SECONDS}s …"
  sleep "$SETTLE_SECONDS"
}

# Relaunches the already-installed app with new launch arguments. Scenes differ
# only by arguments, so skipping the per-scene reinstall keeps relaunches fast —
# reinstall churn over a just-terminated instance can stall the next launch long
# enough that the capture catches the bare launch screen.
relaunch() {
  local udid="$1"
  shift
  terminate_app "$udid"
  sleep 1   # let the previous instance finish tearing down
  log "Launching $BUNDLE_ID $* …"
  xcrun simctl launch "$udid" "$BUNDLE_ID" "$@" >/dev/null
  log "Settling for ${SETTLE_SECONDS}s …"
  sleep "$SETTLE_SECONDS"
}

# Demo server (Scripts/demo-server.sh) lets us capture real signed-in scenes.
demo_server_running() {
  curl -fsS --max-time 2 "http://localhost:8096/System/Info/Public" >/dev/null 2>&1
}

# Representative demo item ids for content deep-link scenes (gus://item, gus://play),
# resolved once per run. Empty when a type isn't in the demo library.
DEMO_IDS_RESOLVED=""
DEMO_MOVIE_ID=""
DEMO_ALBUM_ID=""
DEMO_BOOK_ID=""

resolve_demo_ids() {
  [[ -n "$DEMO_IDS_RESOLVED" ]] && return 0
  DEMO_IDS_RESOLVED=1
  local auth token
  auth=$(curl -fsS --max-time 5 -X POST "http://localhost:8096/Users/AuthenticateByName" \
    -H 'Content-Type: application/json' \
    -H 'X-Emby-Authorization: MediaBrowser Client="GusShots", Device="shots", DeviceId="shots-1", Version="1.0"' \
    -d '{"Username":"gus","Pw":"playa-demo"}' 2>/dev/null) || return 0
  token=$(printf '%s' "$auth" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("AccessToken",""))' 2>/dev/null)
  [[ -z "$token" ]] && return 0

  demo_first_id() {
    curl -fsS --max-time 5 "http://localhost:8096/Items?IncludeItemTypes=$1&Recursive=true&Limit=1&SortBy=SortName" \
      -H "X-Emby-Token: $token" 2>/dev/null \
      | python3 -c 'import json,sys
items = json.load(sys.stdin).get("Items", [])
print(items[0]["Id"] if items else "")' 2>/dev/null
  }

  DEMO_MOVIE_ID=$(demo_first_id "Movie")
  DEMO_ALBUM_ID=$(demo_first_id "MusicAlbum")
  DEMO_BOOK_ID=$(demo_first_id "Book")
}

# Captures the signed-in scenes by relaunching (the app is already installed by
# the platform's Connect capture) with --gus-demo-server and a --gus-route
# destination per scene (external gus:// opens show a confirm dialog).
# Fixed routes cover Home/Libraries/Settings; content deep links (gus://item/<id>,
# gus://play/<id>) cover movie detail, music album, book detail, and video playback.
capture_signed_in_scenes() {
  local udid="$1" outdir="$2"

  relaunch "$udid" --gus-demo-server
  sleep 6   # extra settle: demo sign-in + Home load over localhost
  capture "$udid" "$outdir" "02-home"

  relaunch "$udid" --gus-demo-server --gus-route libraries
  sleep 6
  capture "$udid" "$outdir" "03-libraries"

  relaunch "$udid" --gus-demo-server --gus-route settings
  sleep 6
  capture "$udid" "$outdir" "04-settings"

  resolve_demo_ids

  if [[ -n "$DEMO_MOVIE_ID" ]]; then
    relaunch "$udid" --gus-demo-server --gus-route "item/$DEMO_MOVIE_ID"
    sleep 6
    capture "$udid" "$outdir" "05-movie-detail"
  fi

  if [[ -n "$DEMO_ALBUM_ID" ]]; then
    relaunch "$udid" --gus-demo-server --gus-route "item/$DEMO_ALBUM_ID"
    sleep 6
    capture "$udid" "$outdir" "06-album"
  fi

  if [[ -n "$DEMO_BOOK_ID" ]]; then
    relaunch "$udid" --gus-demo-server --gus-route "item/$DEMO_BOOK_ID"
    sleep 6
    capture "$udid" "$outdir" "07-book-detail"
  fi

  if [[ -n "$DEMO_MOVIE_ID" ]]; then
    relaunch "$udid" --gus-demo-server --gus-route "play/$DEMO_MOVIE_ID"
    sleep 14   # player spin-up + localhost HLS transcode start
    capture "$udid" "$outdir" "08-player"
  fi

  terminate_app "$udid"
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
  2. Resize the A Playa Named Gus window to 1280×800 (or drag to a Retina display for 2x).
  3. Use Cmd+Shift+4 → Space → click the A Playa Named Gus window to capture just the window.
  4. Repeat for each required scene (Connect, Home, Item Detail, Player, Downloads, and
     Settings → Appearance / Navigation / Content Restrictions).
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
  [[ -z "$app" ]] && { warn "Could not locate $APP_NAME.app for iPhone"; return 1; }
  boot_sim "$IPHONE_UDID" "$IPHONE_NAME"
  terminate_app "$IPHONE_UDID"
  install_and_launch "$IPHONE_UDID" "$app" --gus-skip-session-restore
  capture "$IPHONE_UDID" "$OUT/iphone" "01-connect"
  if demo_server_running; then
    capture_signed_in_scenes "$IPHONE_UDID" "$OUT/iphone"
    ok "iPhone: captured Connect + signed-in scenes"
  else
    ok "iPhone: captured Connect (start Scripts/demo-server.sh for signed-in scenes)"
  fi
  terminate_app "$IPHONE_UDID"
}

capture_ipad() {
  local dd="$REPO_ROOT/build-screenshots-ipad"
  build_app "iOS Simulator" "$IPAD_UDID" "$dd"
  local app
  app=$(find_app "$dd" "iphonesimulator")
  [[ -z "$app" ]] && { warn "Could not locate $APP_NAME.app for iPad"; return 1; }
  boot_sim "$IPAD_UDID" "$IPAD_NAME"
  terminate_app "$IPAD_UDID"
  install_and_launch "$IPAD_UDID" "$app" --gus-skip-session-restore
  capture "$IPAD_UDID" "$OUT/ipad" "01-connect"
  if demo_server_running; then
    capture_signed_in_scenes "$IPAD_UDID" "$OUT/ipad"
    ok "iPad: captured Connect + signed-in scenes"
  else
    ok "iPad: captured Connect (start Scripts/demo-server.sh for signed-in scenes)"
  fi
  terminate_app "$IPAD_UDID"
}

capture_tv() {
  local dd="$REPO_ROOT/build-screenshots-tv"
  build_app "tvOS Simulator" "$TV_UDID" "$dd"
  local app
  app=$(find_app "$dd" "appletvsimulator")
  [[ -z "$app" ]] && { warn "Could not locate $APP_NAME.app for Apple TV"; return 1; }
  boot_sim "$TV_UDID" "$TV_NAME"
  terminate_app "$TV_UDID"
  install_and_launch "$TV_UDID" "$app" --gus-skip-session-restore
  capture "$TV_UDID" "$OUT/tv" "01-connect"
  if demo_server_running; then
    capture_signed_in_scenes "$TV_UDID" "$OUT/tv"
    ok "TV: captured Connect + signed-in scenes"
  else
    ok "TV: captured Connect (start Scripts/demo-server.sh for signed-in scenes)"
  fi
  terminate_app "$TV_UDID"
}

capture_vision() {
  local dd="$REPO_ROOT/build-screenshots-vision"
  build_app "visionOS Simulator" "$VISION_UDID" "$dd"
  local app
  app=$(find_app "$dd" "xrsimulator")
  [[ -z "$app" ]] && { warn "Could not locate $APP_NAME.app for Vision Pro"; return 1; }
  boot_sim "$VISION_UDID" "$VISION_NAME"
  terminate_app "$VISION_UDID"
  install_and_launch "$VISION_UDID" "$app" --gus-skip-session-restore
  capture "$VISION_UDID" "$OUT/vision" "01-connect"
  if demo_server_running; then
    capture_signed_in_scenes "$VISION_UDID" "$OUT/vision"
    ok "Vision Pro: captured Connect + signed-in scenes"
  else
    ok "Vision Pro: captured Connect (start Scripts/demo-server.sh for signed-in scenes)"
  fi
  terminate_app "$VISION_UDID"
}

# The watch companion uses its own scheme/target/bundle id, has no AppRoute-based
# --gus-route navigation, and is signed out on a fresh install (no paired phone to hand
# off a credential), so it gets a self-contained capture path: Connect, then the
# signed-in Remote glance via --gus-demo-server.
capture_watch() {
  if [[ -z "$WATCH_UDID" ]]; then
    warn "No '$WATCH_NAME' watch simulator found — skipping watch screenshots"
    return 0
  fi
  local dd="$REPO_ROOT/build-screenshots-watch"
  log "Building watch companion ($WATCH_SCHEME) …"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$WATCH_SCHEME" \
    -destination "platform=watchOS Simulator,id=$WATCH_UDID" \
    -derivedDataPath "$dd" \
    -configuration Debug \
    build \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=NO \
    2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -5
  local app
  app=$(find "$dd/Build/Products" -maxdepth 3 -name "GusWatch.app" -path "*watchsimulator*" | head -1)
  [[ -z "$app" ]] && { warn "Could not locate GusWatch.app for Apple Watch"; return 1; }

  boot_sim "$WATCH_UDID" "$WATCH_NAME"
  xcrun simctl terminate "$WATCH_UDID" "$WATCH_BUNDLE_ID" 2>/dev/null || true
  log "Installing $(basename "$app") …"
  xcrun simctl install "$WATCH_UDID" "$app"
  # Fresh install with no paired phone is signed out → Connect screen.
  log "Launching $WATCH_BUNDLE_ID …"
  xcrun simctl launch "$WATCH_UDID" "$WATCH_BUNDLE_ID" >/dev/null
  sleep "$SETTLE_SECONDS"
  capture "$WATCH_UDID" "$OUT/watch" "01-connect"

  if demo_server_running; then
    xcrun simctl terminate "$WATCH_UDID" "$WATCH_BUNDLE_ID" 2>/dev/null || true
    log "Launching $WATCH_BUNDLE_ID --gus-demo-server …"
    xcrun simctl launch "$WATCH_UDID" "$WATCH_BUNDLE_ID" --gus-demo-server >/dev/null
    sleep 8   # demo sign-in over localhost + Sessions load
    capture "$WATCH_UDID" "$OUT/watch" "02-remote"
    ok "Watch: captured Connect + signed-in Remote"
  else
    ok "Watch: captured Connect (start Scripts/demo-server.sh for signed-in scenes)"
  fi
  xcrun simctl terminate "$WATCH_UDID" "$WATCH_BUNDLE_ID" 2>/dev/null || true
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
  watch)  capture_watch ;;
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
    capture_watch
    echo ""
    log "Done. Screenshots saved to Screenshots/"
    log "Signed-in scenes use the local demo server (Scripts/demo-server.sh start)."
    log "See Documentation/AppStore/screenshots-and-testflight.md and demo-server.md."
    ;;
  *)
    echo "Usage: $0 [--list | iphone | ipad | tv | vision | watch | mac | all]"
    exit 1
    ;;
esac
