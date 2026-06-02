# Gus

An **Apple-first, multiplatform Jellyfin client** — one app that aims to feel first-party
on **iOS, iPadOS, tvOS, visionOS, and macOS** by preferring Apple/system frameworks over
custom code. Built with SwiftUI, the **Observation** framework, and **pure AVKit**
playback (server-side transcoding via Jellyfin).

> Named for *Psych* — "A Playa Named Gus." Bundle id `dev.ericslutz.gus`.

The mature [Swiftfin](https://github.com/eslutz/Swiftfin) app is **reference only**: Gus
mirrors its SDK *patterns*, never its code.

## Status — first milestone

A breadth-first end-to-end slice on all five platforms:
**connect → sign in → browse → detail → play → settings**, plus the visionOS
**Gus Cinema** immersive space.

All five destinations build green (Xcode 26.5 / Swift 6.3 toolchain, Swift 5 language mode).

## Architecture (Apple-first)

| Concern | Gus uses |
|---|---|
| Navigation | `NavigationStack` / `TabView` (iPhone, tvOS); `NavigationSplitView` (iPad, macOS, visionOS) |
| State / DI | **Observation** `@Observable` + `@Environment`, injected at the `App` root |
| Playback | **AVKit** — `VideoPlayer` (iOS/macOS/visionOS), `AVPlayerViewController` (tvOS); server transcode via `transcodingURL` |
| Images | `AsyncImage` + a tuned shared `URLCache` |
| Tokens | **Security** framework (`SecItem*`) — `KeychainStore` |
| Persistence | `Codable` + `FileManager` (`ServerStore`) + `UserDefaults` for prefs |
| Theming | `AccentColor`, semantic colors, system **Materials**, **SF Symbols**, Dynamic Type, `ContentUnavailableView` |
| Now Playing | **MediaPlayer** — `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` |
| Logging | `OSLog` |
| Strings | String Catalog (`Localizable.xcstrings`) |
| Dependency | **Only** `jellyfin-sdk-swift` (`from: 2.1.0`) — everything else is Apple frameworks |

`Sources/` is grouped into `App`, `Models`, `Services`, `Stores` (`@Observable`),
`Features` (Connect/Home/Item/Player/Settings), `SharedUI`, `Platform` (the `#if os(...)`
divergence), and `Immersive` (visionOS Gus Cinema).

## Project generation

The Xcode project is generated from a committed [`project.yml`](project.yml) via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) — a build-time dev tool, **not** a
shipped dependency. `project.yml` is the source of truth; `Gus.xcodeproj` is git-ignored.

```sh
brew install xcodegen      # one-time
xcodegen generate          # regenerate Gus.xcodeproj from project.yml
```

One multiplatform `Gus` target with five Supported Destinations. Deployment floors:
iOS/iPadOS 18, tvOS 18, visionOS 2.0, macOS 15.

## Build & verify

```sh
xcodegen generate
xcodebuild -resolvePackageDependencies -project Gus.xcodeproj -scheme Gus

# discover the simulators installed on this machine
xcodebuild -showdestinations -project Gus.xcodeproj -scheme Gus

# build each destination (names below match a stock Xcode 26.5 install)
xcodebuild -project Gus.xcodeproj -scheme Gus -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project Gus.xcodeproj -scheme Gus -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' build
xcodebuild -project Gus.xcodeproj -scheme Gus -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build
xcodebuild -project Gus.xcodeproj -scheme Gus -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build
xcodebuild -project Gus.xcodeproj -scheme Gus -destination 'platform=macOS' build
```

Then smoke-test against a real/demo Jellyfin server: connect → sign in → home → detail →
**play**, and on visionOS enter **Gus Cinema** during playback.

## Deferred (later rounds)

- **App icons** — `ASSETCATALOG_COMPILER_APPICON_NAME` is intentionally unset so a single
  multiplatform asset catalog doesn't require per-platform icon sets
  (`appiconset` / tvOS `brandassets` / visionOS `solidimagestack`) before real artwork
  exists. The `AccentColor` (pineapple gold) is wired up and drives the app tint.
- Search, multi-user switching, fuller metadata/people/seasons UI, offline/downloads,
  playback-progress reporting, Bonjour discovery UI, blurhash placeholders, music
  libraries, localization beyond the base String Catalog.
