# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## What A Playa Named Gus Is

A Playa Named Gus is an **Apple-first, multiplatform SwiftUI Jellyfin client** — one app
that aims to feel first-party on **iOS, iPadOS, tvOS, visionOS, and macOS**, plus a
**watchOS companion** (`GusWatch`, a focused remote/standalone client — not a primary
video client). Bundle id `dev.ericslutz.gus`; named for *Psych*.

### The core mandate: native APIs over custom code

This is the project's defining constraint — **prefer Apple/system frameworks over custom
or third-party code.** Before writing anything bespoke (a control, a cache, a router, a
theming system), look for the system API that already does it and use that instead. The
first-party *feel* comes from using the system's adaptive components and **never overriding
their look**.

- Third-party *runtime* dependencies are limited to `jellyfin-sdk-swift` (`from: 2.1.0`)
  plus, on iOS/iPadOS only, the Readium toolkit for in-app EPUB reading (ADR 0009 — no
  system API renders EPUB; tvOS/macOS don't link it by design, visionOS is blocked on an
  upstream xrOS compile fix). Do not add others without an explicit ADR.
- When a feature could be built custom or with a system API, the system API wins unless it
  genuinely can't do the job — and that exception should be called out in the PR/commit.

---

## Commands

The Xcode project is **generated** from `project.yml` by XcodeGen;
`A Playa Named Gus.xcodeproj` is git-ignored. `project.yml` is the source of truth.

```sh
brew install xcodegen          # one-time
xcodegen generate              # regenerate — REQUIRED after adding/removing any file
xcodebuild -resolvePackageDependencies -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus'
Scripts/format.sh              # format Sources + Tests with SwiftFormat
swiftformat Sources Tests --lint
```

**Always run `xcodegen generate` after adding, renaming, or deleting a source/resource
file** — XcodeGen globs the file tree at generation time.

List actually-installed simulators before building (simulator names drift between Xcode
versions):

```sh
xcodebuild -showdestinations -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus'
```

Build each destination:

```sh
xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' build
xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build
xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' \
  -destination 'platform=macOS' build
# visionOS: TWO "Apple Vision Pro" sims exist (1.2 and 26.5) — target by id, not name
xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' \
  -destination 'platform=visionOS Simulator,id=<UUID>' build
# watchOS
xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus watchOS' \
  -destination 'generic/platform=watchOS Simulator' build
```

Launch + smoke-test on a simulator:

```sh
xcrun simctl boot 'iPhone 17'; open -a Simulator
xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build build
xcrun simctl install booted \
  "$(find build/Build/Products/Debug-iphonesimulator -name 'A Playa Named Gus.app' | head -1)"
xcrun simctl launch booted dev.ericslutz.gus
```

Scope `find` to the right product dir (`Debug-iphonesimulator`, `Debug-appletvsimulator`,
etc.) — a bare `find build` can grab another platform's product.

Run tests (CI-style schemes):

```sh
xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' \
  -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus tvOS Unit Tests' \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'
xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus macOS Unit Tests' \
  -destination 'platform=macOS'
xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus visionOS Unit Tests' \
  -destination 'platform=visionOS Simulator,id=<UUID>'
```

Run a single Swift Testing test:

```sh
xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:GusTests/<Suite>/<test>
```

`GusTests`/`GusTVOSTests`/`GusVisionOSTests`/`GusMacOSTests` cover shared pure logic with
Swift Testing and are the only test bundles run in CI. The matching `Gus iOS Tests`/
`Gus tvOS Tests`/etc. schemes are narrow local smoke tests for the Connect screen.

Screenshot automation:

```sh
# start the demo server first
Scripts/demo-server.sh
# capture all scenes for one platform (iphone | ipad | tv | vision | watch)
Scripts/screenshots.sh iphone
```

---

## Architecture

A single multiplatform SwiftUI app target, five Supported Destinations. Pure SwiftUI
lifecycle (`@main struct GusApp: App`), no AppDelegate. Source is layered under `Sources/`:

```
App/        @main entry + RootView (signed-out vs signed-in switch) + GusAppIntents.swift
Models/     Codable value types (ServerConnection, StoredUser, SessionCredential, ContentLink)
Services/   Stateless helpers: client factory, device identity, Keychain, persistence,
            image/stream URL builders, diagnostics (DiagnosticsHub/MetricKitCollector),
            content rating gate, SyncPlay + Sessions sockets, WatchConnectivity relay,
            SpotlightIndexer
Stores/     @Observable state objects — AudioPlayerStore (song/audiobook queue),
            SyncPlayStore + RemoteSessionsStore (Jellyfin-gated),
            NavigationPreferencesStore (customizable nav)
Features/   One folder per screen area (Connect, Home, Item, Player, Settings, Music,
            Photos, LiveTV, Books)
SharedUI/   Reusable views (AsyncPoster, PosterCard, LoadingStateView, RestrictedContentView)
            + display helpers, GlassStyle (Liquid Glass), AppearanceSetting
Platform/   ALL #if os(...) divergence lives here (RootContainer, modifiers, nav,
            ContentLinkHandler, UserActivities, DownloadsAvailability)
Immersive/  visionOS-only RealityKit "Gus Cinema"
TopShelf/   tvOS Top Shelf extension entry point
CarPlay/    iOS-only CarPlay audio templates (inert until carplay-audio entitlement granted)
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
- Feature stores (`HomeStore`, `LibraryStore`, `PlaybackStore`) take a `SessionStore` and
  are created inside a view's `.task`; they call `session.client.send(...)`.

### Auth & session flow

Connect normalizes a URL → tokenless `JellyfinClient` → `Paths.getPublicSystemInfo`
(following any redirect) → persist a `ServerConnection`. Sign-in calls
`client.signIn(username:password:)`, which mutates the client's configuration with the
returned access token. The token is stored in the **Keychain** (`KeychainStore`, account
`"<serverID>:<userID>"`); a token-free `StoredUser` is persisted via `ServerStore`
(Codable JSON in Application Support). On launch, `AppModel.restoreLastSession()` rebuilds
an authenticated client from the stored token silently.

### Navigation

Navigation divergence is isolated in `Platform/RootContainer.swift`: `TabView`
(compact iPhone, tvOS) vs `NavigationSplitView` (iPad, macOS, visionOS). Item and library
navigation destinations are registered once at each `NavigationStack` root via
`.gusItemDestinations()`; feature views push typed `LibraryRef`/`ItemRef` values. Fixed
app destinations use `AppRoute` + `AppNavigationModel` for `gus://home`, `gus://search`,
and `gus://settings`, shared by URL opens, menu commands, and the tvOS Top Shelf extension.

**Content deep links** (`gus://item/<id>`, `gus://play/<id>` — `Models/ContentLink.swift`)
ride `AppNavigationModel` via a consume-once pending-link; `Platform/ContentLinkHandler.swift`
resolves the id through the session's provider and presents the detail sheet or player.
Content links are the shared entry point for: **Handoff** (`Platform/UserActivities.swift`
— detail/player surfaces publish `NSUserActivity` with ids only, never tokens), **Core
Spotlight** (`Services/SpotlightIndexer.swift` — donates browsed items, refuses
other-account continuations, deindexes on sign-out; no watchOS/tvOS), **Siri/App Intents**
(`App/GusAppIntents.swift` — "Play media" provider search), and the **content-aware tvOS
Top Shelf** (Continue Watching snapshot via the `group.dev.ericslutz.gus` App Group,
written by `HomeStore`, read by the credential-free `GusTopShelf` extension).

### Playback

**Video:** `StreamURLBuilder` POSTs `Paths.getPostedPlaybackInfo` with a `DeviceProfile`
biased toward HLS transcoding so `AVPlayer` always receives a playable container.
`PlaybackStore` owns the `AVPlayer` and tears it down on dismiss. Surface is `VideoPlayer`
on iOS/macOS/visionOS and `AVPlayerViewController` (via representable) on tvOS.
`NowPlayingController` feeds `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`.
`AVAudioSession` is guarded (`#if os(iOS) || os(tvOS) || os(visionOS)` — doesn't exist on macOS).

**Audio:** songs and audiobooks play through `AudioPlayerStore` + `AudioPlayerView` (queue,
shuffle/repeat, speed, chapters) over the Jellyfin universal audio endpoint.
`playerPresentation` routes by `MediaItem.isAudioPlayable`.

**visionOS 3D:** `Media3DDetector` maps Jellyfin SBS/TAB/MVC metadata into a
`Stereo3DPresentation`; non-visionOS always resolves to 2D. SBS/TAB use Gus Cinema
`ImmersiveSpace` (`StereoFrameRenderer` splits packed frames into per-eye `CVPixelBuffer`s
via `CMTaggedBufferGroup`). MV-HEVC uses AVKit directly with `preferredViewingMode = .stereo`.

**Downloads** (`OfflineDownloadStore` + `DownloadSessionCoordinator`): background
`URLSessionConfiguration.background` download session. AVPlayer-native originals use
`Paths.getDownload`; incompatible sources use server-side progressive MP4 transcoding.
Platform availability routed through `Platform/DownloadsAvailability.swift`. tvOS excluded.

### watchOS companion

`GusWatch` is a second application target (`WKRunsIndependentlyOfCompanionApp`), embedded
in `Watch/`. Compiles the shared subset — `Models/`, `Providers/`, `Services/`, and
non-video `Stores/` (no `PlaybackStore`/`SyncPlayStore`) — plus `Sources/Watch`. Remote
control rides `RemoteSessionsStore` + `SessionsSocket`; credentials hand off from iPhone
via `WatchSessionRelay` / `WatchCredentialReceiver`.

---

## Conventions

- **Language/style:** Swift API Design Guidelines. Match surrounding code's idiom. Doc-comment
  types and non-obvious methods with `///`; explain *why*, not *what*.
- **Concurrency:** `@MainActor @Observable` state objects. `async`/`await` for networking;
  no Combine. Project builds in **Swift 5 language mode** (`SWIFT_VERSION = 5`) deliberately.
- **Platform branches:** confine `#if os(...)` to `Platform/` and small guarded view
  modifiers. Feature views should read as ordinary SwiftUI.
- **Errors & states:** use `ContentUnavailableView` + `LoadState` + `LoadingStateView`. Log
  with `OSLog` (subsystem `"dev.ericslutz.gus"`), never `print`.
- **Avoid platform-only APIs** that break other targets: no `UIDevice`/`UIScreen` (use
  `DeviceIdentity`); guard `allowsExternalPlayback`, `AVAudioSession`, `keyboardType`,
  `fullScreenCover`, `navigationBarTitleDisplayMode`, hover effects.
- **User-facing text** goes through the String Catalog (`SWIFT_EMIT_LOC_STRINGS` is on).
  Validate with `jq empty Resources/Localizable.xcstrings`.
- **Spotlight** guards `#if canImport(CoreSpotlight) && !os(tvOS)` — the framework imports
  on tvOS but its symbols are marked unavailable.
- **Definition of done:** builds green on all five destinations (`xcodegen generate` first),
  no new platform-only API leaks, user-facing strings localized, new screens have
  empty/error states, and any deviation from the native-first mandate is justified in the commit.

### Apple-first technology mapping

| Concern | Use |
|---|---|
| Navigation/routing | `NavigationStack` / `NavigationSplitView` / `TabView` |
| State / DI | Observation `@Observable` + `@Environment` |
| Playback | AVKit (`VideoPlayer`, `AVPlayerViewController`); no VLCKit |
| Images | `AsyncImage` + tuned shared `URLCache` |
| Secrets | Security framework `SecItem*` |
| Persistence | `Codable` + `FileManager`; `UserDefaults`/`@AppStorage` for prefs |
| Theming | `AccentColor`, semantic colors, system Materials, SF Symbols, Dynamic Type |
| Now Playing | MediaPlayer (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`) |
| Downloads | Background `URLSessionDownloadTask`, `FileManager`, `Codable` |
| Logging | `OSLog` `Logger` |
| Localized strings | String Catalog (`Localizable.xcstrings`) |
| Immersive / 3D (visionOS) | RealityKit + `ImmersiveSpace` for Cinema/SBS/TAB; AVKit for MV-HEVC |

---

## App icon

The icon is the official **Gus brand mark** from
`Gus.website/assets/gus-mark.svg` — a deep teal rounded square with an icy G and mist
play symbol — rendered across all platforms using `NSBitmapImageRep` at exact pixel sizes.
The **Winter Chill** palette drives the mark and all color assets:

| Role | Hex |
|---|---|
| Background / deep brand base | `#0B2E33` |
| Pineapple highlight — ice | `#B8E3E9` |
| Pineapple depth — teal mid | `#4F7C82` |
| Lattice + crown — mist | `#93B1B5` |

`AccentColor` (light `#4F7C82` / dark `#B8E3E9`), `LaunchBackground` (light `#B8E3E9` /
dark `#0B2E33`), and cinema colorsets all share this palette.

Asset catalogs: `Resources/Assets.xcassets/AppIcon.appiconset` (iOS universal with
default + dark + tinted appearances, plus macOS sizes), `AppIcon.brandassets` (tvOS),
`AppIcon.solidimagestack` (visionOS), and `Resources/Watch/Assets.xcassets` for watchOS.
`Scripts/generate-app-icon.swift` exists but draws an older pineapple design — it is
**not** the source of the current assets. To regenerate icons from the SVG, rasterize
`Gus.website/assets/gus-mark.svg` using `NSBitmapImageRep` (see commit history for the
Swift snippet).

---

## Demo server

`Scripts/demo-server.sh` runs a local Jellyfin container over the rights-cleared
`sample_media/` folder (git-ignored). Debug builds sign straight in via the
`--gus-demo-server` launch argument or the Connect screen's demo button.
See `Documentation/AppStore/demo-server.md`.

---

## Diagnostics

`DiagnosticsHub` records privacy-safe lifecycle markers (numeric/boolean payloads only)
and OSSignposter intervals; `MetricKitCollector` normalizes MetricKit payloads into local
`DiagnosticSummary` records (no tvOS MetricKit; macOS diagnostics only). No third-party
analytics — see `Documentation/AppStore/diagnostics-reliability.md`.

---

## Signing caveat

The `group.dev.ericslutz.gus` App Group must be registered with the App ID before tvOS
device/archive signing (simulators don't enforce it). See
`Documentation/AppStore/signing-capabilities.md`.

---

## Planning & process

The full milestone plan lives in `Documentation/ROADMAP.md`. Keep it current — when scope
changes or a milestone completes, update the roadmap as part of the same change.

Long-form contributor and user-facing documentation belongs in the wiki repo at
`/Users/ericslutz/Developer/Code/A Playa Named Gus/Gus.wiki`; repo docs are links or
brief summaries.

---

## Swiftfin reference policy

The mature [Swiftfin](https://github.com/eslutz/Swiftfin) app is **reference only** —
mirror its *patterns* and SDK call shapes, **never copy its code**. Swiftfin is built on
VLCKit, a custom coordinator/router, Factory DI, Combine, and ~30 dependencies; A Playa
Named Gus deliberately re-expresses those patterns on the Apple-first stack above.
