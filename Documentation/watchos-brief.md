# watchOS companion capabilities

GusWatch is a standalone-capable Jellyfin client embedded in the iOS archive.
It targets watchOS 26 or later. Its primary jobs are remote control and audio,
not full replacement browsing or playback.

## Current implementation

- Sign in with Quick Connect, restore from the Keychain, or optionally use
  WatchConnectivity handoff from iPhone. Credential and endpoint changes use
  the shared session lease.
- View and control eligible Jellyfin sessions. Remote monitoring uses socket
  updates and a bounded polling fallback only while frontmost. Quick resume
  can send playback to another client.
- Browse focused libraries and play music or audiobooks with native routing
  and Now Playing. On-watch downloads are audio-only with a 2 GB account
  budget and local delete controls.
- Video is constrained to foreground playback; offer remote playback when a
  source cannot play on Watch. Do not assume phone-class codecs or background video.

The separate target uses selected shared models, providers, services, stores
and playback code, plus Watch-specific UI. [Project configuration](../project.yml)
owns target membership. See [signing](AppStore/signing-capabilities.md#watchos-companion)
for the iOS archive's embedded Watch app.

## Validation and limits

Use the [local validation guide](local-validation.md) and the Gus watchOS Tests
scheme for affected tests. A generic Watch simulator build proves only
compilation. There is no hosted Watch simulator lane.

Keep paired-device and real-client acceptance separate: Quick Connect,
credential rotation and handoff, remote command readback, live updates and
polling fallback, native routing, playback and offline recovery, VoiceOver,
and a battery soak. These are verification targets, not results.
