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

**Sketch is the fresh redesign workspace.** The private **Gus** folder in Eric Slutz's
Workspace contains the editable working documents; `Design/` contains the two iPhone R5
snapshots, and `Design/Archive/` holds local historical design material. Follow Apple HIG, Apple Design
Resources and current framework documentation. Use linked official Apple components;
never label a flat or blur approximation verified native Liquid Glass fidelity.
The current iPhone implementation follows the user-selected live **Gus iPhone** document
(`65DEED33-7DFF-47E5-AF51-31D00E68E6EE`), its Screens, States and Components pages,
inspected through Sketch MCP. The R5 snapshots remain historical references. Runtime
verification uses one iPhone simulator in Light appearance against the local demo server;
physical acceptance and later-device redesign remain separate. Consult the locally archived `Design/Archive/2026-10-27/Sketch/README.md`
and its milestone index first, when available.
Preserve the archived `Gus.fig`, Fresh Foundation candidate and split Figma files as
historical references; do not import their screen layouts into the redesign or regenerate
them. The archived `Design/Archive/2026-10-27/DISCOVER.md` remains the approved behavioral input, with implementation
status checked against current source. Design coverage does not prove runtime behavior.

The iPad implementation follows the fresh **Gus iPadOS** handoff. Its ordinary
details stay in the main navigation stack; Reader, Photos and Now Playing occupy
the window. Global Search is a dedicated sidebar destination (a Search tab in a
compact window), and the sidebar visibility control sits at its trailing edge.
Use native controls and preserve the approved iPhone presentation. The external
94-scenario comparison and supporting-state checklist track runtime acceptance;
see `Documentation/ipad-capabilities.md` for client/service boundaries.

- Third-party *runtime* dependencies are limited to `jellyfin-sdk-swift` (`from: 2.1.0`)
  plus, on iOS/iPadOS only, the Readium toolkit for in-app EPUB reading (ADR 0009 — no
  system API renders EPUB; tvOS/macOS don't link it by design, visionOS is blocked on an
  upstream xrOS compile fix). Do not add others without an explicit ADR.
- When a feature could be built custom or with a system API, the system API wins unless it
  genuinely can't do the job — and that exception should be called out in the PR/commit.

---

## Delivery policy

Keep build and review evidence out of Git. Store logs, result bundles, screenshots,
exports and dated validation artifacts locally outside the tracked source tree.
Keep durable decisions, actionable limitations and reproducible instructions in
concise documentation; historical results do not establish current release readiness.

Changes to protected `main` require a pull request and all required GitHub CI checks;
do not push directly or bypass protection. GitHub runs CI on PRs targeting `main`.
Xcode Cloud uses manual-only main workflows: cached single-iPhone validation and a separate
full-matrix internal TestFlight release. Release-candidate tests remain required; see
`Documentation/AppStore/pipeline-policy.md` for the saved release gates.

## OS compatibility policy

The minimum deployment target is **26.0 on every platform**, including Watch and
Top Shelf. Build with Xcode 27.1 or newer and prefer the latest OS 27.x APIs,
guarding newer APIs with runtime availability checks and preserving useful OS 26
fallbacks. Lowering deployment targets must not remove newer OS functionality.
Build validation and actual OS 26 runtime/device acceptance are separate gates.

## Warning-free build policy

Treat every warning as an error. App, extension, Watch, and test targets must
compile, test, archive, and export with zero warnings and zero errors across all
supported platforms. Swift and C-family warnings are errors in project.yml.
Do not disable diagnostics, lower concurrency checking, or override these gates
to obtain a green build. Fix the underlying cause, including test fixtures.
Build-tool, linker, asset, and dependency warnings also block acceptance even when
compiler flags do not promote them. Inspect raw logs and Xcode Cloud issues for
the exact validated commit; a successful build with warnings is not accepted.
See `Documentation/AppStore/warning-policy.md` for the release gates and Build 16 findings.

## Architecture policy

Build only Apple Silicon versions. `Config/Shared.xcconfig` sets `ARCHS = arm64`
and excludes Intel architectures for Debug, Release, app, extension, and test
builds. Physical Watch builds retain the SDK's ARM device variants. Do not add
Intel or universal Mac builds. Build scripts and GitHub CI use the shared
warning-free wrapper, which rejects explicit Intel architecture requests and
excludes Intel from package and embedded-target builds.

## Commands

The Xcode project is **generated** from `project.yml` by XcodeGen;
The shared `A Playa Named Gus.xcodeproj` snapshot and `Package.resolved` belong in git
for Xcode Cloud discovery. `project.yml` remains the source of truth; user workspace
state remains ignored. Include regenerated project changes when source files change.

```sh
brew install xcodegen          # one-time
xcodegen generate              # regenerate — REQUIRED after adding/removing any file
python3 Scripts/check-cloud-project.py # verify shared snapshot and dependency pins
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
  'build/Build/Products/Debug-iphonesimulator/A Playa Named Gus.app'
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
Swift Testing and are the test bundles run in CI. The matching `Gus iOS Tests`/
`Gus tvOS Tests`/etc. schemes also provide local authenticated UI regressions using
`Scripts/demo-server.sh start`; `Gus watchOS Tests` covers Watch browse/audio.
`python3 Scripts/validate-release.py --phase all` runs the sequential local matrix.

Screenshot automation:

```sh
# start the demo server first
Scripts/demo-server.sh
# capture all scenes for one platform (iphone | ipad | tv | vision | watch)
Scripts/screenshots.sh iphone
```

---

## Architecture

A single multiplatform SwiftUI app target, five Supported Destinations. SwiftUI
lifecycle (`@main struct GusApp: App`), with a minimal iOS `UIApplicationDelegateAdaptor`
only for background URLSession wake/completion events (ADR 0005). Source is layered under `Sources/`:

```
App/        @main entry + RootView (signed-out vs signed-in switch) + GusAppIntents.swift
Models/     Codable value types (ServerConnection, StoredUser, SessionCredential, ContentLink)
Services/   Stateless helpers: client factory, device identity, Keychain, persistence,
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
- Feature stores take a `SessionStore` and use its media provider. `RootNavigationState`
  owns Home, cached library/detail stores, per-section search, navigation paths,
  per-library display choices, profile presentation, and scroll anchors for the signed-in account; adaptive view replacement reuses that state.
  `RootView` owns `AudioPlaybackCoordinator` and stops it when the account changes.

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
All section stacks bind their paths to `RootNavigationState`. Compact iPhone navigation
uses three content tabs plus an explicit More list and a native Search tab, keeping
one stack per section. The default content tabs are Home, Movies and Series when
available; a saved account-specific order keeps its first three visible sections. Settings/Downloads children use the typed `AppScreen` destinations.

**Content deep links** (`gus://item/<id>`, `gus://play/<id>` — `Models/ContentLink.swift`)
ride `AppNavigationModel` via a consume-once pending-link; `Platform/ContentLinkHandler.swift`
resolves the id through the session's provider. iPad and tvOS item links push into the selected
section's normal stack; iPad photos open the fullscreen session viewer. Other platforms present a detail sheet. Session player hosts sit
above adaptive layout replacement, with the detail sheet hosting playback while it is open.
Content links are the shared entry point for: **Handoff** (`Platform/UserActivities.swift`
— detail/player surfaces publish `NSUserActivity` with ids only, never tokens), **Core
Spotlight** (`Services/SpotlightIndexer.swift` — donates browsed items, refuses
other-account continuations, deindexes on sign-out; no watchOS/tvOS), **Siri/App Intents**
(`App/GusAppIntents.swift` — "Play media" provider search), and the **content-aware tvOS
Top Shelf** (Continue Watching snapshot via the `group.dev.ericslutz.gus` App Group,
written by `HomeStore`, read by the credential-free `GusTopShelf` extension).

### Playback

**Video:** `StreamURLBuilder` POSTs `Paths.getPostedPlaybackInfo` with a `DeviceProfile`
that leans **direct play** for everything the device's hardware decodes
(`DevicePlaybackCapabilities` gates HEVC/AV1 on `VTIsHardwareDecodeSupported` — guarded
`canImport(VideoToolbox)` for watchOS — and HDR ranges on `AVPlayer.eligibleForHDRPlayback`),
falling back to HEVC-preferred fMP4 HLS transcoding with 8-channel audio and
`enableSubtitlesInManifest` (bitmap subs burn in; text subs ride the manifest).
`PlaybackStore` owns the `AVPlayer` and tears it down on dismiss; it sets
`AVPlayerItem.externalMetadata` (not on macOS — no API), auto-plays next episodes or
dismisses at natural end (`PlaybackPreferences`), reports pause/resume immediately, and
reads the Settings-backed `PlaybackQuality` bitrate cap. Track switching is in-place via
`AVMediaSelection` for direct play (`PlaybackMediaSelectionMatcher`, ordinal+language)
with a server-side rebuild fallback. Surfaces: `AVPlayerViewController` on iOS
(`updatesNowPlayingInfoCenter = false` — `NowPlayingController` is the single Now Playing
writer), tvOS, and visionOS (where `AVExperienceController` provides native expanded and
immersive playback controls), and `AVPlayerView` on macOS (video opens in the dedicated
`GusPlayerWindow` window scene, not a sheet). `NowPlayingController`
feeds `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`. `AVAudioSession` is guarded
(`#if os(iOS) || os(tvOS) || os(visionOS)` — doesn't exist on macOS).

**Audio:** songs and audiobooks play through `AudioPlayerStore` + `AudioPlayerView` (queue,
shuffle/repeat, speed, chapters) over the Jellyfin universal audio endpoint.
`playerPresentation` routes by `MediaItem.isAudioPlayable`.
`AudioPlaybackCoordinator` owns the queue and preparation task independently of the player
presentation. Close dismisses prepared iOS audio while playback continues; the persistent Now
Playing control reopens it. Non-iOS playback retains its platform controls. Closing during preparation cancels
the task. Audio/video stores reject late results after cancellation or teardown; loading
and failed player states expose cancellation and retry. The Watch companion uses its own
scrollable audio sheet and tears down playback when leaving that sheet.

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
non-video `Stores` (no `PlaybackStore`) — plus `Sources/Watch`. Remote
control rides `RemoteSessionsStore` + `SessionsSocket`; credentials hand off from iPhone
via `WatchSessionRelay` / `WatchCredentialReceiver`.

---

## Conventions

- **Language/style:** Swift API Design Guidelines. Match surrounding code's idiom. Doc-comment
  types and non-obvious methods with `///`; explain *why*, not *what*.
- **Concurrency:** `@MainActor @Observable` state objects. `async`/`await` for networking;
  no Combine. Complete checking on all targets. Watch, Top Shelf and tvOS/visionOS app
  use Swift 6; iOS/macOS use Swift 5 pending the documented Readium/Declared Age Range
  isolation boundaries in `Documentation/Reviews/2026-10-10-release-validation/SWIFT-CONCURRENCY.md`.
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

The modern icon adapts the **Gus brand mark** from
`Gus.website/assets/gus-mark.svg` into a connected icy G and a smaller mist play
symbol on deep teal. Its editable native source is `Resources/AppIcon.icon`.
The G curve and arm form one continuous SVG stroke in the rear depth group;
the smaller play symbol sits in a separate foreground group. The G uses 30%
translucency, the play uses 20%, and play refraction is restrained to 0.12.
Keep these as editable SVG layers and make Icon Composer the source of truth for
modern iOS/iPadOS, macOS, and watchOS icons. The **Winter Chill** palette drives
the mark and all color assets:

| Role | Hex |
|---|---|
| Background / deep brand base | `#0B2E33` |
| Pineapple highlight — ice | `#B8E3E9` |
| Pineapple depth — teal mid | `#4F7C82` |
| Lattice + crown — mist | `#93B1B5` |

`AccentColor` (light `#4F7C82` / dark `#B8E3E9`), `LaunchBackground` (light `#B8E3E9` /
dark `#0B2E33`), and cinema colorsets all share this palette.

`Resources/Assets.xcassets/AppIcon.appiconset` retains opaque raster fallbacks.
`AppIcon.brandassets` (tvOS) and `AppIcon.solidimagestack` (visionOS) remain
platform-specific background/G/play stacks generated from the approved SVGs by
`swift Scripts/generate-platform-icons.swift`. This also refreshes static tvOS Top Shelf
artwork and the review page in `Documentation/AppStore/platform-icon-review/`.
`Scripts/generate-app-icon.swift` draws an older
pineapple design and is **not** a source for the current icon. For the modern icon, edit
`Resources/AppIcon.icon` in Icon Composer and preserve the Gus palette and G/play identity. The modern geometry is an intentional
adaptation of the website mark.

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

## Companion repos: wiki & website (keep in sync)

Two sibling repos document Gus and **must be kept up to date with relevant changes as
part of the same unit of work** — don't let app changes land while their documentation
goes stale:

- **Wiki — `../Gus.wiki`** — the **primary source for user-facing documentation**
  (feature guides, setup instructions, FAQs). When a change adds, removes, or alters
  user-visible behavior, update the corresponding wiki page(s) alongside it. Make wiki
  changes locally in that repo.
- **Website — `../Gus.website`** — the marketing/support/compliance site at
  `gus.ericslutz.dev` (marketing, support, privacy policy, accessibility, age
  suitability — see `Documentation/AppStore/review-support-pages.md`). Update it when a
  change affects anything it presents: feature claims, screenshots, support
  instructions, privacy or accessibility disclosures, or brand assets
  (`assets/gus-mark.svg` there is the app-icon source of truth).

Repo docs in this project stay intentionally compact — links or brief summaries that
point at the wiki; long-form contributor and user-facing documentation belongs in the
wiki, not here.

---

## Swiftfin reference policy

The mature [Swiftfin](https://github.com/eslutz/Swiftfin) app is **reference only** —
mirror its *patterns* and SDK call shapes, **never copy its code**. Swiftfin is built on
VLCKit, a custom coordinator/router, Factory DI, Combine, and ~30 dependencies; A Playa
Named Gus deliberately re-expresses those patterns on the Apple-first stack above.

### iOS review iteration 2

Theme selection is device-local and independent of Appearance: Gus Default, Apple Default, or an opaque custom accent. Shared theme storage/contrast helpers are reusable; only iOS exposes the selector. Home Recently Added feeds span libraries by media type; All Next Up has a local grid/list choice. Read-only sheets use leading Close and editors use trailing Done/Save. iOS playlist reorder handles use public drag-and-drop because the system edit-mode handle has no leading placement API; moves still use the existing scoped server edit queue. Completed playlist presentation resets to Play and item 1 while retaining the completion marker for Next Up.

Extend the existing external iPhone comparison report with `Scripts/generate-ui-comparison.py --next-iteration <captures> --output <existing-report> --notes <notes>`. Preserve original Before/After assets, captions, notes and manifest fields; iteration 2 is a third inline image. No screenshots or build evidence belong in source.
