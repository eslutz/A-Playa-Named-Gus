# Gus engineering guide

Read [AGENTS.md](../AGENTS.md) for project rules. This orientation guide explains
implementation boundaries; verify precise behavior in source and tests before
changing it. See [ADRs](adr/) for why these decisions were made, and the
[behavior and regression guide](behavior-and-regression-guide.md) for cross-cutting contracts.

## Operational runbooks

- [Demo server](demo-server.md): rights-cleared Jellyfin fixtures and local sign-in.
- [Diagnostics and reliability](diagnostics-reliability.md): logging, performance
  measurement, diagnostic export, and privacy boundaries.
- [Universal Links](universal-links.md): domain association, routing, and validation.

## Architecture

The main SwiftUI target has four XcodeGen destinations: iOS (iPhone and iPad),
tvOS, visionOS, and macOS. Watch has its own app target. SwiftUI
lifecycle (`@main struct GusApp: App`), with a minimal iOS `UIApplicationDelegateAdaptor`
only for background URLSession wake/completion events (ADR 0005). Source is layered under `Sources/`:

```
App/        @main entry + RootView (signed-out vs signed-in switch) + GusAppIntents.swift
Models/     Codable value types (ServerConnection, StoredUser, SessionCredential, ContentLink)
Services/   Service boundaries: client factory, device identity, Keychain, persistence,
            image/stream URL builders, diagnostics (DiagnosticsHub/MetricKitCollector),
            content rating gate, Sessions socket, WatchConnectivity relay,
            SpotlightIndexer
Stores/     @Observable state objects — AudioPlayerStore (song/audiobook queue),
            SharePlayCoordinator + RemoteSessionsStore (Jellyfin-gated),
            NavigationPreferencesStore (customizable nav)
Features/   One folder per screen area (Connect, Home, Item, Player, Settings, Music,
            Photos, LiveTV, Books)
SharedUI/   Reusable views (AsyncPoster, PosterCard, LoadingStateView, RestrictedContentView)
            + display helpers, GlassStyle (Liquid Glass), AppearanceSetting
Platform/   substantial #if os(...) divergence lives here (RootContainer, modifiers, nav,
            ContentLinkHandler, UserActivities, DownloadsAvailability)
Immersive/  visionOS-only RealityKit "Gus Cinema"
TopShelf/   tvOS Top Shelf extension entry point
CarPlay/    iOS-only CarPlay audio templates and Siri media intent handling
Watch/      watchOS companion app UI (GusWatch target)
```

### State & dependency injection

State objects are `@Observable @MainActor` classes (Observation framework — not
`ObservableObject`/Combine). Injected via `@Environment` at root, read with
`@Environment(Type.self)`.

- `AppModel` owns the known servers/users list and the optional `currentSession`; funnels
  connect / sign-in / restore / sign-out.
- `RootView` switches on `AppModel.currentSession`: `nil` → `ConnectFlowView`; otherwise
  injects a `SessionStore` (authenticated `JellyfinClient` + user + server) into the signed-in tree.
- Feature stores take a `SessionStore` and use its media provider. `RootNavigationState`
  owns Home, weak library/detail store lookups, window-owned global Search results, navigation paths,
  per-library display choices, profile presentation, and scroll anchors for the signed-in account; adaptive view replacement reuses that state.
  `RootView` owns `AudioPlaybackCoordinator` and stops it when the active session lease changes.
- `SavedMediaStore` owns supplemental Gus intent, cursors, activity and its CloudKit
  journal. `ServerMediaListsStore` owns the account-scoped native-list cache and offline
  edit journal; Jellyfin owns names, membership and ordering. Current serialized paths,
  cloud IDs and offline-draft reconciliation stay stable.

### Swift concurrency boundaries

The app uses complete concurrency checking. Watch, Top Shelf, tvOS and visionOS use
Swift 6 language mode; iOS and macOS remain in Swift 5 mode pending the boundaries
below. Configuration alone does not prove a warning-free build.

- Readium's asynchronous asset retrieval, publication opening and navigation APIs
  use non-Sendable objects in the MainActor reader model. Resolve upstream isolation
  or introduce a reviewed confined service before migrating the iOS target; an
  unchecked conformance alone is not proof of safety.
- SwiftUI's `DeclaredAgeRangeAction` has an unannotated asynchronous boundary on
  iOS/macOS. The settings flow permits one request at a time and retains a manual
  content-limit fallback. Entitlement and device acceptance remain separate.
- Preserve the documented ownership around download delegate locks, callback bridges,
  cancellation and the ordered audio-session queue when changing those systems.

The deployment floor is OS 26.0; newer APIs require availability checks. Exact
minimum-runtime execution remains a separate acceptance gate.

### Auth & session flow

Connect normalizes a URL → tokenless `JellyfinClient` → `Paths.getPublicSystemInfo`
(following any redirect) → persist a `ServerConnection`. Password and Quick Connect authentication feed the same session installation path.
The token is stored in the **Keychain** (`KeychainStore`, account
`"<provider>:<serverID>:<userID>"`); a token-free `StoredUser` is persisted via `ServerStore`
(Codable JSON in Application Support). On launch, `AppModel.restoreLastSession()` rebuilds
an authenticated client from the stored token silently.

Normal authenticated activation uses the same async AppModel installation path and
immutable `SessionLease`. Credential or endpoint changes retire the old lease;
profile-only changes keep it. Retirement checkpoints players and gives their
originating report queue up to five seconds to flush. Typed authenticated 401
recovery locks the expired account while preserving current data; 403 is a permission
failure. Explicit Sign Out retains its separate deletion policy.

### Navigation

Navigation divergence is isolated in `Platform/RootContainer.swift`: compact-width
iOS uses `TabView`; tvOS and visionOS use `TabView` with `.sidebarAdaptable`;
regular-width iOS and macOS use `NavigationSplitView`. Each signed-in stack registers its value destinations at the root.
Fixed app routes for `gus://home`, `gus://search` and `gus://settings` are
shared by URL opens, menu commands and the tvOS Top Shelf extension.

Compact iPhone navigation shows three content tabs, More when needed, and Search.
The default content tabs are Home, Movies and Series when available. A saved
account order determines the first three visible sections. Vision Pro shows up to
seven sections alongside Search, or six sections plus More and Search.
More presents its overflow sections as native pushes. Each section retains its
value-based child path when moving between a direct tab, More and the sidebar.

Discover's catalog, title, credits and season routes use the same stack as
Open in Gus and subsequent Jellyfin detail pushes. Each Discover route belongs
to the current Seerr connection revision. A connection change truncates the
path at the first stale route, including any Jellyfin pages pushed above it.

Selecting a genre, studio or credit pushes related results in the current stack,
including when a content link opened the detail in a sheet. Native Back returns
through the same pages. Each related destination owns its paged results and
viewport while it is on the stack. The window retains its text search, and
Clear Results returns that search to Recent Searches. The last 20 completed
searches belong to the signed-in account on this device.

**Content deep links** (`gus://item/<id>`, `gus://play/<id>` — `Models/ContentLink.swift`)
ride `AppNavigationModel` via a consume-once pending-link; `Platform/ContentLinkHandler.swift`
resolves the id through the session's provider. iPad and tvOS item links push into the selected
section's normal stack; iPad photos open the fullscreen session viewer. Other platforms present a detail sheet. Session player hosts sit
above adaptive layout replacement, with the detail sheet hosting playback while it is open.
Content links are the shared entry point for: **Handoff** (`Platform/UserActivities.swift`
— detail/player surfaces publish identity and sanitized playback intent, never tokens), **Core
Spotlight** (`Services/SpotlightIndexer.swift` — donates browsed items, refuses
other-account continuations, deindexes on sign-out; no watchOS/tvOS), **Siri/App Intents**
(`App/GusAppIntents.swift` — "Play media" provider search), and the **content-aware tvOS
Top Shelf** (Continue Watching snapshot via the `group.dev.ericslutz.gus` App Group,
written by `HomeStore`, read by the credential-free `GusTopShelf` extension).

### Playback

`PlaybackRequest` carries source, semantic track/subtitle intent, start position and
presentation through local/remote playback, queues, Watch, Mac windows, Handoff and
SharePlay. Version changes require Start Over or explicit timestamp reuse. Per-account
track remembering is opt-in and same-series only; persisted preferences contain no
source-local indexes. Missing/ambiguous named tracks use defaults with a notice.

**Video:** `StreamURLBuilder` POSTs `Paths.getPostedPlaybackInfo` with a `DeviceProfile`
that prefers **direct play** when the source, container, codecs, device capability,
HDR, and selected tracks allow it
(`DevicePlaybackCapabilities` gates HEVC/AV1 on `VTIsHardwareDecodeSupported` — guarded
`canImport(VideoToolbox)` for watchOS — and HDR ranges on `AVPlayer.eligibleForHDRPlayback`),
routing raw TS/M2TS through HLS (including Blu-ray sources with mixed audio codecs),
falling back to HEVC-preferred fMP4 HLS transcoding with 8-channel audio and
`enableSubtitlesInManifest` (bitmap subs burn in; text subs ride the manifest).
`PlaybackStore` owns the `AVPlayer` and tears it down on dismiss; it sets
`AVPlayerItem.externalMetadata` (not on macOS — no API), auto-plays next episodes or
dismisses at natural end (`PlaybackPreferences`), enqueues pause/resume snapshots on the
session-owned `PlaybackReportQueue`, and
reads the Settings-backed `PlaybackQuality` bitrate cap. Track switching is in-place via
`AVMediaSelection` for direct play (`PlaybackMediaSelectionMatcher`, ordinal+language)
with a server-side rebuild fallback. Surfaces: `AVPlayerViewController` on iOS
and tvOS, and on visionOS where its experience controller supports expanded and
immersive playback. iOS and visionOS video suppress AVKit automatic Now Playing
publishing so app-managed metadata does not compete with it. macOS uses `AVPlayerView` in the dedicated `GusPlayerWindow` scene, not a sheet. `NowPlayingController`
feeds `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`. `AVAudioSession` is guarded
(`#if os(iOS) || os(tvOS) || os(visionOS)` — doesn't exist on macOS).

**Audio:** songs and audiobooks play through `AudioPlayerStore` + `AudioPlayerView` (paged
queue, full-collection shuffle, repeat, speed, chapters) using provider-negotiated audio
with the selected source and track intent.
`playerPresentation` routes by `MediaItem.isAudioPlayable`.
`AudioPlaybackCoordinator` owns the queue and preparation task independently of the player
presentation. Close dismisses prepared iOS and tvOS audio while playback continues; the persistent Now
Playing control reopens it. Non-iOS playback retains its platform controls. Closing during preparation cancels
the task. Audio/video stores reject late results after cancellation or teardown; loading
and failed player states expose cancellation and retry. The Watch companion uses its own
scrollable audio sheet and tears down playback when leaving that sheet.

One 30-second resolution budget includes metadata, safe read retries and fallbacks;
allocating requests are not blindly repeated. Native readiness has a separate
45-second bound. Reports and known-resource cleanup have five-second request bounds.
Terminal work retains its originating transport after lease retirement. Unknown
allocation IDs cannot be claimed closed; see `Documentation/behavior-and-regression-guide.md`.

**visionOS 3D:** `Media3DDetector` maps Jellyfin SBS/TAB/MVC metadata into a
`Stereo3DPresentation`; non-visionOS always resolves to 2D. SBS/TAB use Gus Cinema
`ImmersiveSpace` (`StereoFrameRenderer` splits packed frames into per-eye `CVPixelBuffer`s
via `CMTaggedBufferGroup`; that RealityKit path sets stereo viewing mode).
MV-HEVC uses AVKit native spatial playback; MVC remains unsupported.

**Downloads** (`OfflineDownloadStore` + `DownloadSessionCoordinator`): background
`URLSessionConfiguration.background` download session. AVPlayer-native originals use
`Paths.getDownload` for the primary source or source-qualified static streams for
alternate versions. Incompatible video uses progressive MP4 conversion; incompatible
audio uses MP3, with explicit tracks sent through the source-qualified audio endpoint.
Records and local checkpoints retain known source identity. File preparation/finalization
runs on a serial worker with a generation-checked metadata commit before completion
acknowledgment. Unreadable metadata preserves files and exposes native retry UI.
Platform availability routed through `Platform/DownloadsAvailability.swift`. tvOS excluded.

**Artwork:** shared role/rendition requests feed native AsyncImage and ordered fallbacks.
OS 26 keeps its native transport; OS 27 inherits `NativeArtworkTransport` from the
credential lease, using a memory-only cache cleared when the lease retires. Do not claim
that OS 26 AsyncImage uses the Jellyfin SDK's URLSession or cache.

### watchOS companion

`GusWatch` is a second application target (`WKRunsIndependentlyOfCompanionApp`), embedded
in the iOS app bundle under `Watch/`. Compiles the shared subset — `Models/`, `Providers/`, `Services/`, and
selected `Stores`, including the shared `PlaybackStore` lifecycle — plus `Sources/Watch`. Remote
control rides `RemoteSessionsStore` + `SessionsSocket`; credentials hand off from iPhone
via `WatchSessionRelay` / `WatchCredentialReceiver`.

## Apple-first technology mapping

| Concern | Use |
|---|---|
| Navigation/routing | `NavigationStack` / `NavigationSplitView` / `TabView` |
| State / DI | Observation `@Observable` + `@Environment` |
| Playback | AVKit (`AVPlayerViewController` or `AVPlayerView` on macOS); no VLCKit |
| Images | Native `AsyncImage`; lease-owned memory cache on OS 27, native transport on OS 26 |
| Secrets | Security framework `SecItem*` |
| Persistence | `Codable` + `FileManager`; `UserDefaults`/`@AppStorage` for prefs |
| Theming | `AccentColor`, semantic colors, system Materials, SF Symbols, Dynamic Type |
| Now Playing | MediaPlayer (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`) |
| Downloads | Background `URLSessionDownloadTask`, `FileManager`, `Codable` |
| Logging | `OSLog` `Logger` |
| Localized strings | String Catalog (`Localizable.xcstrings`) |
| Immersive / 3D (visionOS) | RealityKit + `ImmersiveSpace` for Cinema/SBS/TAB; AVKit for MV-HEVC |
