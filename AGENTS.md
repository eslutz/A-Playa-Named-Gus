# AGENTS.md

This file provides guidance to Codex when working with code in this repository.

## What A Playa Named Gus Is

A Playa Named Gus is an **Apple-first, multiplatform SwiftUI Jellyfin client** — one app
that aims to feel first-party on **iOS, iPadOS, tvOS, visionOS, and macOS**. Bundle id
`dev.ericslutz.gus`; named for *Psych*.

### The core mandate: native APIs over custom code

This is the project's defining constraint, and it should drive **every** implementation
decision: **prefer Apple/system frameworks over custom or third-party code.** Before
writing anything bespoke (a control, a cache, a router, a theming system), look for the
system API that already does it and use that instead. The first-party *feel* comes from
using the system's adaptive components and **never overriding their look**.

- Third-party *runtime* dependencies are limited to `jellyfin-sdk-swift` (`from: 2.1.0`)
  plus, on iOS/iPadOS only, the Readium toolkit for in-app EPUB reading (ADR 0009 — no
  system API renders EPUB; tvOS/macOS don't link it by design, visionOS is blocked on an
  upstream xrOS compile fix). Do not add others without an explicit ADR. (XcodeGen is a
  build-time dev tool, not a shipped dependency, and doesn't count against this rule.)
- When a feature could be built custom or with a system API, the system API wins unless
  it genuinely can't do the job — and that exception should be called out in the PR/commit.

## Commands

The Xcode project is **generated** from `project.yml` by XcodeGen;
`A Playa Named Gus.xcodeproj` is git-ignored. `project.yml` is the source of truth.

```sh
brew install xcodegen          # one-time
xcodegen generate              # regenerate A Playa Named Gus.xcodeproj — REQUIRED after adding/removing any file
xcodebuild -resolvePackageDependencies -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus'
Scripts/format.sh              # format Sources + Tests with SwiftFormat
swiftformat Sources Tests --lint

# list the simulators actually installed on this machine before building
xcodebuild -showdestinations -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus'
```

**Always run `xcodegen generate` after adding, renaming, or deleting a source/resource
file** — XcodeGen globs the file tree at generation time, so new files are invisible to
`xcodebuild` until you regenerate.

Build each destination (names below match a stock Xcode 26.5 install — verify with
`-showdestinations`, as simulator names drift between Xcode versions):

```sh
xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' build
xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build
xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' -destination 'platform=macOS' build
# visionOS: target by simulator id — TWO "Apple Vision Pro" sims exist (1.2 and 26.5),
# so targeting by name is ambiguous/errors. Get the id from -showdestinations.
xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' -destination 'platform=visionOS Simulator,id=<UUID>' build
```

Launch + smoke-test on a simulator:

```sh
xcrun simctl boot 'iPhone 17'; open -a Simulator
xcodebuild -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus' -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build build
xcrun simctl install booted "$(find build/Build/Products/Debug-iphonesimulator -name 'A Playa Named Gus.app' | head -1)"
xcrun simctl launch booted dev.ericslutz.gus
xcrun simctl io booted screenshot /tmp/gus.png
```

> When locating the built `.app`, scope `find` to the right product dir
> (`Debug-iphonesimulator`, `Debug-appletvsimulator`, etc.) — a bare `find build` can
> grab another platform's product (device families won't match and install fails).

Run the CI-style platform unit test actions with:

```sh
xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'
xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus tvOS Unit Tests' -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'
xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus macOS Unit Tests' -destination 'platform=macOS'
# visionOS: use the latest compatible Apple Vision Pro simulator id from -showdestinations.
xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus visionOS Unit Tests' -destination 'platform=visionOS Simulator,id=<UUID>'
```

Run a single Swift Testing test with:

```sh
xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/<Suite>/<test>
```

`GusTests`/`GusTVOSTests`/`GusVisionOSTests`/`GusMacOSTests` cover shared pure logic
with Swift Testing and are the only test bundles run in CI. The matching UI test targets
and `Gus iOS Tests`/`Gus tvOS Tests`/`Gus visionOS Tests`/`Gus macOS Tests` schemes
intentionally stay as narrow local launch smoke tests for the Connect screen.

## Architecture (big picture)

A single multiplatform SwiftUI app target, five Supported Destinations. Pure SwiftUI
lifecycle (`@main struct GusApp: App`), no AppDelegate. Source is layered under `Sources/`:

```
App/        @main entry + RootView (signed-out vs signed-in switch)
Models/     Codable value types (ServerConnection, StoredUser, SessionCredential)
Services/   Stateless helpers: client factory, device identity, Keychain, persistence,
            image/stream URL builders, diagnostics (DiagnosticsHub/MetricKitCollector),
            content rating gate, SyncPlay socket
Stores/     @Observable state objects (the "view models"), incl. AudioPlayerStore
            (song/audiobook queue engine) and SyncPlayStore (Jellyfin-gated)
Features/   One folder per screen area (Connect, Home, Item, Player, Settings, Music,
            Photos, LiveTV)
SharedUI/   Reusable views (AsyncPoster, PosterCard, LoadingStateView) + display helpers
Platform/   ALL #if os(...) divergence lives here (RootContainer, modifiers, nav)
Immersive/  visionOS-only RealityKit "Gus Cinema"
TopShelf/   tvOS Top Shelf extension entry point
CarPlay/    iOS-only CarPlay audio templates (inert until the carplay-audio entitlement
            is granted — see Documentation/AppStore/signing-capabilities.md)
```

**Audio vs video playback.** Video stays in `PlaybackStore` (pure AVKit surfaces; the
iOS/iPadOS surface is `AVPlayerViewController` with PiP, macOS `AVPlayerView`, tvOS the
focus-engine controller, visionOS SwiftUI `VideoPlayer`). Songs and audiobooks play
through `AudioPlayerStore` + `AudioPlayerView` (queue, shuffle/repeat, playback speed,
chapters) over the Jellyfin universal audio endpoint; `playerPresentation` routes by
`MediaItem.isAudioPlayable`.

**Diagnostics.** `DiagnosticsHub` records privacy-safe lifecycle markers (numeric/boolean
payloads only) and OSSignposter intervals; `MetricKitCollector` normalizes MetricKit
payloads into local `DiagnosticSummary` records (no tvOS MetricKit; macOS diagnostics
only). No third-party analytics — see `Documentation/AppStore/diagnostics-reliability.md`.

**Demo server.** `Scripts/demo-server.sh` runs a local Jellyfin container over the
rights-cleared `sample_media/` folder (git-ignored). Debug builds sign straight in via
the `--gus-demo-server` launch argument or the Connect screen's demo button —
`Documentation/AppStore/demo-server.md`.

**State & dependency injection.** State objects are **Observation-framework**
`@Observable @MainActor` classes (not `ObservableObject`/Combine). They are injected via
SwiftUI's `@Environment` at the app/root level and read with `@Environment(Type.self)`:

- `AppModel` is created in `GusApp` and injected app-wide. It owns the known servers/users
  lists and the optional `currentSession`, and funnels connect / sign-in / restore /
  sign-out.
- `RootView` switches on `AppModel.currentSession`: `nil` → `ConnectFlowView`; otherwise
  it injects a `SessionStore` (the authenticated `JellyfinClient` + user + server) into
  the signed-in tree.
- Feature stores (`HomeStore`, `LibraryStore`, `PlaybackStore`) take a `SessionStore` and
  are created inside a view's `.task` (the environment isn't available at `init`), then
  call `session.client.send(...)`.

**Auth & session flow.** Connect normalizes a URL → tokenless `JellyfinClient` →
`Paths.getPublicSystemInfo` (following any redirect) → persist a `ServerConnection`.
Sign-in calls `client.signIn(username:password:)`, which mutates the client's
configuration with the returned access token. The token is stored in the **Keychain**
(`KeychainStore`, account `"<serverID>:<userID>"`); a token-free `StoredUser` is persisted
via `ServerStore` (Codable JSON in Application Support). On launch, `AppModel`
`restoreLastSession()` rebuilds an authenticated client from the stored token silently.

**Navigation divergence** is isolated in `Platform/RootContainer.swift`:
`TabView` (compact iPhone, tvOS) vs `NavigationSplitView` (iPad, macOS, visionOS). Item
and library navigation destinations are registered **once** at each `NavigationStack`
root via `.gusItemDestinations()`; feature views push typed `LibraryRef`/`ItemRef` values.
Fixed app destinations use `AppRoute` + `AppNavigationModel` for `gus://home`,
`gus://search`, and `gus://settings`, which are shared by URL opens, menu commands, and
the tvOS Top Shelf extension. `RootContainer` maps those fixed routes onto tabs or split
selection, while search focus requests stay in the search feature views.
Keep platform `#if` branches in `Platform/` (or small guarded modifiers) rather than
scattering them through feature views.

**Playback is pure AVKit.** `StreamURLBuilder` POSTs `Paths.getPostedPlaybackInfo` with a
`DeviceProfile` **biased toward HLS transcoding** so `AVPlayer` always receives a playable
container (it uses `transcodingURL` when present, else a direct stream). `PlaybackStore`
owns the `AVPlayer` and tears it down on dismiss. The surface is `VideoPlayer` on
iOS/macOS/visionOS and `AVPlayerViewController` (via a representable) on tvOS, which has no
SwiftUI `VideoPlayer`. `NowPlayingController` feeds `MPNowPlayingInfoCenter` /
`MPRemoteCommandCenter`. The audio session is configured only where it exists
(`#if os(iOS) || os(tvOS) || os(visionOS)` — there is no `AVAudioSession` on macOS).

**visionOS 3D / spatial playback.** Stereo playback is visionOS-only and requires direct
play. `Media3DDetector` maps Jellyfin SBS/TAB/MVC metadata plus conservative MV-HEVC
stream hints into a `Stereo3DPresentation`; non-visionOS platforms always resolve to 2D.
`StreamURLBuilder` disables transcoding for stereo attempts because HLS transcoding
flattens stereo, then falls back to 2D with a notice when direct play is unavailable.
MV-HEVC uses the normal AVKit `VideoPlayer` path with a Spatial badge. SBS/TAB uses the
Gus Cinema `ImmersiveSpace`: a `StereoFrameRenderer` taps `AVPlayerItemVideoOutput` from
the same `AVPlayer`, splits each packed frame into per-eye `CVPixelBuffer`s, tags them
via `CMTaggedBufferGroup`/`CMTag.stereoView`, and feeds them to `AVSampleBufferVideoRenderer`;
`VideoMaterial(videoRenderer:)` with `preferredViewingMode = .stereo` on the `Stereo3DScreen`
plane provides true left/right eye separation.
MVC is unsupported and plays in 2D with a notice. The visionOS player menu offers Auto,
2D, and Spatial; Spatial is the manual override for unflagged MV-HEVC files.

**Downloads are background-capable and non-tvOS.** `OfflineDownloadStore` resolves a
download source, persists status/progress metadata, and hands transfer work to
`DownloadSessionCoordinator`, a native `URLSessionConfiguration.background` download
session. AVPlayer-native originals use `Paths.getDownload(itemID:)`; incompatible
sources use Jellyfin server-side progressive MP4 transcoding through
`Paths.getVideoStreamByContainer`. Files still land in Application Support under a
per-server/user folder and are excluded from backup. Pause/resume/delete are supported;
resume data can expire server-side, so stale resumes may restart. Keep feature views free
of platform `#if`s by routing availability through `Platform/DownloadsAvailability.swift`.

**Apple-first technology mapping** — when you need one of these, reach for the right
column, not a custom/third-party equivalent:

| Concern | Use |
|---|---|
| Navigation/routing | `NavigationStack` / `NavigationSplitView` / `TabView` (no custom coordinator/router) |
| State / DI | Observation `@Observable` + `@Environment` (no Combine `@Published`, no DI container) |
| Playback | AVKit (`VideoPlayer`, `AVPlayerViewController`); no VLCKit |
| Images | `AsyncImage` + a tuned shared `URLCache` (no Nuke/Kingfisher) |
| Secrets | Security framework `SecItem*` (no KeychainSwift) |
| Persistence | `Codable` + `FileManager`; `UserDefaults`/`@AppStorage` for prefs |
| Theming | `AccentColor`, semantic colors, system Materials, SF Symbols, Dynamic Type, `ContentUnavailableView` |
| Now Playing | MediaPlayer (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`) |
| Downloads | Background `URLSessionDownloadTask`, `FileManager`, `Codable`, backup-exclusion resource values |
| Logging | `OSLog` `Logger` (no Pulse) |
| Localized strings | String Catalog (`Localizable.xcstrings`) |
| Immersive / 3D (visionOS) | RealityKit + `ImmersiveSpace` for Cinema/SBS/TAB; AVKit direct play for MV-HEVC |

## Conventions & standards

- **Language/style:** follow the
  [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
  Match the surrounding code's idiom and comment density. Doc-comment types and non-obvious
  methods with `///`; explain *why*, not *what*.
- **Concurrency:** state objects are `@MainActor @Observable`. `async`/`await` for all
  networking; no Combine. The project builds in **Swift 5 language mode** deliberately
  (`SWIFT_VERSION = 5`) to avoid strict-concurrency churn against the SDK this milestone —
  modern APIs are availability-gated, not language-mode-gated, so keep using them.
- **Platform branches:** confine `#if os(...)` to `Platform/` and small guarded view
  modifiers. Feature views should read as ordinary SwiftUI.
- **Errors & states:** surface load/empty/error states with `ContentUnavailableView` and
  the shared `LoadState` + `LoadingStateView`. Log with `OSLog` (`subsystem
  "dev.ericslutz.gus"`), never `print`.
- **Avoid platform-only APIs that break other targets:** no `UIDevice`/`UIScreen` (use
  `DeviceIdentity`); guard `allowsExternalPlayback`, `AVAudioSession`, `keyboardType`,
  `fullScreenCover`, `navigationBarTitleDisplayMode`, hover effects, etc., which don't
  exist on every platform.
- **User-facing text** goes through the String Catalog (`SWIFT_EMIT_LOC_STRINGS` is on).
- **HIG fidelity:** use system components as designed; don't restyle them. Respect Dynamic
  Type, safe areas, focus (tvOS), pointer/hover (iPad/visionOS), and platform navigation
  idioms.
- **Definition of done for a change:** builds green on all five destinations
  (`xcodegen generate` first), no new platform-only API leaks, user-facing strings
  localized, new screens have empty/error states, `jq empty Resources/Localizable.xcstrings`
  passes, and any deviation from the native-first mandate is justified in the commit. For
  playback features, record which checks are automated and which require manual/device
  verification.

## Reference documentation

Consult these when implementing — they encode the requirements above.

**Apple frameworks (API):**
- SwiftUI — https://developer.apple.com/documentation/swiftui
- Observation (`@Observable`) — https://developer.apple.com/documentation/observation , migration guide: https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro
- NavigationStack — https://developer.apple.com/documentation/swiftui/navigationstack
- NavigationSplitView — https://developer.apple.com/documentation/swiftui/navigationsplitview
- TabView — https://developer.apple.com/documentation/swiftui/tabview
- AsyncImage — https://developer.apple.com/documentation/swiftui/asyncimage
- ContentUnavailableView — https://developer.apple.com/documentation/swiftui/contentunavailableview
- Material — https://developer.apple.com/documentation/swiftui/material
- AVKit — https://developer.apple.com/documentation/avkit ; VideoPlayer — https://developer.apple.com/documentation/avkit/videoplayer ; AVPlayerViewController — https://developer.apple.com/documentation/avkit/avplayerviewcontroller
- AVFoundation media playback — https://developer.apple.com/documentation/avfoundation/media-playback
- MediaPlayer / Now Playable — https://developer.apple.com/documentation/mediaplayer/becoming-a-now-playable-app
- Keychain Services — https://developer.apple.com/documentation/security/keychain-services
- URLCache — https://developer.apple.com/documentation/foundation/urlcache
- RealityKit — https://developer.apple.com/documentation/realitykit ; ImmersiveSpace — https://developer.apple.com/documentation/swiftui/immersivespace
- String Catalog — https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog
- Privacy manifest — https://developer.apple.com/documentation/bundleresources/app-privacy-configuration

**Human Interface Guidelines (design):**
- HIG home — https://developer.apple.com/design/human-interface-guidelines
- App icons — https://developer.apple.com/design/human-interface-guidelines/app-icons
- Layout — https://developer.apple.com/design/human-interface-guidelines/layout
- Navigation & search — https://developer.apple.com/design/human-interface-guidelines/navigation-bars , .../tab-bars , .../sidebars
- Materials — https://developer.apple.com/design/human-interface-guidelines/materials
- Typography — https://developer.apple.com/design/human-interface-guidelines/typography
- Color — https://developer.apple.com/design/human-interface-guidelines/color
- Playing video — https://developer.apple.com/design/human-interface-guidelines/playing-video
- Immersive experiences (visionOS) — https://developer.apple.com/design/human-interface-guidelines/immersive-experiences
- Designing for tvOS — https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos
- Accessibility — https://developer.apple.com/design/human-interface-guidelines/accessibility
- SF Symbols — https://developer.apple.com/sf-symbols/

**App Store:**
- App Review Guidelines — https://developer.apple.com/app-store/review/guidelines/
- App Store Connect help — https://developer.apple.com/help/app-store-connect/

## App icon design

The icon uses the official **Winter Chill** palette with the app's pineapple cue: a deep
teal field, an icy pineapple body shading into teal depth, and a mist-toned diamond
crosshatch lattice + crown. Current values (the roadmap's M1 role table is the source of
truth):

| Role | Hex |
|---|---|
| Background / deep brand base | `#0B2E33` |
| Pineapple highlight — ice | `#B8E3E9` |
| Pineapple depth — teal mid | `#4F7C82` |
| Lattice + crown — mist | `#93B1B5` |

The same palette drives `AccentColor` (light `#4F7C82` / dark `#B8E3E9`),
`LaunchBackground` (light `#B8E3E9` / dark `#0B2E33`), and the cinema key/fill/backdrop
colorsets. A single multiplatform asset catalog holds the icon as `AppIcon.appiconset`
(iOS universal with **default + dark + tinted appearances**, plus macOS idioms),
`AppIcon.brandassets` (tvOS), and `AppIcon.solidimagestack` (visionOS) — all named
`AppIcon` — with `ASSETCATALOG_COMPILER_APPICON_NAME` resolving to `AppIcon`; the watch
target's catalog at `Resources/Watch/Assets.xcassets` carries the watchOS icon. All art
is generated by `Scripts/generate-app-icon.swift` using Core Graphics (Apple-first, no
third-party image tooling). See the roadmap's Brand milestone.

## Swiftfin reference policy

The mature [Swiftfin](https://github.com/eslutz/Swiftfin) app (and its visionOS PRs #1/#2)
is **reference only** — mirror its *patterns* and SDK call shapes, **never copy its code**.
Swiftfin is built on VLCKit, a custom coordinator/router, Factory DI, Combine, and ~30
dependencies; A Playa Named Gus deliberately re-expresses those patterns on the Apple-first stack above.
The "Gus Cinema" immersive space is ported in structure from PR #2's `visionos-native`
branch and re-expressed on `@Observable` with the Jellyfin palette.

## Planning & process

The full milestone plan to App Store submission lives in `Documentation/ROADMAP.md`.
Keep it current: when scope changes or a milestone completes, update the roadmap as part
of the same change so the plan stays the source of truth.

Repository docs stay intentionally compact. `README.md` is a short overview and quick
start, and `CONTRIBUTING.md` only points to the GitHub wiki's Contributing page.
Long-form contributor and user-facing documentation belongs in the source-controlled wiki
repo at `/Users/ericslutz/Developer/Code/A Playa Named Gus/Gus.wiki`; make wiki changes
there locally, and keep repo docs as links or brief summaries.
