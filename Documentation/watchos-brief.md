# watchOS Companion — Product Brief

Status: brief (the Future Features acceptance artifact). Implementation follows as its
own milestone once the 1.0 launch scope is stable.

## Version 1 feature set

1. **Session status glance** — active server name, signed-in user, connection state.
2. **Now Playing remote control** — observe the household's active Jellyfin sessions
   (`Sessions` API) and control any controllable client: play/pause, seek ±, volume,
   stop. This is the watch's highest-value job: a remote for the TV/desktop player.
3. **Live session updates** — keep the active remote-control screen in sync through the
   Jellyfin WebSocket when available, with a timed `Sessions` API polling fallback. This
   means the watch listens for server/player changes instead of repeatedly asking the
   server "what changed?" every few seconds.
4. **Quick resume** — top 3 Continue Watching items; tapping sends `Sessions/{id}/Playing`
   to a selected target client (not on-watch playback).
5. **Lightweight library browsing** — shallow Movies, Shows, Music, Books, and Libraries
   entry points optimized for the watch, focused on recent/resumable/favorite content
   rather than full replacement browsing.
6. **Direct audio playback** — music/audiobook playback on the watch speaker or
   paired AirPods via the universal audio endpoint (`StreamURLBuilder.universalAudioURL`),
   reusing `AudioPlayerStore`'s queue engine.
7. **Offline audio downloads** — audio-only music/audiobook downloads with a conservative
   watch storage budget and clear delete controls.
8. **Constrained direct video playback** — a secondary, novelty path for short,
   watch-appropriate video playback using native playback APIs where watchOS supports it.
   It must not become the primary use case or drive custom video UI; unsupported sources
   should offer remote playback to another client instead.

## Companion-only vs standalone

**Standalone-capable** (watchOS app without phone dependency) is the recommendation:
- The Jellyfin stack is plain `URLSession` + Keychain — both fully available on watchOS.
- Sign-in: Quick Connect is ideal for watch (code display + approve on another device);
  `QuickConnectStore` already implements the polling flow.
- WatchConnectivity session hand-off from the iPhone (silently sharing the stored token)
  is an *accelerator*, not a dependency: implement `WCSession` transfer of the
  `SessionCredential` account + token after standalone sign-in works.

## Shared-code subset (verified dependency closure)

The watch target must NOT compile all of `Sources/` (feature views assume the five
desktop/TV platforms). The compiling subset for the watch target:

- `Models/` — all (Foundation-only Codable).
- `Providers/` — all (Foundation + JellyfinAPI; `jellyfin-sdk-swift` declares watchOS
  support in its package platforms — verify at integration).
- `Services/` — `KeychainStore`, `ServerStore`, `AppStorageLocation`,
  `JellyfinClientFactory`, `GusError`, `NetworkRetryPolicy`, `Logger+Gus`,
  `ImageURLBuilder`, `StreamURLBuilder`, `Media3DDetector` (type dependency of the
  provider contract), `DiagnosticsHub`/`DiagnosticSummary` (MetricKit excluded —
  watchOS gap documented like tvOS).
- `Stores/` — `AppModel`, `SessionStore`, `QuickConnectStore`, `PlaybackReporting`,
  `AudioPlayerStore` + `AudioQueue`, plus a watch-specific offline-audio store if the
  existing download store cannot be narrowed safely for watchOS.
- **Excluded:** `Features/`, `Platform/`, `SharedUI/`, `Immersive/`, `TopShelf/`,
  `CarPlay/`, and the existing five-platform `PlaybackStore` video surface.
- New: `Sources/Watch/` — WKApplication SwiftUI app, glance views, remote-control UI,
  lightweight browse views, audio player UI, offline-audio UI, and constrained video UI.

## Jellyfin API requirements

- Existing: auth, Quick Connect, `getResumeItems`, image URLs, universal audio, item
  browsing/search, download/progressive audio URLs, and playback URL resolution.
- New provider surface (watch milestone adds to the Jellyfin session, gated like
  SyncPlay): `getSessions` (controllable clients), `Sessions/{id}/Playing/{command}`
  (remote transport), `Sessions/{id}/Command` (volume/mute), and WebSocket-backed session
  update events with an HTTP polling fallback.
- The session-based remote-control model also serves the future Emby provider per the
  roadmap's cross-device playback-control plans.

## Battery / storage / network tradeoffs

- Use WebSocket session updates only while the remote-control UI is active. Do not keep a
  background socket alive after watchOS suspends the app. If WebSocket is unavailable,
  poll sessions only while the remote-control screen is frontmost (15 s cadence).
- Image loading capped at watch-resolution widths through `ImageURLBuilder` contexts.
- Offline audio: cap well below watch storage (e.g. 2 GB), audio-only,
  Wi-Fi-or-charging transfers per `URLSession` background semantics on watchOS.
- On-watch video: user-initiated foreground playback only, conservative bitrate choices,
  no background video assumptions, and remote-playback fallback whenever the watch cannot
  play the source cleanly.

## Build / CI integration

- `project.yml`: new `GusWatch` application target (platform watchOS, deployment
  watchOS 11), shared files via target membership (XcodeGen `sources` lists), own
  Info.plist + asset catalog reusing the AppIcon artwork.
- CI: add a watchOS simulator build lane; keep it out of the required unit-test matrix
  until the target stabilizes (mirrors how UI tests are staged).
- App Store: watch app ships inside the iOS app archive; no separate record.

## Verification matrix

Standalone sign-in (Quick Connect), session restore from Keychain, remote control
against a real client (pause/seek/volume), WebSocket session updates plus polling
fallback, quick-resume send, lightweight library browsing, WatchConnectivity token
hand-off, audio playback with Now Playing on watch, offline audio download/delete, a
30-minute audio battery soak, and constrained direct video playback with remote-playback
fallback for unsupported media.
