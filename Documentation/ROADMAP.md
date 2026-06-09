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

- [x] **App icon (all platforms).** Jellyfin navy background `#000B25` with a
  purple-to-blue pineapple (`#AC5CC3` → `#00A4DC`) — egg-shaped body with a diamond
  crosshatch lattice and a tight, mostly upright spiky crown. Produce
  `AppIcon.appiconset` (iOS + macOS idioms), `AppIcon.brandassets` (tvOS App Icon + Top
  Shelf), and `AppIcon.solidimagestack` (visionOS layered), all named `AppIcon`; remove the
  `ASSETCATALOG_COMPILER_APPICON_NAME: ""` override in `project.yml`.
  *Acceptance:* actool produces no missing-icon errors on any SDK; icon renders on each
  Home screen / launcher. *(Done: a placeholder pineapple generated with
  `Scripts/generate-app-icon.swift`; all five destinations build green and actool bakes
  `AppIcon` per platform. The artwork is a clean placeholder — final brand polish can
  refine it later.)*
- [x] **Launch experience.** Confirm `UILaunchScreen` presents cleanly; consider a minimal
  branded launch on platforms that support it. *Acceptance:* no flash of unstyled content;
  consistent first frame. *(Done: iOS/iPadOS use a color-only `UILaunchScreen` backed by
  the `LaunchBackground` asset.)*
- [x] **Accent & semantic theme pass.** Centralize the Jellyfin-aligned app palette
  (accent + cinema
  palette) as semantic color assets with light/dark variants; audit views for hardcoded
  colors. *Acceptance:* light/dark both legible; no raw `Color(red:…)` in feature views.
  *(Done: cinema colors live in asset catalog colorsets; windowed UI uses semantic color
  tokens where custom color is needed.)*
- [x] **String Catalog baseline.** Move all current literal UI strings into
  `Localizable.xcstrings` with comments. *Acceptance:* `SWIFT_EMIT_LOC_STRINGS` shows no
  un-catalogued user-facing strings in changed files. *(Done: the base catalog is seeded
  with current UI and user-facing error strings.)*

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
  `BaseItemDto+Display` formatting, `ServerStore` round-trip. *Acceptance:*
  `xcodebuild test` passes; meaningful assertions (not smoke-only). *(Done: Swift Testing
  unit coverage is wired into native iOS, tvOS, visionOS, and macOS test bundles, with
  iPhone and iPad covered through the iOS scheme.)*
- [x] **UI smoke test (optional).** One XCUITest: launch → Connect screen renders.
  *Acceptance:* available for local/manual launch validation. *(Done: `GusLaunchUITests`
  verifies the Connect screen renders through native iOS, tvOS, visionOS, and macOS UI
  test bundles; CI keeps these UI smoke tests out of the required PR pipeline.)*
- [x] **CI pipeline.** GitHub Actions (macOS runner): `xcodegen generate` → resolve →
  build all five destinations → run tests → lint. *Acceptance:* green check required on
  every PR; matrix covers all platforms. *(Done: CI runs on macOS 26 with Xcode
  26.5, and requires SwiftFormat/string-catalog lint, an iPhone/iPad/macOS/tvOS/visionOS
  build matrix, plus native unit tests on each platform.)*
- [x] **Update `project.yml` for the test target & schemes.** *Acceptance:* generated
  project includes test target; `-scheme 'A Playa Named Gus'` test action works. *(Done:
  platform-native unit/UI test targets, CI unit schemes, and local UI-inclusive platform
  schemes are generated from `project.yml`.)*

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

- [x] **Audio & subtitle track selection.** Expose `MediaStream`s; let the user switch
  audio/subtitle tracks (request appropriate stream indices / transcode). *Acceptance:*
  track changes apply; selection persists within a session. *(Done: playback exposes
  audio/subtitle menus, posts selected stream indices, rebuilds the player item, and
  preserves position.)*
- [~] **Picture in Picture.** Enable PiP where supported (iOS/iPadOS/macOS) and verify the
  background-audio + `UIBackgroundModes` path. *Acceptance:* PiP starts on backgrounding;
  audio continues. *(Implementation note: background audio is configured and AVKit surfaces
  build across iOS/iPadOS/macOS; device PiP/background verification is still pending in the
  manual verification.)*
- [~] **AirPlay & external displays.** Verify AVKit AirPlay routing. *Acceptance:* route
  picker works; playback hands off cleanly. *(Implementation note: system
  `AVRoutePickerView` is wired for supported platforms and external playback is enabled
  where available; route handoff verification is pending manual verification.)*
- [~] **Now Playing artwork & metadata polish.** Load poster into `MPMediaItemArtwork`
  (platform image), accurate duration/elapsed/rate. *Acceptance:* lock screen / Control
  Center / Apple TV Remote show artwork + correct scrubbing. *(Implementation note:
  artwork loading and platform artwork conversion are in place; lock-screen/remote visual
  verification is pending manual verification.)*
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
  AVKit direct play with a Spatial badge and manual override; SBS/TAB uses the Gus Cinema
  RealityKit screen; MVC, missing direct play, and non-visionOS platforms fall back to 2D
  with notices where visible. Device-only stereo separation remains a manual Vision Pro
  verification item.)*

---

## M5 — Platform Polish & Accessibility (HIG pass)

**Goal:** each platform feels first-party; the app is fully accessible and localized.

- [x] **tvOS.** Focus engine polish (poster focus scaling, sensible focus order), Top Shelf
  content, large-canvas layout. *Acceptance:* navigable entirely by remote; focus never
  trapped/lost. *(Done: poster navigation preserves native focus styling, related rails
  and grids are grouped for focus, and a static `GusTopShelf` extension opens home,
  search, and settings via `gus://` routes. The app target declares tvOS User Management so
  each Apple TV profile gets separate app storage and Keychain-scoped Jellyfin tokens.)*
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
- [x] **Accessibility audit.** VoiceOver across every screen, Dynamic Type to the largest
  sizes, contrast, Reduce Motion/Transparency. *Acceptance:* a representative VoiceOver
  pass completes each core flow; no clipping at AX5. *(Done: poster cards expose combined
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
  MP4 transcode endpoint; `DownloadSessionCoordinator` uses a native background
  `URLSessionDownloadTask`; `OfflineDownloadStore` persists status/progress/resume data,
  stores per-server/user media in Application Support, excludes media from backup,
  enforces a 20 GB soft cap plus low-space guard, and prefers local playback URLs. ADR
  0005 records the enhanced background/transcode scope and tvOS exclusion.)*

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
  collected data types, Disk Space `85F4.1`, and UserDefaults `CA92.1`; remaining work is
  App Store Connect privacy answers and policy fields.)*
- [ ] **Signing & capabilities.** Real Team/bundle id, Xcode Cloud signing, per-platform
  capability review (background audio, tvOS User Management, sandbox on macOS, Optic ID
  string). *Acceptance:* Xcode Cloud Release archives sign for each platform.
- [ ] **App Store Connect record.** Create the app, set categories, age rating, support &
  marketing URLs, description, keywords. *Acceptance:* record complete and consistent
  across platforms.
- [ ] **Screenshots & previews.** Required sizes for iPhone/iPad/Apple TV/Vision Pro/Mac
  (scripted via `simctl` where possible). *Acceptance:* all required slots filled.
- [ ] **Review-guidelines compliance audit.** Walk the
  [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/):
  third-party-server clients, ATS justification (`NSAllowsArbitraryLoads` for self-hosted
  HTTP), no private API, export-compliance (`ITSAppUsesNonExemptEncryption=false`).
  *Acceptance:* documented self-audit with no open red flags.
- [ ] **TestFlight beta.** Upload through Xcode Cloud, internal/external testing, gather
  crash/feedback.
  *Acceptance:* a clean build runs from TestFlight on each platform.

---

## M9 — Submission & Launch

**Goal:** ship 1.0 and be ready to respond.

- [ ] **Release regression matrix.** Full pass of every core flow on every platform on the
  Release build. *Acceptance:* checklist signed off.
- [ ] **Archive & upload** each platform; attach metadata; submit for review. *Acceptance:*
  "Waiting for Review" on all.
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

These are intentionally outside the 1.0 App Store path above. Promote them into a
milestone only after the launch scope is stable.

- [ ] **watchOS companion app.** Build a focused watchOS experience that extends A Playa
 Named Gus beyond the five launch platforms without trying to make the watch the primary video
 client. Candidate scope includes server/session status, Now Playing glance, remote
 playback control for any active Jellyfin client, client/device selection, quick resume,
 lightweight library browsing, direct audio playback, offline audio downloads, and novelty
 direct video playback on the watch. Offline downloads are limited to audio-first content
 on watchOS; direct video playback is treated as an advanced/secondary feature and should
 not be promoted as a primary use case. *Acceptance:* a watchOS product brief defines the
 minimum useful feature set, platform constraints, Jellyfin API requirements, battery/
 storage/network tradeoffs, and whether it ships as a companion-only target or a
 standalone-capable watchOS app.

- [ ] **Expanded immersive environments.** Enhance Gus Cinema with additional native
 RealityKit environments or scene variants that remain comfortable, performant, and
 playback-focused. *Acceptance:* users can choose from multiple immersive environments,
 environment changes do not interrupt playback, and the default remains simple and stable.

- [ ] **SyncPlay.** Add Jellyfin SyncPlay support for shared playback sessions. Candidate
 scope includes creating/joining/leaving groups, selecting a host/client, synchronized
 play/pause/seek, participant visibility, and graceful handling of drift or unsupported
 clients. *Acceptance:* users can create or join a SyncPlay group and maintain synchronized
 playback across supported Jellyfin clients.

- [ ] **Music library support.** Add first-class Jellyfin music browsing and playback:
 artists, albums, songs, playlists, genres, shuffle/repeat, queue management, background
 audio, Now Playing metadata, AirPlay routing, and offline audio downloads where supported.
 *Acceptance:* users can browse and play music independently of movie/show workflows, with
 accurate progress/state, native audio controls, and platform-appropriate background
 behavior.

- [ ] **Live TV & DVR support.** Add Jellyfin Live TV and DVR functionality including
 channel guide, live channel playback, recording library, scheduled recordings, and
 recording management. *Acceptance:* users can browse the guide, start live playback, view
 recordings, and manage scheduled recordings with clear unsupported-state handling when
 the server has no tuner/DVR configured.

- [ ] **Books and audiobooks.** Add support for Jellyfin book libraries, with special focus
 on audiobooks as an audio-first playback experience. Candidate scope includes book
 browsing, audiobook playback, playback speed, chapter navigation, bookmarks, resume
 progress, and offline audiobook downloads. *Acceptance:* audiobook progress syncs
 reliably with Jellyfin and the UX is distinct from video playback.

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
 simulator/vehicle verification matrix before implementation starts.

- [ ] **Photos.** Add Jellyfin photo library browsing with albums, timelines, full-screen
 viewing, slideshows, favorites, and casting/photo playback to larger clients. *Acceptance:*
 users can browse photo libraries comfortably across platforms and start a slideshow on a
 selected playback device.

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
 - SyncPlay should remain Jellyfin-specific unless an equivalent Emby-supported shared
   playback model is identified.
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
