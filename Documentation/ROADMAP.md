# A Playa Named Gus — Roadmap to App Store

This is the source-of-truth plan for taking A Playa Named Gus from its first end-to-end
slice to a shippable, App Store-ready, multiplatform app. It is organized into
**milestones**; each milestone is a coherent unit of work broken into **features** with
explicit acceptance criteria.

**How to use this doc:** work milestones top-to-bottom (later ones assume earlier ones).
Keep it current — when a feature lands or scope changes, check the box and adjust here in
the same change. See `../AGENTS.md` or `../CLAUDE.md` for the architecture and the native-first mandate that
constrain *how* each item is built.

## Conventions for this roadmap

- `[ ]` not started · `[~]` in progress · `[x]` done.
- Every feature names an **Acceptance** bar. A feature isn't done until it builds green on
  all five destinations and meets that bar.
- **Native-first** is assumed on every item: reach for the Apple/system API first; a
  bespoke or third-party approach must be justified in the change that introduces it.

## October 2026 UI remediation

- [~] October 11 repairs cover sign-in/error feedback, Mac discovery, persistent download artwork, confirmed/selective/bulk management deletion, native swipe deletion, completion cleanup, adaptive hero/actions/sidebar, audio return controls, and playback lifecycle/replay. Physical phone checks finished on **1.0.0 (11)**; management scrolling/Cancel and compact actions passed, and the phone is released with no automation pending. Later source changes have not been installed on it. The landscape Home search repair passed 1/1; full narrow-screen portrait/landscape checks passed 2/2 in light/dark at accessibility XXXL. The final focused playback run passed **23/23** (two real natural-completion/replay checks and 21 UI/lifecycle regressions). Nested EPUB chapter navigation now uses a native sheet/list with recursive disclosure groups and retains Readium’s directional navigation adapter. Its isolated iOS simulator acceptance passed **1/1**, covering chapter selection, readable portrait/landscape pages, forward/backward paging, keyboard absence, and return to book details. See [current repair evidence](Reviews/2026-10-11-auth-device-repair/REPORT.md).
- [x] Implement remediation for the 24 findings in the October 9–10 review and both addenda: bounded artwork/detail layouts, adaptive actions/audio, persistent audio dismissal/reopening, shared navigation across width changes, explicit iPhone More, tvOS link navigation, cancellation/retry, request identity, filtered paging, and localized accessibility fixes. The earlier candidate passed all six platform builds and four 274-test suites; see [the remediation report](Reviews/2026-10-10-ui-remediation/REPORT.md) for scoped runtime and contrast evidence.
- [~] Complete release acceptance: physical acceptance of later source changes, Mac window/keyboard checks, assistive technology and platform input, remaining appearance/metadata/error variants, full iPad contrast acceptance (native Xcode 27 sampler blocked), exact minimum-OS execution, broader Duo video/navigation/sheet transition flows, and signed TestFlight acceptance. The sampled live Duo audio transition/control check passed; see the repair report for its limits. The Watch stall was fixed and retested locally on 40 mm and 46 mm. Simulator checks do not close the remaining gates.

- [x] October 12 stale-reference recovery: shared account-scoped resolution, versioned Next Up migration, explicit legacy replacement, public-artwork fallbacks, scoped system links, preserved downloaded-file identity, and confirmed progress transfer. Source, regression tests, platform builds, and the physical Trespass recovery are verified; evidence and remaining cross-platform runtime limits are recorded in [the validation report](Reviews/2026-10-12-stale-media-references/VALIDATION.md).

## Global Definition of Done (applies to every milestone)

- Builds green on iOS, iPadOS, tvOS, visionOS, macOS (`xcodegen generate` first).
- No platform-only API leaks across targets; `#if os(...)` confined to `Platform/`.
- New/changed user-facing strings are in the String Catalog.
- New screens have loading / empty / error states (`LoadingStateView` +
  `ContentUnavailableView`).
- Accessibility: VoiceOver labels on interactive elements, Dynamic Type respected,
  contrast ≥ WCAG AA for custom colors.
- `Documentation/ROADMAP.md`, `AGENTS.md`, and `CLAUDE.md` updated to match reality.

---

## M0 — Foundation slice ✅ (complete)

The breadth-first vertical slice on all five platforms: connect → sign in → browse →
detail → play → settings, plus the visionOS Gus Cinema immersive space. Project generated
from `project.yml` (XcodeGen), `jellyfin-sdk-swift` as the only runtime dependency,
Observation-based stores, pure-AVKit playback, Keychain token storage. All five
destinations build; iOS launches and renders the Connect screen.

---

## M1 — Brand & Identity

**Goal:** A Playa Named Gus looks like a finished product at first glance — real icon,
considered launch and accent, consistent semantic theming.

- [x] **App icon (all platforms).** Use the official Gus brand mark from
  `Gus.website/assets/gus-mark.svg` as the source of truth. Produce
  `AppIcon.appiconset` (iOS + macOS idioms), `AppIcon.brandassets` (tvOS App Icon + Top
  Shelf), and `AppIcon.solidimagestack` (visionOS layered), all named `AppIcon`; remove the
  `ASSETCATALOG_COMPILER_APPICON_NAME: ""` override in `project.yml`.
  *Acceptance:* actool produces no missing-icon errors on any SDK; icon renders on each
  Home screen / launcher. *(Done: current source-controlled assets use the Gus brand mark;
  the older `Scripts/generate-app-icon.swift` pineapple generator is retired and must not be
  used for regeneration.)*
- [x] **Launch experience.** Confirm `UILaunchScreen` presents cleanly; consider a minimal
  branded launch on platforms that support it. *Acceptance:* no flash of unstyled content;
  consistent first frame. *(Done: iOS/iPadOS use a color-only `UILaunchScreen` backed by
  the `LaunchBackground` asset.)*
- [~] **Accent & semantic theme pass.** Centralize the official Winter Chill app palette
  as semantic color assets with light/dark variants; audit views for hardcoded colors.
  Color roles:

  | Role | Light mode | Dark mode | Use |
  |---|---:|---:|---|
  | Brand light / launch wash | `#B8E3E9` | `#0B2E33` | Launch background, empty-state wash, app icon contrast field, and subtle branded surfaces while preserving system Materials for ordinary content. |
  | Primary accent / `AccentColor` | `#4F7C82` | `#B8E3E9` | Interactive tint, selected tab/sidebar state, links, focus rings, primary action glyphs, and key cinema lighting. |
  | Secondary accent | `#93B1B5` | `#4F7C82` | Secondary actions, muted glyphs, dividers, poster placeholders, badges, and cinema fill lighting. |
  | Deep brand base | `#0B2E33` | `#0B2E33` | App icon background, dark launch variant, cinema backdrop/shadow, and high-contrast text or glyphs only when placed on light brand surfaces. |

  Keep text, destructive, warning, success, selection-material, and disabled-state colors
  on Apple semantic colors unless a future brand brief adds dedicated accessible status
  colors; do not use palette colors as body text on low-contrast pairings. *Acceptance:*
  light/dark both legible; no raw `Color(red:…)` in feature views; asset catalog colors,
  current app icon art, launch background, and cinema lighting all use Winter Chill.
  *(Done: `AccentColor` and `LaunchBackground` carry the Winter Chill light/dark role
  values, the `Cinema*` colorsets use the always-dark immersive variants, and
  `GusCinemaPalette` fallbacks match; no raw brand literals remain outside the asset
  catalog/generator.)*
- [x] **String Catalog baseline.** Move all current literal UI strings into
  `Localizable.xcstrings` with comments. *Acceptance:* `SWIFT_EMIT_LOC_STRINGS` shows no
  un-catalogued user-facing strings in changed files. *(Done: the base catalog is seeded
  with current UI and user-facing error strings.)*
- [x] **Appearance setting + Liquid Glass adoption.** Settings → Appearance offers
  System/Light/Dark, applied via `preferredColorScheme` at the window root on every
  platform. Floating control surfaces (player overlays/badges, hero, book, and album
  actions) adopt Liquid Glass on OS 26+ through availability-gated helpers
  (`SharedUI/GlassStyle.swift`) with system-Material fallbacks at the current deployment
  floors; visionOS keeps its native glass (`glassBackgroundEffect`, bordered buttons).
  *Acceptance:* light/dark/system all render correctly; glass surfaces appear on OS 26
  and degrade to Materials below it.

---

## M1.5 — Winter Chill Theme Alignment

**Goal:** migrate the app from the previous Jellyfin-inspired brand colors to the official
Winter Chill palette everywhere it appears, and keep future UI work consistent with that
theme.

- [x] **Palette asset refresh.** Update every brand color asset and generated-color input
  to the M1 Winter Chill role table: `AccentColor`, launch background, cinema key/fill/
  backdrop colors, current app icon assets, and any other non-system brand tokens.
  *Acceptance:* asset catalog values match the roadmap roles in light and dark mode; old
  brand hex values are gone from source-controlled assets/scripts/docs except historical
  ADR context; `xcodegen generate` and the platform builds still pass. *(Done — verified
  by grep across Sources/Scripts/docs.)*
- [x] **Winter Chill app icon regeneration.** Regenerate the iOS/macOS app icon, tvOS
  brand assets, Top Shelf images, and visionOS layered icon from the Gus brand mark SVG.
  *Acceptance:* actool produces no icon warnings on any destination, the icon reads clearly
  in light/dark launchers, and generated images no longer use the old purple/blue palette.
  *(Done; iOS additionally ships dark and tinted appearance variants. The legacy pineapple
  generator is retired.)*
- [~] **Theme consistency audit.** Sweep signed-out, signed-in, playback, downloads,
  settings, search, music, photos, books, Live TV, CarPlay, Top Shelf, and visionOS Cinema
  surfaces for stale brand colors or one-off styling. Preserve Apple semantic colors,
  Materials, Dynamic Type, focus, and accessibility behavior; do not replace system status
  colors with custom brand colors unless a future palette expansion adds accessible status
  tokens. *Acceptance:* light mode, dark mode, Reduce Transparency, tvOS focus, and
  visionOS glass all stay legible and visually aligned with Winter Chill. *(Code-side
  complete — all custom color flows through the refreshed semantic tokens; the
  per-platform visual verification pass rides the release regression matrix.)*
- [~] **Brand documentation and screenshot alignment.** Update `AGENTS.md`, `CLAUDE.md`,
  README/support copy where they mention brand colors, then recapture App Store/demo
  screenshots after the palette lands. *Acceptance:* docs and screenshots describe/show
  Winter Chill consistently, and no release-facing artifact still presents the old palette
  as current. *(Docs updated — AGENTS.md palette table and cinema comments; screenshot
  recapture remains once marketing capture runs.)*

---

## M2 — Engineering Quality & CI

**Goal:** the codebase is safe to grow — consistent errors, formatting, tests, and
automated build verification. (Covers priority: *polish & testing*.)

- [x] **Error & cancellation model.** Introduce a small typed error surface and adopt
  structured-concurrency cancellation (cancel in-flight loads on view disappearance / new
  query). *Acceptance:* navigating away mid-load cancels the request; errors render via
  `ContentUnavailableView`, never a silent failure. *(Done: `GusError` maps common error
  cases and stores/views ignore cancellation instead of surfacing stale failures.)*
- [x] **Logging consistency.** One `OSLog` category convention across stores/services; no
  `print`. *Acceptance:* logs are filterable by subsystem/category in Console. *(Done:
  `Logger(category:)` centralizes the subsystem and categories.)*
- [x] **Formatting & linting.** Add SwiftFormat (and/or SwiftLint) config as a build-time
  dev tool with a documented `make`/script entry. *Acceptance:* `format` script is
  idempotent; CI fails on violations. *(Done: `.swiftformat`, `Scripts/format.sh`, and CI
  lint are present.)*
- [x] **Unit test target.** Add `GusTests` covering pure logic: URL normalization,
  `SessionCredential.account`, `StreamURLBuilder` profile/URL selection,
  `MediaItem+Display` formatting, `ServerStore` round-trip. *Acceptance:*
  `xcodebuild test` passes; meaningful assertions (not smoke-only). *(Done: Swift Testing
  unit coverage is wired into native iOS, tvOS, visionOS, and macOS test bundles, with
  iPhone and iPad covered through the iOS scheme.)*
- [x] **UI smoke test (optional).** One XCUITest: launch → Connect screen renders.
  *Acceptance:* available for local/manual launch validation. *(Done: `GusLaunchUITests`
  verifies the Connect screen renders through native iOS, tvOS, visionOS, and macOS UI
  test bundles; CI keeps these UI smoke tests out of the required PR pipeline.)*
- [x] **CI pipeline.** GitHub Actions: validate the shared project/pins → resolve →
  build the iPhone/iPad/macOS/tvOS/visionOS/Watch matrix → run native unit tests → lint.
  *Acceptance:* successful required checks on the complete current source. *(Configured
  on the hosted `xcode-27` runner with a minimum iOS simulator SDK of 27.1. Final
  run `38192282611` at `edd06e6636cd32b877622dbcb4ccb34524a1b3c1` passed **13/13 jobs**:
  six builds, five unit lanes, lint and docs. Each unit lane passed 288 Swift Testing
  cases in 49 suites and three separate XCTest measurements. Native audio completion,
  replay and deletion/no-stream assertions passed with the one-second 48 kHz fixture
  and unchanged eight-second deadline. The earlier 400 ms fixture failures remain
  recorded with their cause unresolved; no production workaround was added. See
  [full hosted evidence](AppStore/cloud-onboarding-evidence/github-ci/run-38192282611-summary.json).
  This is separate from successful 4/4 Xcode Cloud BUILD and device/release acceptance.
  Current GUS-UI-040 source `64505d9dfd337c90f390c7c66503912eac252d3f` passed Cloud Build 3 4/4 BUILD
  actions and [GitHub run `38194318738`, attempt 2](https://github.com/eslutz/A-Playa-Named-Gus/actions/runs/38194318738/attempts/2)
  completed **13/13 successful checks**. iPad alone reran unchanged; the other 12 successes
  were carried forward from attempt 1. Each accepted unit lane passed 288 cases/49 suites
  plus three separate XCTest measurements, including both actual native audio cases.
  The initial iPad completion failure remains recorded with its cause unresolved; retry
  acceptance does not establish a reliable fix. [Current proof](AppStore/cloud-onboarding-evidence/github-ci/run-38194318738-attempt-2-summary.json).)*
- [x] **Update `project.yml` for the test target & schemes.** *Acceptance:* generated
  project includes the test targets; the per-platform `Gus <platform> Unit Tests` test
  actions work (the `A Playa Named Gus` scheme is build-only). *(Done: platform-native
  unit/UI test targets, CI unit schemes, and local UI-inclusive platform schemes are
  generated from `project.yml`.)*

---

## M3 — Core Feature Completeness

**Goal:** the app does what users expect of a Jellyfin client. (Covers priority:
*deferred features*.)

- [x] **Search.** Global search (`Paths.getItems` with `searchTerm`) surfaced per platform
  (`.searchable`, tvOS search tab). *Acceptance:* debounced, cancellable, paginated
  results with a no-results state. *(Done: `SearchStore` drives debounced, cancellable,
  paginated `getItems` search; iOS/iPadOS/macOS/visionOS use `.searchable`, and tvOS has a
  Search tab.)*
- [x] **Series → seasons → episodes.** Detail hierarchy for shows (`getItems` by
  parent/`getSeasons`/`getEpisodes`) with season picker and episode list. *Acceptance:*
  can navigate Series → Season → Episode → Play. *(Done: series details load seasons and
  selected-season episodes with independent states; the native season picker and episode
  rows navigate to episode detail/playback.)*
- [x] **Richer item metadata.** People (cast/crew), genres, studios, community/critic
  ratings, taglines on the detail screen. *Acceptance:* fields render when present, degrade
  gracefully when absent. *(Done: item details fetch full metadata and render optional
  taglines, genres, studios, critic/community ratings, and cast/crew only when present.)*
- [x] **Playback progress reporting.** `Paths.reportPlaybackStart/Progress/Stopped` so
  resume + Continue Watching stay accurate; resume from saved position. *Acceptance:*
  server reflects progress; "Continue Watching" updates after playback. *(Done: playback
  seeks to saved ticks, reports start/progress/stop, and increments an app-level refresh
  marker after successful stop reporting.)*
- [x] **Multi-user / multi-server switching.** Account switcher in Settings; store and pick
  among known `StoredUser`s/servers (tokens already keyed by `serverID:userID`).
  *Acceptance:* switch without re-entering credentials; sign out one without affecting
  others. *(Done: Settings groups stored users by server, switches when a token exists,
  offers sign-in-again for missing tokens, current-user sign-out removes only that user's
  token/record, and launch restore uses the server-qualified `serverID:userID` key.)*
- [x] **Quick Connect.** `getQuickConnectEnabled` → `signIn(quickConnectSecret:)`.
  *Acceptance:* code-based sign-in works where the server enables it; hidden when disabled.
  *(Done: Quick Connect checks availability after server selection, displays the polling
  code, cancels on disappearance, and signs in through the shared persistence path.)*
- [x] **Bonjour discovery (optional).** `JellyfinClient.discover()` behind the
  `NSLocalNetworkUsageDescription` permission, with manual entry still primary.
  *Acceptance:* discovered servers are selectable; permission prompt only when used.
  *(Done: a user-initiated Find Local Servers action discovers and deduplicates local
  servers, handles empty/error states, and fills the manual URL field when selected.)*

---

## M4 — Playback Depth

**Goal:** playback is competitive and system-integrated.

- [~] **Audio & subtitle track selection.** Expose `MediaStream`s; let the user switch
  audio/subtitle tracks (request appropriate stream indices / transcode). *Acceptance:*
  track changes apply; selection persists within a session. *(Implementation note:
  playback plumbing still supports `AVMediaSelection` in-place switches and Jellyfin
  stream-index rebuilds for transcoded streams. tvOS can still expose these through
  Apple's native `transportBarCustomMenuItems`, but the custom non-tvOS video options
  overlay was removed. Restoring iOS/iPadOS/macOS/visionOS in-player selection is tracked
  as a native-player API gap in ADR 0011.)*
- [x] **Native player pipeline & chrome overhaul.** Make the AVKit player behave and
  look first-party: an honest, hardware-gated device profile and pure system chrome.
  *Acceptance:* compatible files direct-play untouched; transcodes preserve surround,
  HDR honesty, and manifest subtitles; the system surface presents item metadata.
  *(Done: `DevicePlaybackCapabilities` gates HEVC/AV1 direct play on
  `VTIsHardwareDecodeSupported` and HDR ranges on `AVPlayer.eligibleForHDRPlayback`
  (Hi10P/interlaced H.264 excluded via codec conditions); the transcode target is
  HEVC-preferred fMP4 HLS with 8-channel audio and `enableSubtitlesInManifest` (text
  subs ride the manifest, only bitmap subs burn in); `AVPlayerItem.externalMetadata`
  feeds the system title/info chrome (sans macOS, which lacks the API);
  `updatesNowPlayingInfoCenter = false` on iOS so `NowPlayingController` is the single
  Now Playing writer; custom non-tvOS player option overlays were removed so video stays
  on system chrome (see ADR 0011 for the native API gaps this exposes); macOS video opens
  in a dedicated cinematic `WindowGroup` (QuickTime-style, green-button fullscreen)
  instead of a sheet; natural end auto-plays the next episode (Settings toggle, default on)
  or dismisses the player; pause/resume report immediately instead of on the 10 s tick;
  and Settings gains a Streaming Quality picker (Maximum/High/Medium/Low) replacing the
  hardcoded 120 Mbps.)*
- [~] **Picture in Picture.** Enable PiP where supported (iOS/iPadOS/macOS) and verify the
  background-audio + `UIBackgroundModes` path. *Acceptance:* PiP starts on backgrounding;
  audio continues. *(Implementation note: the iOS/iPadOS surface is now
  `AVPlayerViewController` with `allowsPictureInPicturePlayback` and automatic PiP on
  backgrounding, and macOS uses `AVPlayerView` with PiP enabled — SwiftUI `VideoPlayer`
  exposed no PiP, which this replaces; device PiP/background verification is still
  pending in the manual verification.)*
- [~] **AirPlay & external displays.** Verify AVKit AirPlay routing. *Acceptance:* route
  picker works; playback hands off cleanly. *(Implementation note: external playback is
  enabled where available, iOS/iPadOS use AVKit's system player route affordance, macOS
  relies on native AVKit/system behavior for video, and audio playback still exposes
  `AVRoutePickerView`. The removed custom video route picker is not planned to return.)*
- [~] **Now Playing artwork & metadata polish.** Load poster into `MPMediaItemArtwork`
  (platform image), accurate duration/elapsed/rate. *Acceptance:* lock screen / Control
  Center / Apple TV Remote show artwork + correct scrubbing. *(Implementation note:
  artwork loading and platform artwork conversion are in place;
  `changePlaybackPositionCommand` now powers the lock-screen/Control Center scrubber, and
  Now Playing carries media type plus album/artist metadata for audio items;
  lock-screen/remote visual verification is pending manual verification.)*
- [x] **Chapters & next-up.** Chapter markers if present; auto-play next episode / up-next
  prompt. *Acceptance:* chapter skip works; next episode offered at credits. *(Done:
  chapter targets render as seek actions and episode playback loads Jellyfin next-up with a
  near-credits prompt.)*
- [~] **visionOS Cinema integration.** Sync the immersive Cinema with the active player
  (state, dismissal). *Acceptance:* entering/leaving Cinema never interrupts windowed
  audio; graceful fallback if the space can't open. *(Implementation note: Cinema open
  state and fallback paths are wired; simulator/device verification is pending manual
  verification.)*
- [x] **visionOS 3D video playback.** Support stereoscopic/spatial playback on Vision Pro
  where Jellyfin metadata or user override can identify a 3D source. *Acceptance:*
  supported 3D formats are documented, playback chooses the correct AVKit/visionOS
  presentation path, and unsupported formats fall back gracefully. *(Done: MV-HEVC uses
  AVKit direct play with a Spatial badge; SBS/TAB uses the Gus Cinema RealityKit screen;
  MVC, missing direct play, and non-visionOS platforms fall back to 2D with notices where
  visible. The removed manual override is not planned to return without a native
  system-presented viewing-mode surface. Device-only stereo separation remains a manual
  Vision Pro verification item.)*

---

## M5 — Platform Polish & Accessibility (HIG pass)

**Goal:** each platform feels first-party; the app is fully accessible and localized.

- [x] **tvOS.** Focus engine polish (poster focus scaling, sensible focus order), Top Shelf
  content, large-canvas layout. *Acceptance:* navigable entirely by remote; focus never
  trapped/lost. *(Done: poster navigation preserves native focus styling, related rails
  and grids are grouped for focus, and the `GusTopShelf` extension is content-aware — it
  renders the signed-in user's Continue Watching row (artwork, progress bars, play/detail
  actions via `gus://play` / `gus://item` links) from a credential-free App Group snapshot
  written by `HomeStore`, falling back to static home/search/settings shortcuts when
  signed out. The app target declares tvOS User Management so each Apple TV profile gets
  separate app storage and Keychain-scoped Jellyfin tokens.)*
- [x] **visionOS.** Ornaments/toolbars, `.glassBackgroundEffect()` on panels, hover
  effects, real look-to-scroll, depth-aware layout. *Acceptance:* matches HIG immersive
  guidance; comfortable at default scale. *(Done: signed-in panels use glass, split-view
  toolbar actions expose fixed destinations, Cinema control moves to a bottom ornament,
  and look-to-scroll is enabled when available. Z-offset depth layout is deferred — the
  current flat layout reads cleanly at the default visionOS scale.)*
- [x] **macOS.** Menu-bar commands (`Commands`), keyboard shortcuts, window sizing/restore,
  toolbar. *Acceptance:* core actions have menu items + shortcuts; window state restores.
  *(Done: app-level Commands route home/search/settings and sign out, window sizing is set
  via `defaultSize`/`windowResizability`, `SceneStorage` restores the sidebar selection
  across launches, split-view toolbar actions mirror the command destinations, and user-domain
  storage/Keychain keep separate macOS login accounts isolated.)*
- [x] **iPad.** Pointer/keyboard support, multitasking/Stage Manager sizing,
  split-view tuning. *Acceptance:* usable with keyboard/trackpad; adapts to all size
  classes. *(Done: hover affordances remain system-native, keyboard route shortcuts are
  available on keyboard platforms, and the split view uses fixed route toolbar actions.)*
- [~] **Accessibility audit.** VoiceOver across every screen, Dynamic Type to the largest
  sizes, contrast, Reduce Motion/Transparency. *Acceptance:* a representative VoiceOver
  pass completes each core flow; no clipping at AX5. *(Source implementation and scoped
  native audits are complete; manual VoiceOver speech/rotor/focus acceptance remains open.
  Poster cards expose combined
  accessibility labels, playback controls have labels/hints, section headers are marked
  `.isHeader` for VoiceOver rotor navigation, episode rows emit combined locator/title/
  runtime labels, the metadata row is combined into one focus stop, and Reduce
  Transparency replaces the Material placeholder with an opaque tonal fill.)*
- [x] **Localization pass.** Finalize the base catalog; verify pseudolocalization &
  layout. *Acceptance:* no hardcoded strings; UI survives pseudoloc. *(Done: all user-
  facing strings are in `Localizable.xcstrings` with comments; the critic rating uses
  explicit `String(localized:comment:)` with a translator comment; the catalog builds
  successfully across the platform matrix.)*

---

## M6 — Performance & Resilience

**Goal:** smooth with large libraries and flaky networks.

- [x] **Library pagination / lazy loading.** Page `getItems` with infinite scroll and
  prefetch. *Acceptance:* a 5k-item library scrolls smoothly; memory stays bounded. *(Done:
  `LibraryStore` uses shared `Paging`, page size 60, total-record counts, and prefetches
  within the final 12 items; `LibraryGridView` shows a bottom loading indicator.)*
- [x] **Image pipeline tuning.** Right-size `URLCache`, request appropriately sized images,
  cancel offscreen loads. *Acceptance:* no redundant full-size fetches; scroll stays
  jank-free. *(Done: `ImageURLBuilder.ImageContext` centralizes a fixed width set for grid,
  rail, backdrop, and Now Playing artwork; the documented 64 MB memory / 512 MB disk
  `URLCache` budget remains unchanged.)*
- [x] **Network resilience.** Timeouts, retry/backoff where sensible, offline-tolerant
  empty states, reachability messaging. *Acceptance:* server-down and slow-network paths
  degrade gracefully, never hang. *(Done: `JellyfinClientFactory` sets request/resource
  timeouts while keeping `waitsForConnectivity`; `NetworkRetryPolicy` adds opt-in retries
  only for idempotent foreground loads; `GusError` surfaces clearer timeout/offline
  messages; `LoadingStateView` supports an optional Try Again action.)*
- [x] **Offline downloads.** Background downloads on iOS/iPadOS, macOS, and visionOS;
  tvOS excluded. *Acceptance:* local playback, pause/resume/delete, disk-budget surfacing,
  and an explicit go/no-go recorded. *(Done: `DownloadSourceResolver` keeps
  AVPlayer-native originals and sends incompatible media through Jellyfin's progressive
  MP4 conversion endpoint with independent video/audio stream copying, preserving
  resolution and surround audio when compatible; HEVC sample-entry metadata is
  normalized for native Apple playback. `DownloadSessionCoordinator` preserves the
  completed temporary file before its delegate returns and uses a native background
  `URLSessionDownloadTask`; `OfflineDownloadStore` persists status/progress/resume data,
  stores per-server/user media in Application Support, excludes media from backup,
  enforces a 20 GB soft cap plus low-space guard, and prefers local playback URLs. ADR
  0005 records the enhanced background/transcode scope and tvOS exclusion.)*
- [~] **Download feedback and offline library (#15, #16).** Actual received bytes,
  optional total/percentage, measured speed/ETA, stalled/waiting states, and a main
  Downloaded section with local search, show/season grouping, account isolation, cached
  artwork, and local playback checkpoints. iOS background completion uses a minimal
  native lifecycle bridge. Implementation and automated verification are tracked locally;
  physical iPhone background/airplane-mode acceptance is still required before closure.

---

## M7 — Media Server Provider Architecture

**Goal:** isolate Jellyfin-specific API and DTO assumptions behind a provider boundary
before the 1.0 release path, so A Playa Named Gus can stay Jellyfin-only at launch while
preserving a clean route to future backends such as Emby.

- [x] **Provider boundary.** Introduce a media-server provider abstraction such as
  `MediaServerProvider`, with Jellyfin as the only production implementation for 1.0.
  *Acceptance:* feature stores depend on provider/domain contracts for core operations
  rather than directly on Jellyfin SDK call shapes; no non-Jellyfin runtime dependency is
  added. *(Done: `MediaProviderSession` is the signed-in media boundary, with
  `JellyfinMediaProviderSession` as the only production adapter and no new runtime
  dependency.)*
- [x] **Gus-native domain models.** Move feature views and stores away from Jellyfin SDK
  DTOs for libraries, media items, people, images, playback sources, playback sessions,
  remote commands, progress events, and server capabilities. *Acceptance:* UI code renders
  Gus-native models, with Jellyfin DTO mapping isolated inside the Jellyfin provider.
  *(Done: `MediaItem`, media stream/source, image, playback, download, and reporting
  contracts now drive feature views/stores; Jellyfin DTO mapping lives in
  `Sources/Providers/Jellyfin`.)*
- [x] **Provider-scoped persistence.** Persist accounts, tokens, server IDs, user IDs,
  playback preferences, and cached metadata with an explicit provider identity.
  *Acceptance:* existing Jellyfin users migrate without reauthentication, token lookup
  remains Keychain-backed, and future providers can coexist without account/key collisions.
  *(Done: persisted server/user/session records carry `providerKind`, Keychain accounts
  use `jellyfin:serverID:userID`, and restore migrates legacy Jellyfin token accounts.)*
- [x] **Capability-driven feature availability.** Add a capability model so UI can show,
  hide, or degrade features based on backend and server configuration. *Acceptance:*
  feature code does not spread `if Jellyfin` / `if Emby` checks; provider-specific behavior
  stays behind the provider implementation or capability mapping. *(Done:
  `ProviderCapabilities` gates search/download entry points while provider-specific
  behavior stays behind the session adapter.)*
- [x] **Regression coverage and ADR.** Capture the provider architecture decision and add
  focused tests for Jellyfin mapping, persistence migration, playback source selection, and
  capability handling. *Acceptance:* current Jellyfin connect, browse, search, detail,
  playback, progress, downloads, and settings flows behave unchanged across all supported
  platforms. *(Done: ADR 0008 records the boundary; focused tests cover Jellyfin mapping,
  provider-scoped credentials, legacy token migration, playback reporting/domain
  selection, download source selection, and capability-disabled downloads.)*

---

## M8 — App Store Readiness

**Goal:** everything Apple requires to accept and review the app.

- [x] **Complete available local candidate validation and commits.** Execute the iOS 27 Swift,
  UI/UX/design, accessibility, reliability, privacy and guideline validation plan;
  remediate verified findings, validate the full staged candidate, and commit all
  existing and new repository changes across app/wiki/website. Track manual and
  portal acceptance separately. See
  [the execution plan](Reviews/2026-10-10-release-validation/PLAN.md) and
  [final scoped results](Reviews/2026-10-10-release-validation/VALIDATION.md).
  Six builds, four 282-test suites, maintained/expanded native UI and state tests,
  shared macOS sanitizers and four unsigned Release archives pass. Manual, SDK
  migration and portal gates remain separate; M8 release readiness stays open.

Readiness documents, the GitHub Actions/Xcode Cloud ownership split, committed paid
Developer Team ID, and the app privacy manifest now live under `Documentation/AppStore/`,
`Config/Shared.xcconfig`, `ci_scripts/`, and `Resources/PrivacyInfo.xcprivacy`, but M8
remains unchecked until App Store Connect privacy answers, Xcode Cloud signing, archive
validation, TestFlight, and submission work are actually done.

- [ ] **Privacy manifest & nutrition labels.** Keep `Resources/PrivacyInfo.xcprivacy`
  aligned with actual required-reason API and data-use behavior, then complete App Privacy
  answers in App Store Connect (data not collected by A Playa Named Gus itself; connects
  to a user-provided server). *Acceptance:* manifest validates; App Store Connect labels
  match behavior. *(Started: `PrivacyInfo.xcprivacy` is bundled with no tracking, no
  collected data types, Disk Space `E174.1` for low-space download refusal, and
  UserDefaults `CA92.1`; remaining work is
  App Store Connect privacy answers and policy fields.)*
- [~] **Signing & capabilities.** Real Team/bundle id, Xcode Cloud signing, per-platform
  capability review (background audio, tvOS User Management, sandbox on macOS, Optic ID
  string). *Acceptance:* Xcode Cloud Release archives sign for each platform. *(Code side
  complete per `Documentation/AppStore/signing-capabilities.md` — entitlements, capability
  declarations, committed Team ID, and the Optic ID/Face ID no-usage-string rationale;
  Cloud Build 2 passed all four iOS/macOS/tvOS/visionOS BUILD actions for code commit
  `084a470`; remaining work is signed Release archive validation,
  CarPlay audio (`com.apple.developer.carplay-audio`, manual Apple grant), and device
  verification for the portal-backed App Groups, Associated Domains, Shared with You, and
  Declared Age Range capabilities.)*
- [ ] **App Store Connect record.** Create the app, set categories, age rating, support &
  marketing URLs, privacy policy URL, description, keywords. *Acceptance:* record
  complete and consistent across platforms, using the published `gus.ericslutz.dev`
  support, privacy, and marketing pages.
- [ ] **Hosted review, support, and compliance pages.** Publish the five pages at
  `gus.ericslutz.dev` — marketing, support, privacy policy, accessibility, and age
  suitability — per `Documentation/AppStore/review-support-pages.md`. *Acceptance:* all
  pages are live over HTTPS and App Store Connect URLs plus review notes reference them.
- [~] **Accessibility readiness and disclosure.** Native Apple accessibility initiative
  across all five platforms; scope, feature requirements, and validation matrix per
  `Documentation/AppStore/accessibility.md`. *Acceptance:*
  `https://gus.ericslutz.dev/accessibility` is published and linked from the
  website/support pages; App Store accessibility disclosures match implemented support;
  major user flows are usable with relevant Apple accessibility features; release testing
  passes the matrix in `Documentation/AppStore/accessibility.md`. *(Code-side audit done:
  VoiceOver labels and headers from M5, item-specific Voice Control names on repeated
  download actions, decorative icons hidden, no color-only state, no custom animations so
  Reduce Motion is respected by construction, caption/alternate-audio menus in the
  player; remaining work is the manual device validation matrix and the published page.)*
- [~] **Diagnostics & reliability foundation.** Implement Apple-native diagnostics (crash
  triage, MetricKit, performance baselines, review cadence) without third-party analytics;
  scope per `Documentation/AppStore/diagnostics-reliability.md`. *Acceptance:* that
  document's acceptance checklist is complete and privacy disclosures match implemented
  behavior. *(Started: `DiagnosticsHub` lifecycle markers/signposts, `MetricKitCollector`
  with platform gaps documented, `DiagnosticSummaryStore`, XCTest + launch-script
  baselines recorded; remaining items need TestFlight builds.)*
- [~] **Copyright-safe demo media library.** Implement a demo library for App Store
  screenshots, previews, review access, and TestFlight validation using only
  rights-cleared content, kept separate from personal libraries. *Acceptance:*
  the demo library can populate Home, library grids, search, item detail, playback, and
  downloads for screenshot capture and reviewer/tester walkthroughs; demo credentials or
  setup steps are documented; all screenshot/TestFlight media assets are confirmed
  rights-cleared before upload. *(Started: `Scripts/demo-server.sh` runs a local Jellyfin
  container over the public-domain/CC0 `sample_media/` library with automated first-run
  setup; `--gus-demo-server` launch argument and a Debug-only Connect button sign
  straight in; Home population verified on the iPhone simulator; docs in
  `Documentation/AppStore/demo-server.md`. Remaining: tap-through validation of
  playback/downloads per platform and a hosted instance for App Review access; TV-series/
  Live-TV/spatial examples are not yet represented in the sample library, which also
  blocks their screenshot scenes.)*
- [~] **Screenshots & previews.** Required sizes for iPhone/iPad/Apple TV/Vision Pro/Mac
  (scripted via `simctl` where possible). *Acceptance:* all required slots filled.
  *(Started: `Scripts/screenshots.sh` resolves required-size simulators by name, drives
  the demo server (`--gus-demo-server` + `--gus-route`), and captures Connect, Home,
  Libraries, and Settings on iPhone/iPad/Apple TV/Vision Pro/Apple Watch, plus
  deep-linked content scenes (movie detail, album, book detail, video player) via
  `gus://item`/`gus://play` content links on every simulator platform; macOS stays
  manual per the script's instructions. TV-series and Live TV scenes need demo data
  first (see the demo-library item). Final marketing-quality capture and App Store
  Connect upload remain.)*
- [x] **Review-guidelines compliance audit.** Walk the
  [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/):
  third-party-server clients, scoped ATS (`NSAllowsLocalNetworking` for self-hosted LAN
  HTTP; TLS required remotely), no private API, export-compliance
  (`ITSAppUsesNonExemptEncryption=false`).
  *Acceptance:* documented self-audit with no open red flags. *(Done:
  `Documentation/AppStore/review-compliance-audit.md` walks guidelines 1–5, audits the
  shipped configuration, and drafts the Notes for Review and age-rating answers.)*
- [x] **Local API/Cloud preparation.** Secure key location, ignored configuration, native
  read-only API client, offline signing/bootstrap tests, shared project snapshot and
  dependency pins prepared. Account-wide API authentication and Cloud onboarding are
  verified; the complete candidate is published to `origin/main` and passed all four
  Cloud BUILD actions. Signed archive acceptance remains pending; see `AppStore/api-access.md`
  and `AppStore/xcode-cloud-dependency-onboarding.md`.
- [ ] **TestFlight beta.** Upload through Xcode Cloud, internal/external testing, gather
  crash/feedback.
  *Acceptance:* a clean build runs from TestFlight on each platform.

---

## M9 — Submission & Launch

**Goal:** ship 1.0 and be ready to respond.

- [ ] **Release regression matrix.** Full pass of every core flow on every platform on the
  Release build. *Acceptance:* checklist signed off.
- [ ] **Xcode Cloud archive & upload** each platform; attach metadata; submit for review.
  *Acceptance:* "Waiting for Review" on all.
- [ ] **Review response.** Address any rejections; resubmit. *Acceptance:* "Ready for
  Sale."
- [ ] **Post-launch.** Monitor crash/feedback; triage into a 1.0.x / next-version backlog.
  *Acceptance:* monitoring in place; backlog seeded.

---

## Cross-cutting: documentation (continuous)

Treat documentation as part of every milestone, not a phase:

- [ ] Keep this roadmap, `AGENTS.md`, and `CLAUDE.md` accurate as scope evolves.
- [x] Record significant technical decisions as short ADRs in `Documentation/adr/`
  (e.g., "AVKit-only playback", "Observation over ObservableObject", "XcodeGen as project
  source of truth"), so the *why* survives.
- [x] Keep `README.md` aligned with the current build/verify story. *(Done: README covers
  the current connect→browse/search→detail→play→settings/downloads flow, offline downloads
  scope, the five-destination build, and the unit/UI test action.)*

---

## Future Features

These were scoped as post-1.0 work, outside the App Store path above. Several have since
**landed in the codebase ahead of being formally milestoned** — they ship in the app today
even if post-1.0 device verification or polish remains — while others are still unstarted.
The per-item checkbox is the source of truth (`[x]` done · `[~]` in progress · `[ ]` not
started); the table below is a status-at-a-glance index. Promote an item into a numbered
milestone once it becomes the active focus and is ready to carry a hard acceptance bar.

| Feature | Status |
|---|---|
| Disney+ catalog/progress integration, mixed video playlists, and unified Next Up | `[ ]` Not started — authenticated Disney+ validation and product choices pending |
| Customizable main navigation | `[x]` Done |
| Content deep links & system integration (Universal Links, Shared with You, Handoff, Spotlight, Siri, Top Shelf) | `[x]` Done |
| Music library support | `[~]` In app; genre browse + live-library validation remain |
| Books & audiobooks | `[~]` In app; visionOS reader blocked on an upstream Readium fix |
| Photos | `[~]` In app; favorites + casting remain |
| Live TV & DVR | `[~]` In app; full EPG grid + tuner-equipped validation remain |
| CarPlay audio companion | `[~]` In app; entitlement + Siri intents + vehicle test remain |
| SharePlay | `[x]` Native Group Activities integration with item-detail system launch |
| Family safety controls & age assurance | `[~]` In app; Declared Age Range entitlement wired, device verification remains |
| watchOS companion | `[~]` In app; on-device verification matrix remains |
| Expanded immersive environments | `[ ]` Not started |
| Apple Intelligence library assistant & generated artwork | `[ ]` Not started |
| WidgetKit home screen & lock screen widgets | `[ ]` Not started |
| Push Notifications | `[ ]` Future — [#12](https://github.com/eslutz/A-Playa-Named-Gus/issues/12) |
| Tap to Share | `[ ]` Future — [#13](https://github.com/eslutz/A-Playa-Named-Gus/issues/13) |
| User-initiated diagnostic export | `[ ]` Not started |
| Advanced accessibility enhancements | `[ ]` Not started |
| Emby support (provider investigation) | `[ ]` Not started — unblocked by M7 |

- [~] **watchOS companion app.** Build a focused watchOS experience that extends A Playa
 Named Gus beyond the five launch platforms without trying to make the watch the primary video
 client. Scope, constraints, and tradeoffs: `Documentation/watchos-brief.md`.
 *Acceptance:* the brief's verification matrix passes on watch hardware.
 *(Implemented: the `GusWatch` target (standalone-capable companion, embedded in the iOS
 archive) ships the full v1 brief — session status glance, Sessions-API remote control
 with WebSocket live updates + polling fallback (`RemoteSessionsStore`/`SessionsSocket`),
 quick resume to a chosen client, lightweight per-library browse, on-watch audio through
 the shared `AudioPlayerStore` with long-form audio routing, offline audio downloads
 under a 2 GB watch budget, constrained on-watch video via the native `VideoPlayer` with
 remote-playback fallback, standalone Quick Connect sign-in, and WatchConnectivity
 credential hand-off from the iPhone. CI builds the watch lane. Remaining: the brief's
 on-device verification matrix — real-client remote control, route-picker audio, battery
 soak, and WatchConnectivity hand-off on hardware.)*

- [ ] **Expanded immersive environments.** Enhance Gus Cinema with additional native
 RealityKit environments or scene variants that remain comfortable, performant, and
 playback-focused. *Acceptance:* users can choose from multiple immersive environments,
 environment changes do not interrupt playback, and the default remains simple and stable.

- [~] **SharePlay.** Use Apple's native Group Activities stack for shared playback
 sessions instead of Jellyfin SyncPlay. *Acceptance:* users can start SharePlay from
 the item-detail native system surface, incoming SharePlay sessions route to the shared
 item via the existing content-link player flow, and the active `AVPlayer` coordinates
 through `AVPlaybackCoordinator` without sharing Jellyfin tokens or stream URLs.
 *(Implementation note:
 `SharePlayCoordinator` defines the `GusPlaybackActivity`, listens for incoming
 `GroupActivity.sessions()`, opens the requested item through `AppNavigationModel`, and
 calls `coordinateWithSession` on the live player. Eligible item detail screens present
 Apple's native `GroupActivitySharingController` on iOS/iPadOS/visionOS/macOS; tvOS can
 still join and coordinate incoming sessions but does not expose that sharing controller.
 The old Jellyfin SyncPlay store/socket/menu/tests have been removed. Leaving/ending
 SharePlay stays in Apple's system SharePlay controls, not custom player chrome.)*

- [x] **Customizable main navigation.** Let users choose from Settings which sections are
 visible in the primary app menu/tab/sidebar and in what order, while keeping Home fixed at
 the start and Settings fixed at the end. *Acceptance:* users can hide and reorder all
 intermediate navigation items with native edit controls, the preference persists per app
 user, unavailable provider sections are handled gracefully, and each platform still
 preserves its native tab, sidebar, or focus behavior. *(Done:
 `NavigationPreferencesStore` persists per-account order/visibility for the Libraries
 grid plus consolidated categories (Movies, Shows, Music, Books, Photos, Live TV);
 Settings → Navigation edits with toggles and move controls that work on every platform
 including tvOS focus; all three roots (tabs, visionOS sidebar, split view) render the
 customized sections dynamically; removed categories drop gracefully and newly available
 categories append visible; `gus://` routes map onto
 the customized layout with a Home fallback when Libraries is hidden.)*

- [x] **Content deep links & system integration.** Deep-link individual library items and
 surface them through the system features that depend on it. *Acceptance:* `gus://item/
 <id>`, `gus://play/<id>`, `https://gus.ericslutz.dev/item/<id>`, and
 `https://gus.ericslutz.dev/play/<id>` open the detail surface or player from a cold or
 warm launch; system entry points carry no credentials and refuse links donated by another
 account. *(Done: `ContentLink` + a consume-once `AppNavigationModel` pending-link
 request resolve ids through the session provider (`Platform/ContentLinkHandler.swift`),
 gated by family-safety restrictions. Built on it: **Universal Links / Shared with You** —
 `applinks:gus.ericslutz.dev` supports `/item/*` and `/play/*`, Apple's
 `SWHighlightCenter` feeds a Home "Shared with You" rail, and item detail shows Apple's
 `SWAttributionView` when the current account can resolve the shared link;
 **Handoff** — detail and player surfaces publish `NSUserActivity` (ids only) and continue
 on another device;
 **Core Spotlight** — `SpotlightIndexer` donates browsed/loaded items with
 `server|user|item` identifiers, opens results in-app, and deindexes on sign-out (no
 watchOS/tvOS indexing); **Siri/App Intents** — a "Play media" intent with provider
 search plus an App Shortcut phrase; **tvOS Top Shelf** — static deep-link entry points
 plus personalized Continue Watching when the App Group snapshot is available. Remaining:
 device verification of Shared with You, Handoff/Siri/Spotlight, Universal Links, and the
 personalized Top Shelf surface.)*

- [ ] **Apple Intelligence library assistant and generated artwork.** Integrate Apple's
 Foundation Models, Core Spotlight LLM search, Private Cloud Compute, and Image Playground
 APIs after the relevant WWDC26 / iOS 27-era SDKs are stable enough for App Store release.
 Candidate scope:
 - Natural-language library search and recommendations: users can ask broad or precise
   questions such as "I feel like watching a sci-fi movie in space with aliens and lots of
   guns or action" or "movies with Batman and the Joker in them," and Gus returns only
   grounded matches from the user's own indexed libraries.
 - Grounding/indexing: donate provider-neutral `MediaItem` metadata to Core Spotlight,
   including title, media type, collection, genres, overview, taglines, people/cast,
   character/role names when available, studios, production year, ratings, play state,
   favorites, and server/provider IDs. Do not let model world knowledge fabricate matches
   that are not present in the library.
 - Model routing: prefer the on-device Foundation Models system model for private,
   offline-capable search and lightweight recommendations; use Private Cloud Compute only
   for requests that need larger context, stronger reasoning, multimodal input, or many
   tool calls, with Apple Intelligence availability checks, user-facing fallback, and no
   app-owned cloud/API key path.
 - Query behavior: combine `SpotlightSearchTool` / Foundation Models tool calling with
   existing provider search/filter APIs so conversational results can still open native
   library, item detail, and playback flows; preserve deterministic filters for exact
   constraints such as "must include both Batman and Joker."
 - Evaluation: build an `Evaluations` dataset from demo-library and fixture metadata to
   verify result coverage, exact-match constraints, hallucination resistance, family-safety
   filtering, offline/on-device fallback, and Private Cloud Compute fallback behavior.
 - Generated posters/covers: use the Image Playground API for user-initiated artwork
   generation from media metadata and optional user prompts. The user must preview and
   approve the result, select whether it becomes a poster/primary image or backdrop, and
   explicitly choose to sync it back to the media server.
 - Server sync: add provider-gated artwork upload/update support only where the server
   account has permission; preserve the original artwork where possible, record a revert
   path, respect metadata locking/provider policy, and handle unsupported providers by
   keeping the generated artwork local.
 - Platform/availability gate: Foundation Models search should target iOS, iPadOS, macOS,
   and visionOS first; Image Playground-generated artwork should ship only on platforms
   where Apple exposes the API and the current device supports Apple Intelligence. tvOS,
   unsupported devices, unsupported regions/languages, daily Private Cloud Compute limits,
   and disabled Apple Intelligence settings must fall back to the existing search and
   artwork flows.
 *Acceptance:* a product/technical brief cites the Apple API availability being targeted,
 decides on-device vs Private Cloud Compute routing for each use case, defines privacy
 copy and consent boundaries, proves Core Spotlight indexing coverage for the supported
 media types, documents Jellyfin artwork upload/revert behavior, and ships an evaluation
 matrix before implementation begins.

- [~] **Music library support.** Add first-class Jellyfin music browsing and playback:
 artists, albums, songs, playlists, genres, shuffle/repeat, queue management, background
 audio, Now Playing metadata, AirPlay routing, and offline audio downloads where supported.
 *Acceptance:* users can browse and play music independently of movie/show workflows, with
 accurate progress/state, native audio controls, and platform-appropriate background
 behavior. *(Started: music domain types and artist/album/track browse
 (`ArtistAlbumsView`/`AlbumDetailView`), `AudioPlayerStore` queue engine with
 shuffle/repeat and progress reporting, `AudioPlayerView` with transport/AirPlay,
 universal-audio streaming + offline audio originals/transcodes; genre browse and
 device validation against a live library remain.)*

- [~] **Live TV & DVR support.** Add Jellyfin Live TV and DVR functionality including
 channel guide, live channel playback, recording library, scheduled recordings, and
 recording management. *Acceptance:* users can browse the guide, start live playback, view
 recordings, and manage scheduled recordings with clear unsupported-state handling when
 the server has no tuner/DVR configured. *(Started: `LiveTVView` serves channels with
 now-airing info, recordings, and cancellable scheduled recordings behind a Live TV
 availability probe, with a clear no-tuner state; channel playback rides the normal
 playback pipeline. A full EPG grid and recording creation remain; validation needs a
 tuner-equipped server.)*

- [~] **Family safety controls and age assurance.** Add parent-friendly content controls
 using Apple-provided safety APIs rather than a custom age-verification or child-profile
 system. Candidate scope includes reading the device's effective movie and TV rating
 restrictions through ManagedSettings media settings, mapping Jellyfin parental/official
 ratings onto those thresholds, hiding or clearly gating media above the effective limit,
 and explaining when content is unavailable because of a system family setting. Evaluate
 Declared Age Range / `AgeRangeService` for privacy-preserving age-aware defaults,
 age-gated preferences, active parental-control signals, and region-specific age assurance
 obligations; do not store birthdates or exact ages. Evaluate PermissionKit/significant
 update flows for future changes that require parent or guardian consent. Treat
 FamilyControls, DeviceActivity, and additional ManagedSettings restrictions as
 entitlement-gated follow-up work only if Gus needs Screen Time-style controls beyond
 media-rating filtering. *Acceptance:* a family-safety product brief documents platform
 availability, entitlement/review requirements, Jellyfin rating-field mapping, behavior for
 unrated media, age-gate choices, privacy/data-retention rules, App Store Connect age
 rating impacts, and a test matrix for child, teen, adult, declined-sharing, and missing
 system-restriction scenarios before implementation starts. *(Implemented:
 `Documentation/family-safety-brief.md` is the acceptance artifact; `ContentRatingGate`
 covers US and international rating systems (BBFC/FSK/ACB/Canadian, country prefixes,
 bare ages) and now gates item detail and playback with a clear explanation in addition
 to filtering Home/library/search/similar/Up Next/Live TV recordings/CarPlay/watch
 lists; Declared Age Range (iOS/macOS 26+) offers privacy-preserving age-aware defaults
 from Settings with the entitlement now wired, pending real-device system-sheet
 verification; ManagedSettings/FamilyControls device-restriction reading remains
 entitlement-gated follow-up per the brief.)*

- [ ] **WidgetKit home screen, lock screen, and desktop widgets.** Add WidgetKit widgets
 for iPhone, iPad, and Mac that surface the most useful at-a-glance information from the
 user's Jellyfin library without requiring the app to be open. Candidate scope:
 - **Continue Watching** — the top in-progress item (poster, title, progress bar) with a
   tap that deep-links to `gus://play/<id>` to resume immediately. Small, medium, and
   large sizes; Lock Screen / StandBy accessory variant showing title + progress.
 - **On Deck / Next Up** — next unwatched episode in an active series, with series
   artwork and episode name. Medium and large sizes.
 - **Recently Added** — a grid of newly added library items for the configured library
   section. Medium and large sizes.
 - **Interactive widget actions** (iOS 17+/macOS 14+) — a play button inline in the
   widget that fires a `gus://play/<id>` intent without opening the app's full UI.
 - **Widget configuration** — a WidgetKit `AppIntentConfiguration` lets users pick which
   server, user, and library section to display; the widget uses a credential-free App
   Group snapshot, which should be wired only after the App Group is enabled in the
   developer portal.
 - **Live Activities / Dynamic Island** — a Now Playing Live Activity for active video
   or audio playback, showing artwork, title, and elapsed/remaining time with play/pause
   controls from the lock screen or Dynamic Island.

 Implementation notes:
 - Use `WidgetKit` + `AppIntentConfiguration`; `TimelineProvider` fetches from the App
   Group snapshot (no direct network call from the widget extension).
 - The widget extension target links only `Models/` and the App Group snapshot reader —
   no `JellyfinClient`, no `Keychain`, no `AVPlayer`. All content resolves from the
   snapshot the main app keeps fresh.
 - Deep links use the existing `gus://item/<id>` and `gus://play/<id>` content link
   scheme (`Models/ContentLink.swift`); the main app's `ContentLinkHandler` handles them.
 - Artwork is cached in the shared container as downscaled thumbnails so the widget
   extension never makes image network requests.
 - Declare the widget extension in `project.yml` with the App Group entitlement; add the
   extension target to the `Gus iOS Unit Tests` scheme for widget snapshot tests.

 *Acceptance:* a product brief defines which widget families ship first, the App Group
 snapshot schema additions needed, the timeline refresh cadence and rate-limit strategy,
 privacy copy (no credentials leave the device, no server URL in the widget UI unless the
 user opts in), and a device test matrix covering iPhone home screen, Lock Screen, StandBy,
 iPad home screen, and Mac desktop before implementation starts.

- [ ] **User-initiated diagnostic export.** Add a Settings diagnostics section after the
 Apple-native diagnostics foundation is stable. The export must be explicitly initiated by
 the user and never automatic. Candidate bundle contents include app version, OS version,
 device model, active server type/version when available, playback engine information,
 recent application events, error history, and MetricKit summaries where appropriate. The
 bundle must exclude authentication tokens, passwords, personally identifiable information,
 server URLs unless explicitly approved by the user, and other sensitive data, then use the
 Share Sheet for support workflows. *Acceptance:* a product brief defines redaction rules,
 export format, user consent copy, platform availability, support intake workflow, and
 regression tests before implementation starts.

- [ ] **Advanced accessibility enhancements.** After the App Store accessibility readiness
 work is complete, evaluate deeper platform-specific accessibility features that are not
 required for the initial release. Candidate scope includes Assistive Access-oriented
 simplification, Switch Control and Full Keyboard Access stress testing, custom VoiceOver
 rotors for long media lists, richer caption/audio-description preference persistence,
 additional visionOS comfort settings, and automated accessibility snapshots where Apple
 tooling supports them. *Acceptance:* a follow-up accessibility brief defines which
 advanced features materially improve Gus beyond the launch accessibility baseline without
 adding custom systems that duplicate Apple-provided accessibility behavior.

- [~] **Books and audiobooks.** Add support for Jellyfin book libraries, with special focus
 on audiobooks as an audio-first playback experience. Candidate scope includes book
 browsing, audiobook playback, playback speed, chapter navigation, bookmarks, resume
 progress, and offline audiobook downloads. *Acceptance:* audiobook progress syncs
 reliably with Jellyfin and the UX is distinct from video playback. *(Started: book/
 audiobook domain types; audiobooks play through the audio player with speed control,
 chapter menu, resume-from-server-position, and offline downloads. Reading: books
 download as originals, every non-tvOS platform gets a share sheet whose primary job is
 "Open in Books", and iOS/iPadOS get an in-app Readium reader with chapter navigation
 (ADR 0009). Reading position resumes exactly on the same device and syncs a coarse
 fraction to Jellyfin (`UserData.PlaybackPositionTicks`) for cross-device/Continue —
 a spike confirmed Jellyfin 10.11 round-trips it, gated by `supportsBookProgressSync`.
 tvOS browses details only by design; visionOS reading is blocked on an upstream Readium
 xrOS compile fix (tracked in the ADR).)*

- [ ] **CarPlay audio companion.** Add an iOS-only CarPlay experience after the music and
 audiobook foundations are in place. Candidate scope includes a minimal Listen Now entry
 point, music and audiobook browsing through native CarPlay templates, offline audio
 playback, system Now Playing artwork/progress, play/pause/seek/next/previous transport
 controls, and an "Open Gus on iPhone to sign in" fallback when no session is available.
 This should use the CarPlay audio entitlement and system CarPlay templates rather than a
 custom vehicle UI, and it should not expose movie/show browsing or promote in-car video
 playback as a supported use case. *Acceptance:* a CarPlay product brief defines the
 audio-only scope, entitlement/review requirements, iOS-only build settings, Siri/
 `INPlayMediaIntent` needs, provider capability dependencies, offline behavior, and
 simulator/vehicle verification matrix before implementation starts. *(Started:
 `GusCarPlaySceneDelegate` + `CarPlayContentController` serve album/audiobook tabs and
 Now Playing over the restored session via native templates; the carplay-audio
 entitlement is documented but unwired pending Apple's grant
 (`Documentation/AppStore/signing-capabilities.md`); Siri media intents and CarPlay
 simulator/vehicle verification remain.)*

- [~] **Photos.** Add Jellyfin photo library browsing with albums, timelines, full-screen
 viewing, slideshows, favorites, and casting/photo playback to larger clients. *Acceptance:*
 users can browse photo libraries comfortably across platforms and start a slideshow on a
 selected playback device. *(Started: photo grids browse through the shared library
 pipeline and `PhotoViewerView` adds full-screen paging plus a Reduce Motion-aware
 slideshow; favorites and casting to other playback devices remain.)*

### Emby Support

- [ ] **Emby provider investigation.** Investigate adding Emby as the first non-Jellyfin
 backend after the M7 provider architecture is complete. Emby is the preferred first
 additional backend because its personal-media-server model, REST API surface, media item
 concepts, playback model, session model, and remote-control capabilities are closer to
 Jellyfin than Plex.

 Candidate scope:
 - Manual Emby server connection by URL.
 - Emby user authentication using server-local credentials.
 - Secure storage of Emby access tokens by provider, server ID, and user ID.
 - Optional Emby Connect support after manual multi-server support is working.
 - Library browsing for movies, shows, seasons, episodes, music, photos, books, and
   audiobooks where available.
 - Global search.
 - Detail screens using Gus-native media models rather than Emby DTOs directly.
 - Direct play and transcoded playback URL generation.
 - Audio/subtitle stream selection.
 - Playback start/progress/stopped reporting.
 - Resume and Continue Watching support.
 - Image loading.
 - Active session discovery.
 - Remote playback control through Emby sessions.
 - Client/device selection.
 - Play, pause, stop, seek, next/previous, volume, mute, audio stream, and subtitle stream
   commands where supported by the target Emby client.
 - Capability detection for Emby-specific availability and entitlement differences.

 Provider architecture dependency:
 - Build on the M7 provider boundary instead of introducing another abstraction.
 - Implement Emby as a separate provider behind the same Gus-native domain models,
   persistence model, playback contracts, and capability model.
 - Keep Emby-specific behavior behind the Emby provider and capability mapping.

 Emby-specific considerations:
 - Emby supports both direct server authentication and optional Emby Connect flows.
 - Emby Connect should be treated as an enhancement, not the primary connection path.
 - Emby remote control is session-based and should map cleanly to the planned watchOS and
   cross-device playback-control model.
 - Emby media types overlap heavily with Jellyfin, including audio, video, movies,
   episodes, series, music albums/artists, books, and photos.
 - Emby Downloads & Sync, DVR, hardware-accelerated transcoding, and some app/client
   capabilities may depend on Emby Premiere.
 - The app should represent Premiere-gated functionality as capability/entitlement state
   rather than assuming all Emby servers support every feature.
 - Shared playback should remain Apple-native through SharePlay unless an Emby-specific
   capability is needed for a future non-Apple platform.
 - Branding, naming, App Store metadata, and support copy must make it clear which backend
   a user is connecting to and avoid implying that Emby support is official unless that is
   explicitly approved.

 Prototype sequence:
 1. Implement an internal Emby prototype for connect, authenticate, libraries, search,
    movie/show detail, playback, and progress reporting.
 2. Add Emby remote-control/session support.
 3. Add media-type-specific Emby coverage for music, books/audiobooks, photos, and Live
    TV/DVR.
 4. Evaluate whether Emby support should ship as a full app mode, an experimental backend,
    or a separate build/configuration.

 *Acceptance:* a technical brief defines the Emby auth/token model, minimum supported Emby
 feature set, Premiere-gated capability handling, testing requirements, App Store naming/
 branding constraints, and the first Emby prototype milestone. No user-facing Emby work
 starts until M7 is complete.

## October 11 current validation and publication status

The phone's three requested final flows completed on build 11: Downloads management landscape scrolling/Cancel, compact portrait/landscape actions, and Home capture. No physical automation or new install is pending. The Home capture exposed GUS-UI-038, subsequently repaired with native top-toolbar search in compact-height iOS 26+ layouts and verified on the simulator. GUS-UI-037's largest-text action separation and full narrow-screen bounds are verified in light/dark portrait/landscape. Both later repairs remain source/simulator acceptance rather than build-11 physical acceptance.

Xcode 27.1 RC is installed. SDK-backed Duo audio arrangement and closed, flat-open, and partially folded simulator flows passed individually. A native Device Hub check also passed sampled audio continuity through closed → open → partially open → closed, then Pause, resume, and Stop, retaining the same demo title with intentional Repeat One wraps. [Scoped transition evidence](Reviews/2026-10-11-auth-device-repair/evidence/duo-transitions/acceptance.json) does not measure audible gaps/black-frame duration or cover every video/navigation/sheet flow. Exact minimum-OS execution remains blocked by unavailable compatible runtimes and the lack of a macOS 15 host/VM; deployment-target builds are not minimum-OS execution. Manual VoiceOver speech, rotor, and focus-order acceptance remains open.

Final source review repaired Vision Pro capsule hover shapes, video preparation/autoplay teardown, independent artwork backfill/progress synchronization, nested EPUB chapter navigation, and audio replay after natural queue completion. The focused playback run passed 23/23, including real WAV replay, local-only behavior after automatic deletion, and all three video lifecycle regressions. Full source/test lint passes for 193 files; shared project validation covers 12 schemes and 16 pins, and **9/9 Cloud bootstrap tests pass**. The final native EPUB chapter sheet acceptance passed 1/1, zero skipped, with inspected portrait/landscape prose, forward/backward paging, and return-to-detail captures. Readium’s directional navigation adapter is retained and bound to the navigator; hardware-key input and completion deletion specifically while opening Chapters at the final page were source-reviewed rather than runtime-tested. Tests are serialized with two build jobs after measured host memory pressure was relieved. Detailed evidence and test scope live in [the repair report](Reviews/2026-10-11-auth-device-repair/REPORT.md).

The unused ReadiumAdapterGCDWebServer product is removed; the 16 validated pins, including Readium 3.9.0, remain. Account-wide App Store Connect API authentication and initial Cloud onboarding are verified. The manual-only Gus Multiplatform Validation workflow has four BUILD actions (iOS/macOS/tvOS/visionOS), Xcode 27.1 RC, and a compatible macOS host, without distribution. The reviewed app repairs, shared snapshot/pins, and bootstrap repair are published to `origin/main`. Cloud Build 1 failed its post-clone identity check because the runtime reported the verified account UUID instead of the 10-character signing Team ID. Build 2 completed successfully for all four required BUILD actions and resolved all 16 pinned repositories, validating code commit `084a470683a78256e939bd63b416bc2fb0150bb2`. Later documentation and CI configuration changes retain that app-source build provenance. Signed Release archive validation, upload, and TestFlight acceptance remain pending. See [API setup](AppStore/api-access.md) and [Cloud diagnosis](AppStore/xcode-cloud-dependency-onboarding.md).

The preceding candidate passed **13/13 GitHub jobs** in run `38192282611` at exact commit `edd06e6636cd32b877622dbcb4ccb34524a1b3c1`: all six builds, five unit lanes, lint and docs. Each lane passed 288 Swift Testing cases in 49 suites and three separate XCTest measurements, including the strengthened native audio completion/replay and automatic-deletion/no-stream cases. The one-second 48 kHz PCM fixture retains the eight-second wait limit; the earlier 400 ms/8 kHz failure cause remains unproven. [Lane evidence](AppStore/cloud-onboarding-evidence/github-ci/run-38192282611-test-lanes.json). That tested app source matches Cloud-verified `084a470`. Current GUS-UI-040 source `64505d9dfd337c90f390c7c66503912eac252d3f` gives hero/About artwork media-appropriate fallback symbols and hides decorative artwork from accessibility. [Cloud Build 3](AppStore/cloud-onboarding-evidence/run-3/summary.json) accepted all four BUILD actions with zero errors and seven unchanged warnings. [GitHub run 38194318738, attempt 1](https://github.com/eslutz/A-Playa-Named-Gus/actions/runs/38194318738/attempts/1) passed 12/13 jobs, including all six builds; iPad recorded one native first-completion issue. [Failure proof](AppStore/cloud-onboarding-evidence/github-ci/run-38194318738-attempt-1-ipad-test-failure.json). [Attempt 2](https://github.com/eslutz/A-Playa-Named-Gus/actions/runs/38194318738/attempts/2) subsequently accepted **13/13 checks** after an unchanged-source iPad-only retry, carrying forward the other 12 successes. Every accepted unit lane passed 288 Swift Testing cases/49 suites plus three separate XCTest measurements and both native audio cases; iPad replay/deletion passed in 5.097/1.278 seconds. [Current lane proof](AppStore/cloud-onboarding-evidence/github-ci/run-38194318738-current-test-lanes.json). The first failure’s cause remains unresolved, and a reliable fixture/platform fix is not claimed. Build 2 retains its historical source/package-resolution evidence; sampled Duo runtime acceptance predates this edit. Internal-only TestFlight is authorized and the all-pipelines-pass prerequisite is met, while signed archive/upload/distribution acceptance remains pending. The remaining physical, minimum-OS, assistive, full Mac and release gates remain open.


### Internal TestFlight release status

Required current-source CI is accepted after the unchanged iPad retry; the internal release attempt is a separate unmet gate. Cloud Build 4 failed iOS export and Mac preparation for App Store Connect at `64505d9`; tvOS/visionOS `1.0.0 (4)` uploads are valid/ready, but all four distribution post-actions were skipped and `Gus Internal` has no builds with the tester still `NOT_INVITED`. The generic errors do not establish a cause. Signed distribution, account access and installation acceptance remain open. [Release report](AppStore/internal-testflight-release.md), [final proof](AppStore/cloud-onboarding-evidence/internal-testflight/run-4-summary.json).

### Build warning repair — October 12, 2026

Cloud Build 6 accepted all four required BUILD actions with zero errors and zero warnings after the six iOS/one Mac diagnostics were repaired. Readium loading now owns each publication graph until its one-time transfer to the main actor; normalized URL comparison replaces the deprecated operator. Declared Age Range interoperability is scoped to the SDK annotation gap with the existing main-actor request guard retained. Complete checking remains enabled. A test-only URL correction is published on `main`; its full regression matrix is pending. [Repair and proof](AppStore/build-warning-repairs.md).

The internal release gate exposed default iOS/Watch PNG alpha channels after signed export. Independent Apple validation supplied concrete rejection codes `90396`/`90717`; opaque store-canvas repair and a platform-aware artwork assertion are published at `64b9de6`/`f354c7a`. The earlier failed assertion is retained, and corrected CI plus signed retry/group install eligibility remain pending. [Icon repair](AppStore/icon-upload-repair.md), [release status](AppStore/internal-testflight-release.md).


Native Icon Composer source recreation is published at `f1a387f`. The existing Gus vector G/play mark remains editable, with default/dark/monochrome and round Watch previews captured. Four-platform Cloud Build 8 passed without issues. The preceding PNG repair CI passed 13/13; the separate native-source CI and subsequent signed release/group eligibility remain pending. [Source](AppStore/icon-composer-source.md).


October 12 pipeline policy supersedes direct-main publication: main now requires PRs, all 13 GitHub checks, resolved conversations, and administrator enforcement. Cloud accepts only exact main and requires unit tests before internal distribution. The compile-only workflow is deleted. Native icon source passed Cloud Build 8 without issues; CI 38242041231 passed 12/13, with the existing audio end-notification failure on iPad retained as an unresolved diagnostic. No icon failure or successful tester access is inferred from that attempt.

## Unified Next Up and Jellyfin lists — feature branch

- [~] Combine Continue Watching and saved/automatic next episodes into one Next Up list ordered by genuine viewing/list activity; preserve undated legacy order and missing saved references.
- [~] Jellyfin owns native playlist and Collection/BoxSet names, IDs, membership, playlist order and permissions. Gus keeps an account-scoped cache and durable per-operation offline edits. Jellyfin 10.11.11 deduplicates playlist items, so native lists contain each media item once; an uncertain create/add outcome requires review before an explicit retry.
- [~] Ordered movie/episode/video playback and persistent cursors apply only to all-video playlists, independently of normal episode autoplay. Existing audio playlists remain visible and open the audio player; mixed-media entries open individually. Collections group titles and do not form autoplay queues.
- [~] Private CloudKit synchronizes supplemental Gus playlist cursors, saved Next Up intent and activity, rather than native list definitions. Previous Gus-owned playlists remain preserved and can be explicitly imported into Jellyfin; import refuses legacy lists with repeated items rather than silently collapsing them. Credentials, server URLs, signed artwork and downloaded files remain excluded.
- [ ] Signed iCloud container/provisioning and physical iPhone → Apple TV sync, offline/reconnect, playback/cursor and accessibility acceptance. Native list implementation and validation are tracked in [the implementation ledger](Reviews/2026-10-13-jellyfin-lists/IMPLEMENTATION.md); no release acceptance is claimed.

## Native tvOS presentation — local feature candidate

- [~] Native sidebar and dedicated Search; cinematic focus-driven unified Next Up and recently-added fallback, adaptive TV grids, TV detail composition and direct Account menu.
- [~] Session-owned identity/index focus bookmarks plus horizontal scroll restoration; poster progress/watched accessibility values and full-synopsis sheet.
- [~] Native AVKit display matching, Playback Info/Next Episode, single TV video Now Playing owner, background pause and pause/rate-preserving server track rebuilds.
- [ ] Compatible tvOS 27 runtime capture and remote-only focus, Back/Menu, repeated/cancelled account/playback flows; physical VoiceOver/HDR/audio and signed private-sync acceptance remain open.

Based on merged PR #21 (`c847a27`): Jellyfin owns playlists and collections; unique native membership, permissions and explicit legacy import remain unchanged. No duplicate-entry queue product is introduced. Local implementation and evidence: [TV redesign](Reviews/2026-10-13-tvos-redesign/IMPLEMENTATION.md). No publication or release acceptance is claimed.
