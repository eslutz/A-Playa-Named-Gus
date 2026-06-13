# 0010 — watchOS companion app and session-based remote control

Date: 2026-06-10
Status: accepted

## Context

The roadmap's "watchOS companion" future feature calls for a focused watch experience —
a remote for the household's other Jellyfin players first, a lightweight standalone
client second — without making the watch a primary video client. The product brief
(`Documentation/watchos-brief.md`) defined the v1 scope; this ADR records the
architectural decisions made implementing it.

Three questions needed answering: how the watch target shares code with the five-platform
app, whether it is companion-only or standalone-capable, and how remote control of other
clients fits the provider architecture (M7) without leaking Jellyfin specifics.

## Decision

**A second application target, `GusWatch`**, embedded inside the iOS app archive (no
separate App Store record) and **standalone-capable**
(`WKRunsIndependentlyOfCompanionApp`). The watch is useful without the phone: it signs in
on its own via Quick Connect (ideal for the watch — display a code, approve elsewhere),
and WatchConnectivity hand-off from the iPhone (`WatchSessionRelay` /
`WatchCredentialReceiver`) is an *accelerator*, not a dependency.

**Shared-code subset, not the whole app.** Feature views assume the desktop/TV platforms,
so the watch target compiles only the verified subset — `Models/`, `Providers/`,
`Services/`, and the non-video `Stores/` (no `PlaybackStore`) — plus
platform-neutral `NowPlayingController`, `NowPlayingArtworkFactory`,
`DownloadsAvailability`, and `LoadingStateView`. The watch UI lives in `Sources/Watch`.
XcodeGen `sources` lists enumerate the subset; this is the same exclusion discipline the
TopShelf and CarPlay code already use.

**Remote control rides the Jellyfin `Sessions` API**, behind a `providerKind` gate exactly
like remote sessions (`RemoteSessionsStore` + `SessionsSocket`), rather than joining the shared
`MediaProviderSession` contract. The session-based control model (list controllable
clients, `Sessions/{id}/Playing/{command}`, `Sessions/{id}/Command`, `Sessions/{id}/Playing`
to start playback, WebSocket session events with a polling fallback) is intentionally
provider-specific; per the roadmap it also serves the future Emby provider's
cross-device control. Live updates run only while a remote surface is frontmost (battery
rule), and on-watch audio reuses the shared `AudioPlayerStore` queue engine with watchOS
`.longFormAudio` routing.

## Consequences

- The watch target needs no extra entitlement (URLSession, data-protection Keychain,
  WatchConnectivity). It ships and is signed as part of the iOS app archive in Xcode
  Cloud; CI gains a watchOS build lane (kept out of the required unit-test matrix, like
  UI tests).
- `Sessions`-based remote control is a Jellyfin-gated subsystem,
  outside the provider contract. When the Emby provider arrives, the shared remote-control
  surface is the place to generalize it (or keep parallel provider-gated implementations),
  not the `MediaProviderSession` protocol.
- Constrained on-watch video uses the native `VideoPlayer` (available on watchOS 7+) and
  is explicitly a novelty path — failures offer remote playback instead.
- The brief's on-device verification matrix (real-client remote control, route-picker
  audio, battery soak, WatchConnectivity hand-off) is hardware-only and remains a release
  task; the simulator covers compilation and flow wiring.
