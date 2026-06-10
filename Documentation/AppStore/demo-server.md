# Demo Media Server

A local Jellyfin container serving the rights-cleared `sample_media/` library (not
committed — provenance in `sample_media/README.md`). It backs App Store screenshots,
reviewer/tester walkthroughs, performance baseline measurement, and local testing of the
full signed-in experience — including real playback — with no personal library involved.

## Usage

```sh
Scripts/demo-server.sh start    # create/start; first run auto-completes Jellyfin setup
Scripts/demo-server.sh stop     # stop, keep state
Scripts/demo-server.sh reset    # remove container + config volumes (media untouched)
Scripts/demo-server.sh status   # container + API health
```

| | |
|---|---|
| URL | `http://localhost:8096` |
| Username | `gus` |
| Password | `playa-demo` |
| Libraries | Movies, Music, Photos, Books (from `sample_media/`) |

The first `start` automates the Jellyfin startup wizard (locale, demo user, remote
access), creates the four libraries against the read-only `/media` mount, and triggers a
scan. Requires Docker.

## Connecting the app

- **Launch argument** `--gus-demo-server` (Debug builds): connects and signs in
  automatically on launch — used by `Scripts/screenshots.sh` and simulator validation.
- **Connect screen** (Debug builds): "Use Local Demo Server" button below Local Servers.
- **Manually** (any build): enter `http://localhost:8096` and sign in with the demo
  credentials. Simulators share the host network, so `localhost` reaches the container
  from iOS/tvOS/visionOS simulators and the macOS app alike.

## App Review / TestFlight

For App Review demo access, host the same setup on a reachable HTTPS server (the
container + `sample_media/` folder are portable) and supply that URL plus the demo
credentials in the review notes — review can't reach `localhost`. All media is
public-domain/CC0 per `sample_media/README.md`; confirm provenance before adding any new
demo asset.
