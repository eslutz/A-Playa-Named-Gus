#!/bin/zsh
# Local demo Jellyfin server for screenshots, App Review walkthroughs, and testing.
#
# Runs the official jellyfin/jellyfin container with the rights-cleared sample_media/
# folder (not committed — see sample_media/README.md) mounted read-only, and automates
# the first-run wizard so a fresh `start` is immediately sign-in-able:
#
#   URL       http://localhost:8096
#   Username  gus
#   Password  playa-demo
#
# Usage:
#   Scripts/demo-server.sh start    # create/start the container; run setup on first start
#   Scripts/demo-server.sh stop     # stop the container (state preserved)
#   Scripts/demo-server.sh reset    # remove container + config volumes (media untouched)
#   Scripts/demo-server.sh status   # container + API health
#
# See Documentation/AppStore/demo-server.md for the demo-library workflow.
set -euo pipefail

CONTAINER="gus-demo-jellyfin"
IMAGE="jellyfin/jellyfin:latest"
PORT=8096
BASE_URL="http://localhost:${PORT}"
DEMO_USER="gus"
DEMO_PASSWORD="playa-demo"
SCRIPT_DIR="${0:A:h}"
MEDIA_DIR="${SCRIPT_DIR:h}/sample_media"
AUTH_HEADER='Authorization: MediaBrowser Client="GusDemoSetup", Device="script", DeviceId="gus-demo-setup", Version="1.0"'

wait_for_api() {
  for _ in $(seq 1 60); do
    if curl -fsS "$BASE_URL/System/Info/Public" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "error: Jellyfin API did not come up at $BASE_URL" >&2
  return 1
}

setup_needed() {
  # The wizard is pending until /Startup/Complete; public info reports StartupWizardCompleted.
  local completed
  completed=$(curl -fsS "$BASE_URL/System/Info/Public" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("StartupWizardCompleted", True))' 2>/dev/null || echo True)
  [[ "$completed" == "False" ]]
}

run_first_time_setup() {
  echo "Running first-run setup (user + libraries)…"
  curl -fsS -X POST "$BASE_URL/Startup/Configuration" -H "$AUTH_HEADER" -H 'Content-Type: application/json' \
    -d '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}' >/dev/null
  curl -fsS "$BASE_URL/Startup/User" -H "$AUTH_HEADER" >/dev/null
  curl -fsS -X POST "$BASE_URL/Startup/User" -H "$AUTH_HEADER" -H 'Content-Type: application/json' \
    -d "{\"Name\":\"$DEMO_USER\",\"Password\":\"$DEMO_PASSWORD\"}" >/dev/null
  curl -fsS -X POST "$BASE_URL/Startup/RemoteAccess" -H "$AUTH_HEADER" -H 'Content-Type: application/json' \
    -d '{"EnableRemoteAccess":true,"EnableAutomaticPortMapping":false}' >/dev/null
  curl -fsS -X POST "$BASE_URL/Startup/Complete" -H "$AUTH_HEADER" >/dev/null

  echo "Signing in to create libraries…"
  local token
  token=$(curl -fsS -X POST "$BASE_URL/Users/AuthenticateByName" -H "$AUTH_HEADER" -H 'Content-Type: application/json' \
    -d "{\"Username\":\"$DEMO_USER\",\"Pw\":\"$DEMO_PASSWORD\"}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["AccessToken"])')

  add_library() {
    # NB: don't name a local "path" — zsh ties $path to $PATH.
    local name="$1" type="$2" media_path="$3"
    curl -fsS -X POST "$BASE_URL/Library/VirtualFolders?name=$name&collectionType=$type&paths=$media_path&refreshLibrary=false" \
      -H "Authorization: MediaBrowser Token=\"$token\"" -H 'Content-Type: application/json' \
      -d '{"LibraryOptions":{"EnableRealtimeMonitor":false}}' >/dev/null
    echo "  added $name library ($media_path)"
  }

  add_library "Movies" "movies" "/media/Movies"
  add_library "Music" "music" "/media/Music"
  add_library "Photos" "homevideos" "/media/Photos"
  add_library "Books" "books" "/media/Books"

  curl -fsS -X POST "$BASE_URL/Library/Refresh" -H "Authorization: MediaBrowser Token=\"$token\"" >/dev/null
  echo "Library scan started."
}

case "${1:-start}" in
  start)
    if [[ ! -d "$MEDIA_DIR" ]]; then
      echo "error: $MEDIA_DIR not found — the demo media folder is required (see sample_media/README.md)" >&2
      exit 1
    fi
    if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
      docker start "$CONTAINER" >/dev/null
      echo "Started existing container $CONTAINER."
    else
      docker run -d --name "$CONTAINER" \
        -p "$PORT:8096" \
        -v gus-demo-jellyfin-config:/config \
        -v gus-demo-jellyfin-cache:/cache \
        -v "$MEDIA_DIR:/media:ro" \
        "$IMAGE" >/dev/null
      echo "Created container $CONTAINER."
    fi
    wait_for_api
    if setup_needed; then
      run_first_time_setup
    fi
    echo "Demo Jellyfin ready: $BASE_URL (user: $DEMO_USER / $DEMO_PASSWORD)"
    ;;
  stop)
    docker stop "$CONTAINER" >/dev/null && echo "Stopped $CONTAINER."
    ;;
  reset)
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    docker volume rm gus-demo-jellyfin-config gus-demo-jellyfin-cache >/dev/null 2>&1 || true
    echo "Removed container and config volumes (media folder untouched)."
    ;;
  status)
    docker ps -a --filter "name=$CONTAINER" --format 'container: {{.Status}}' || true
    if curl -fsS "$BASE_URL/System/Info/Public" >/dev/null 2>&1; then
      echo "api: responding at $BASE_URL"
    else
      echo "api: not responding"
    fi
    ;;
  *)
    echo "usage: $0 {start|stop|reset|status}" >&2
    exit 64
    ;;
esac
