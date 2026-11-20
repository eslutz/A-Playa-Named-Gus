# Demo media server

This disposable Jellyfin fixture serves rights-cleared local media, not a
personal library. It supports signed-in simulator testing, screenshot capture,
performance measurements and real playback. Keep the untracked sample media
and provenance with its local README.

## Start, inspect, or reset

Run from the Gus checkout root with Docker running and curl and Python 3
available. The first start initializes a demo user, creates libraries from the
read-only media mount and requests a scan. It uses the Jellyfin latest image;
record the exact server version when comparing results.

```sh
Scripts/demo-server.sh start
Scripts/demo-server.sh status
Scripts/demo-server.sh stop
```

| Setting | Default |
| --- | --- |
| URL | http://localhost:8096 |
| Demo credentials | gus / playa-demo (disposable local fixture only) |
| Libraries | Movies, Music, Photos, Books; Shows if the media folder contains a Shows directory |
| Overrides | GUS_DEMO_CONTAINER, GUS_DEMO_PORT, GUS_DEMO_MEDIA_DIR |

Status reports the container and public API response, not scan completion.
Before using the fixture, verify the expected titles are visible. Stop retains
state. Use reset only when you intend to discard the selected demo container,
configuration and cache volumes; it leaves the source media untouched.
Use a separate container name/port for an isolated scenario.

## Connect Gus

- Debug: use the Use Local Demo Server button or launch with --gus-demo-server.
- For a custom port, set the app's DEBUG GUS_DEMO_URL to the matching loopback
  HTTP URL. The override rejects non-loopback hosts and credentials in the URL;
  GUS_DEMO_USERNAME and GUS_DEMO_PASSWORD are separate debug account overrides.
- Any build can connect manually to the fixture from a simulator or host that
  can reach it. Use the [local validation guide](local-validation.md) for
  target selection and evidence.

## Network and reviewer access

This fixture is intended for local development, but Docker's published port
does not request a loopback-only bind, and the script enables Jellyfin remote
access. Keep it on a trusted, controlled development network. Do not forward the
port or expose the default fixture configuration or credentials to the public.

If reviewer access is needed, separately provision a reachable HTTPS demo with
distinct credentials, rights-cleared content, and no personal media. Supply the
approved reviewer URL and credentials privately in App Store Connect; reviewers
cannot use your localhost fixture. This guide does not deploy a server.
