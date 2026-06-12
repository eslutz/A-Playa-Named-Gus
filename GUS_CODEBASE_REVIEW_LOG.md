# Gus Codebase Review Log

Review started: 2026-06-12

Scope: static codebase review of Gus, a Swift/SwiftUI Jellyfin client for iOS, iPadOS, tvOS, watchOS, visionOS, and macOS. This log is a persistent checkpoint record for sub-agent results, batch summaries, manual verification items, and deferred areas.

## Review Progress Log

### Completed Sub-Agents

- Apple UX and Human Interface Expert - Complete
- Swift, SwiftUI, and Architecture Expert - Complete
- Jellyfin Integration and Networking Expert - Complete
- Media Playback Expert - Complete
- Security, Privacy, and Child Safety Expert - Complete
- Performance, Caching, and Responsiveness Expert - Complete (orchestrator-authored after delegated reviewer timeout)
- Platform, Build, Dependency, and App Store Expert - Complete
- Accessibility and Localization Expert - Complete
- Testing, Dead Code, and Maintainability Expert - Complete

### Remaining Sub-Agents

- None

### Current Batch

- Batch 2 complete

## Sub-Agent Checkpoints

### Apple UX and Human Interface Expert

- Status: Complete
- Files, targets, modules, or systems inspected: `project.yml`, `Resources/Info.plist`, `Resources/Watch/Info.plist`, `Sources/App/GusApp.swift`, `Sources/App/RootView.swift`, `Sources/Platform/RootContainer.swift`, `Sources/Platform/AppNavigationModel.swift`, `Sources/Platform/GusCommands.swift`, `Sources/Platform/PlatformModifiers.swift`, Connect/Home/Search/Library/Item/Live TV/Settings/Downloads/Books/Photos/Player feature folders, `Sources/SharedUI`, `Resources/Localizable.xcstrings`, `Tests/APlayaNamedGusUITests/GusLaunchUITests.swift`, `Documentation/AppStore/accessibility.md`, roadmap/platform notes.
- Summary of findings: Gus is strongly aligned with the Apple-first mandate overall. The shell uses native `TabView`, `NavigationSplitView`, `NavigationStack`, `.searchable`, `Form`, AVKit playback surfaces, `ContentUnavailableView`, scene storage, watchOS `verticalPage`, tvOS Top Shelf, and visionOS `ImmersiveSpace`. UX risks cluster around macOS settings conventions, scene-global navigation in multiwindow environments, custom material rows inside Forms, and watchOS control target size.
- Detailed findings:
  - Finding: macOS settings are routed as app content, not a native Settings scene.
    - Severity: Medium
    - Impact: macOS users expect preferences from the app menu and `Command-,` in a dedicated Settings window; Gus exposes settings in app content/sidebar instead.
    - Affected platforms: macOS
    - Evidence: `Sources/App/GusApp.swift` declares main/player `WindowGroup`s but no `Settings` scene; `Sources/Platform/RootContainer.swift` embeds `SettingsView` as a root section; `Sources/Platform/GusCommands.swift` exposes Settings under a custom Navigate menu.
    - Recommended fix: Add a macOS `Settings` scene with the same app/session dependencies and route system Settings / `Command-,` through SwiftUI settings APIs. Keep sidebar settings only if desired.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: App-wide singleton navigation conflicts with declared multiwindow support.
    - Severity: Medium
    - Impact: iPadOS Stage Manager, macOS, and visionOS windows can share route/search state unexpectedly.
    - Affected platforms: iPadOS, macOS, visionOS
    - Evidence: `Resources/Info.plist` enables multiple scenes; `Sources/App/GusApp.swift` injects `AppNavigationModel.shared`; `Sources/Platform/AppNavigationModel.swift` is singleton-backed; `Sources/Platform/RootContainer.swift` observes shared route state.
    - Recommended fix: Make route/search state scene-scoped or disable/constrain multiwindow support if independent windows are not intended.
    - Confidence: Medium
    - Manual verification required: Yes
  - Finding: Custom material card rows inside native Forms reduce first-party form feel.
    - Severity: Low
    - Impact: Local server and public profile rows fight native Form/List styling and may weaken focus/selection affordances.
    - Affected platforms: iOS, iPadOS, macOS, tvOS, visionOS
    - Evidence: `Sources/Features/Connect/ConnectServerView.swift` uses `.buttonStyle(.plain)` and `.thinMaterial` row backgrounds; `Sources/Features/Connect/SignInView.swift` does the same for public profiles.
    - Recommended fix: Prefer default Form rows with `Label`, `LabeledContent`, or native `Button` styling; if cards are needed, move them outside Form and validate focus.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: watchOS transport controls use small plain icon buttons without explicit touch geometry.
    - Severity: Medium
    - Impact: VoiceOver labels exist, but physical touch targets and Digital Crown navigation comfort need validation.
    - Affected platforms: watchOS
    - Evidence: `Sources/Watch/WatchRemoteView.swift` uses compact icon-only controls with `.buttonStyle(.plain)`; `Documentation/AppStore/accessibility.md` calls for watchOS VoiceOver/Digital Crown validation.
    - Recommended fix: Give transport buttons explicit minimum frames or use larger native controls such as `ControlGroup`; validate on 41/45/49 mm watch sizes.
    - Confidence: Medium
    - Manual verification required: Yes
- Severity of each finding: Medium, Medium, Low, Medium.
- Recommended fixes: Add macOS Settings scene; make navigation scene-scoped or constrain multiwindow; simplify custom Form row styling; increase/validate watchOS transport control geometry.
- Assumptions made: Static source review was sufficient for reachability and UX structure. `project.yml` was treated as authoritative per `CLAUDE.md`.
- Manual verification items: macOS app menu Settings behavior; multiwindow route/search independence; tvOS focus on Connect/Sign In rows; watchOS transport targets and VoiceOver; Dynamic Type on hero/detail/audio screens; visionOS Cinema comfort.
- Errors, limitations, or incomplete areas: No runtime UI, simulator, or device testing was performed.

### Swift, SwiftUI, and Architecture Expert

- Status: Complete
- Files, targets, modules, or systems inspected: `AGENTS.md`, `CLAUDE.md`, `project.yml`, `Config/*.xcconfig`, entitlements, app/watch Info.plists, app/root/navigation wiring, providers, stores, player surfaces, item/detail views, books, downloads, CarPlay, watch app, representative tests.
- Summary of findings: The codebase mostly matches the stated architecture: SwiftUI lifecycle, Observation-based stores, XcodeGen source of truth, explicit platform targets, and generally guarded UIKit/AppKit/Watch/CarPlay APIs. The major architecture risk is account-switch state lifetime; lower-severity risks include platform code drifting into feature files, watchOS scheme test wiring, and main-actor provider isolation.
- Detailed findings:
  - Finding: Signed-in root can retain previous account stores after account switch.
    - Severity: High
    - Impact: Switching stored users can leave `HomeStore`, visible libraries, downloads/up-next loads, and child feature stores bound to the old `SessionStore`, creating stale UI and possible cross-account/server data exposure.
    - Affected platforms: iOS, iPadOS, tvOS, macOS, visionOS
    - Evidence: `AppModel.switchToStoredUser` replaces `currentSession`; `RootView` injects the new session without keying the signed-in subtree; `TabRootView`, `VisionSidebarRootView`, and `SplitRootView` keep `@State private var home` and load only when `home == nil`; `SettingsView` exposes `Switch`.
    - Recommended fix: Give the signed-in root a stable session identity, such as `.id(SessionCredential(user: session.user).account)` on `RootContainer`, or reset/reload stores via `.task(id: sessionIdentity)` / `.onChange`. Also key downloads/up-next loads by session in detail/settings tasks.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Platform-specific implementation has drifted outside the intended `Platform/` boundary.
    - Severity: Medium
    - Impact: Compile-guarded platform divergence in feature files increases review/build risk and weakens the repo convention that features should read as ordinary SwiftUI.
    - Affected platforms: All app platforms
    - Evidence: `VideoPlayerView` owns tvOS UIKit, iOS UIKit, macOS AppKit representables and `#if` routing; `ItemDetailView` embeds platform layout constants.
    - Recommended fix: Move player surface representables into `Sources/Platform` and centralize platform layout metrics in `SharedUI/LayoutMetrics` or platform modifiers.
    - Confidence: High
    - Manual verification required: No for diagnosis; yes after refactor builds.
  - Finding: `Gus watchOS` scheme does not actually test watchOS code.
    - Severity: Low
    - Impact: The watchOS-named scheme builds `GusWatch` but tests iOS test bundles, which can mislead validation.
    - Affected platforms: watchOS validation
    - Evidence: `project.yml` scheme `Gus watchOS` builds `GusWatch` and tests `GusTests`/`GusUITests`; no watch test target is defined.
    - Recommended fix: Remove the scheme test action or add a watchOS test bundle and wire the scheme to it.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Provider abstraction is globally `@MainActor`, limiting future concurrency headroom.
    - Severity: Informational
    - Impact: Mapping and fan-out operations are actor-isolated to the UI actor, which may become avoidable main-actor work for larger libraries.
    - Affected platforms: All
    - Evidence: `MediaProviderSession` is `@MainActor`; `HomeStore` latest-section child tasks are explicitly `@MainActor`.
    - Recommended fix: Not urgent. When moving toward stricter concurrency, consider nonisolated or actor-backed provider sessions, with `@MainActor` only for stores/view state mutation.
    - Confidence: Medium
    - Manual verification required: Only if performance profiling shows jank.
- Severity of each finding: High, Medium, Low, Informational.
- Recommended fixes: Key signed-in root and session-scoped stores by account; move player/platform representables to `Sources/Platform`; fix or remove watchOS scheme test action; revisit provider actor isolation during future concurrency work.
- Assumptions made: `project.yml` is the active source of truth; generated `.xcodeproj` state was not trusted. Static review was acceptable.
- Manual verification items: Account-switch flow across two saved users; all-platform builds after platform-boundary refactor; watch scheme behavior after XcodeGen regeneration; cold-start deep links to dynamic library sections after home libraries load.
- Errors, limitations, or incomplete areas: No builds/tests/simulators were run. Runtime-only AVKit, CarPlay entitlement behavior, WatchConnectivity delivery, background downloads, and visionOS immersive playback remain unverified.

### Jellyfin Integration and Networking Expert

- Status: Complete
- Files, targets, modules, or systems inspected: `AGENTS.md`, `CLAUDE.md`, `project.yml`, `Resources/Info.plist`, `Config/*.entitlements`, `JellyfinClientFactory`, `AppModel`, `SessionStore`, `ServerDiscoveryStore`, `SignInStore`, `QuickConnectStore`, `JellyfinMediaProviderSession`, `JellyfinMediaItemMapper`, `ImageURLBuilder`, `StreamURLBuilder`, `PlaybackStore`, `AudioPlayerStore`, `HomeStore`, `LibraryStore`, `SearchStore`, `ItemDetailStore`, remote sessions/SyncPlay sockets, Top Shelf snapshot, watch resume/remote views, relevant tests.
- Summary of findings: No Critical or High findings. Jellyfin integration is well factored around `MediaProviderSession`, uses Keychain-scoped tokens, has explicit timeouts/retry policy for idempotent loads, and meaningful coverage for playback URL construction, media stream mapping, paging, session credentials, Quick Connect, discovery, and reporting. Main gaps are realistic-server/product completeness issues: revoked tokens are not centrally handled, book/audiobook progress does not feed current resume rails, long seasons are capped at 300 episodes, favorites are not modeled/exposed, and image URLs assume unauthenticated Jellyfin image access.
- Detailed findings:
  - Finding: Revoked or expired tokens strand users in the signed-in shell.
    - Severity: Medium
    - Impact: Launch restore creates `SessionStore` from Keychain without validation. Later 401/403 responses become per-screen failures while `AppModel.currentSession` remains set.
    - Affected platforms: iOS, iPadOS, tvOS, visionOS, macOS, watchOS companion session paths
    - Evidence: `AppModel.restoreSavedSession` restores directly from stored token; `GusError` maps 401/403 to `.unauthorized`; `HomeStore` renders failed state rather than clearing session.
    - Recommended fix: Add central unauthorized handling/session validation. On confirmed 401/403, clear active session and route to sign-in for that server/user while preserving server/user record where appropriate.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Continue/resume rails exclude books and audiobooks despite progress support.
    - Severity: Medium
    - Impact: Book/audiobook progress can sync to Jellyfin, but Home and Watch Resume use a provider method restricted to movies and episodes.
    - Affected platforms: All app platforms for Home, watchOS for `WatchResumeView`
    - Evidence: `JellyfinMediaProviderSession.resumeItems` sets `includeItemTypes: [.movie, .episode]`; `HomeStore` and `WatchResumeView` use that method; roadmap text claims book progress feeds Continue.
    - Recommended fix: Decide whether Continue includes `.book`/`.audioBook` or add separate Continue Reading/Listening rails. Add tests for requested item types and UI behavior.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Series episode lists are hard-capped at 300 with no paging.
    - Severity: Medium
    - Impact: Long-running shows or large single-season libraries can silently omit episodes after the first 300.
    - Affected platforms: iOS, iPadOS, tvOS, visionOS, macOS
    - Evidence: `ItemDetailStore` calls `episodes(..., limit: 300)`; provider uses start index `0`; `ItemDetailView` renders `store.episodes` without load-more.
    - Recommended fix: Make episode loading paginated like `LibraryStore`, preserving selected-season generation guards.
    - Confidence: High
    - Manual verification required: No for code gap; yes for long-season UX.
  - Finding: Jellyfin favorites are not modeled or surfaced.
    - Severity: Medium
    - Impact: Users cannot browse, filter, see, or toggle favorite state in Gus.
    - Affected platforms: All
    - Evidence: `MediaUserData` only stores playback ticks/percentage; mapper drops `UserItemDataDto.isFavorite`; tests explicitly assert no favorites filter.
    - Recommended fix: Add favorite fields/actions to provider-neutral user data, map Jellyfin favorite state, add favorite filters/actions, and persist via `Paths.updateItemUserData`.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Image loading assumes unauthenticated Jellyfin image endpoints.
    - Severity: Low
    - Impact: Locked-down reverse proxies or servers requiring authenticated image access can show missing posters/artwork.
    - Affected platforms: All, especially tvOS Top Shelf and watchOS
    - Evidence: `ImageURLBuilder` uses `client.url(with:)` without query API key; `TopShelfSnapshot` assumes unauthenticated image endpoints; playback URLs append tokens.
    - Recommended fix: Decide whether authenticated image URLs are acceptable for app-only surfaces; keep Top Shelf credential-free or cache/proxy sanitized artwork into the App Group. Add tests documenting intended contract.
    - Confidence: Medium
    - Manual verification required: Yes
- Severity of each finding: Medium, Medium, Medium, Medium, Low.
- Recommended fixes: Add central unauthorized/session invalidation; clarify and implement book/audiobook resume rails; paginate episodes; model favorites; document or improve image auth strategy.
- Assumptions made: Static review only; no live Jellyfin server. Roadmap text was treated as intent only where code implemented or contradicted it. Local resolved SDK behavior was assumed.
- Manual verification items: Revoked-token behavior; image loading behind reverse-proxy auth; book/audiobook resume visibility; long-series paging; direct-play/transcode negotiation against Jellyfin 10.10/10.11 with mixed codecs/subtitles/latency.
- Errors, limitations, or incomplete areas: No builds/tests/network calls. No live Jellyfin server behavior, signed-device behavior, or Top Shelf rendering.

### Media Playback Expert

- Status: Complete
- Files, targets, modules, or systems inspected: `StreamURLBuilder`, `PlaybackStore`, `PlaybackReporting`, `PlaybackMediaSelection`, `VideoPlayerView`, `NowPlayingController`, `PlayerPresentation`, `PlayerExternalMetadata`, `AudioPlayerStore`, `AudioPlayerView`, `WatchAudioPlayerView`, `WatchVideoPlayerView`, `RemoteSessionsStore`, `SessionsSocket`, `JellyfinMediaProviderSession`, `JellyfinMediaItemMapper`, `MediaModels`, `DownloadSourceResolver`, `OfflineDownloadStore`, `project.yml`, plists/entitlements, playback ADRs, roadmap, signing/screenshots docs, `StreamURLBuilderTests`, `PlaybackReportingTests`, `PlaybackMediaSelectionTests`.
- Summary of findings: The main AVKit-first video path is wired: Jellyfin PlaybackInfo, direct stream/HLS transcode choice, single `AVPlayer`, start/progress/stop reporting, resume, stream selection, next-up, PiP-capable surfaces, AirPlay where supported, and Now Playing integration. No Critical issues. Main risks are system media-control polish and side paths: Now Playing observer lifecycle leaks, audio resume reporting starts at the wrong position, audiobooks are tagged as video in Now Playing, queue next/previous commands are not exposed to system remote controls, and watchOS video bypasses shared reporting/system-control stack.
- Detailed findings:
  - Finding: Now Playing time observers accumulate across track/stream changes.
    - Severity: High
    - Impact: Repeated `NowPlayingController.start(...)` calls overwrite the only stored observer token without removing the previous observer, leaving duplicate updates and possible player/observer retention.
    - Affected platforms: iOS, iPadOS, tvOS, visionOS, macOS, watchOS, CarPlay audio
    - Evidence: `NowPlayingController.start` assigns `player` and overwrites `timeObserver`; `stop` removes only the latest token. `PlaybackStore` calls `nowPlaying.start` after stream rebuilds and `AudioPlayerStore` calls it for each track.
    - Recommended fix: In `NowPlayingController.start`, remove any existing observer from the previous player before assigning a new one, cancel artwork, and avoid strongly capturing `player` in the observer closure.
    - Confidence: High
    - Manual verification required: No, though Instruments/runtime confirmation is useful.
  - Finding: Audio resume reports playback start from zero instead of resumed position.
    - Severity: Medium
    - Impact: Audio/audiobook playback seeks to saved Jellyfin position, but immediate `PlaybackStart` may report zero until the next progress update.
    - Affected platforms: iOS, iPadOS, macOS, watchOS, CarPlay audio
    - Evidence: `AudioPlayerStore` seeks before `reportStart`, but `reportStart` derives ticks from `currentTime`, which is only updated by the periodic observer.
    - Recommended fix: After resume seek, set `currentTime` from resume seconds or `player.currentTime()` before `reportStart()` and Now Playing elapsed metadata.
    - Confidence: High
    - Manual verification required: No
  - Finding: Audiobooks are published to Now Playing as video.
    - Severity: Medium
    - Impact: Audiobooks route through the audio player but use video Now Playing metadata semantics.
    - Affected platforms: iOS, iPadOS, macOS, watchOS, CarPlay audio
    - Evidence: `MediaItem.isAudioPlayable` includes `.audioBook`, but `NowPlayingController` checks only `item.type == .audio` when setting `MPNowPlayingInfoPropertyMediaType`.
    - Recommended fix: Use `item.isAudioPlayable` or explicitly include `.audioBook`.
    - Confidence: High
    - Manual verification required: No
  - Finding: System remote commands do not expose queue next/previous.
    - Severity: Medium
    - Impact: Lock screen, Control Center, headset, and CarPlay next/previous commands cannot advance Gus audio queues.
    - Affected platforms: iOS, iPadOS, macOS, watchOS, CarPlay audio
    - Evidence: `AudioPlayerStore.next()` and `previous()` exist, but `NowPlayingController.configureRemoteCommands` wires only play/pause/toggle/skip/scrub; no `nextTrackCommand` or `previousTrackCommand` references were found.
    - Recommended fix: Give `NowPlayingController.start` optional async callbacks for next/previous, enable those commands for audio queues, and disable/map appropriately for video next-up.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: watchOS video playback bypasses shared reporting and system media integration.
    - Severity: Medium
    - Impact: On-watch video can fail to update Jellyfin resume/watched state and may not behave like the main playback stack.
    - Affected platforms: watchOS
    - Evidence: `WatchVideoPlayerView.prepare()` resolves playback and starts `AVPlayer`, but does not use shared `PlaybackStore` start/progress/stopped reporting, Now Playing, or audio-session setup.
    - Recommended fix: Reuse a watch-safe playback/reporting wrapper or add minimal watch video reporting, audio session setup, and teardown reporting.
    - Confidence: High
    - Manual verification required: Yes
- Severity of each finding: High, Medium, Medium, Medium, Medium.
- Recommended fixes: Fix `NowPlayingController.start` lifecycle; update audio resume timing; tag audiobooks as audio; wire next/previous remote commands; add or remove/limit watchOS video reporting path.
- Assumptions made: Static review only; Jellyfin SDK call shapes are accepted as generated API contracts.
- Manual verification items: PiP on iPhone/iPad/macOS; AirPlay/external routes; lock screen/Control Center metadata/artwork/scrub/commands; tvOS transport menus; visionOS 3D paths; CarPlay after entitlement is granted and wired; watchOS remote/audio/offline/video progress behavior.
- Errors, limitations, or incomplete areas: No build, tests, simulator, device, CarPlay, AirPlay, PiP, or Jellyfin runtime session was executed.

### Security, Privacy, and Child Safety Expert

- Status: Complete
- Files, targets, modules, or systems inspected: `KeychainStore`, `SessionCredential`, `AppModel`, `ServerStore`, settings account switching, watch credential handoff, downloads, book cache/progress, image `URLCache`, Up Next, navigation preferences, diagnostic summaries, Spotlight, Handoff, Siri/App Intents, Top Shelf, Now Playing, App Groups, WatchConnectivity, `Info.plist`, entitlements, `PrivacyInfo.xcprivacy`, `project.yml`, `Package.resolved`, App Store privacy docs.
- Summary of findings: No production hardcoded secrets were found. Tokens are generally stored correctly in Keychain under provider/server/user-qualified accounts, persisted server/user JSON does not include tokens, ATS allows local-network HTTP while keeping arbitrary loads disabled, macOS sandbox is enabled with outbound networking only, and no third-party analytics SDK is present. Primary risks are child-safety and privacy retention gaps where system indexes/snapshots and local caches can outlive account switches, sign-out, or server-side restriction changes.
- Detailed findings:
  - Finding: Spotlight can expose adult titles/descriptions after switching to a child account.
    - Severity: High
    - Impact: A child using device/system search can see adult-account titles, overviews, genres, artists, or series names even though tapping the result is refused.
    - Affected platforms: iOS, iPadOS, macOS, likely visionOS where CoreSpotlight is available
    - Evidence: `SpotlightIndexer.index` donates title, description, and keywords; `HomeStore` and `LibraryStore` index visible items; `switchToStoredUser` restores the new session without deindexing old domains; deindexing only happens on sign-out.
    - Recommended fix: On account switch, delete the outgoing account's Spotlight domain before installing the new session, or disable Spotlight indexing unless explicitly enabled. Consider deleting all Gus Spotlight domains on sign-out and restriction changes.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: tvOS Top Shelf snapshot can show stale adult Continue Watching content.
    - Severity: High
    - Impact: Adult Continue Watching/Next Up titles, artwork URLs, and progress can remain visible on the Apple TV home screen after switching to a child user until a child-scoped Home load overwrites the snapshot.
    - Affected platforms: tvOS
    - Evidence: `TopShelfSnapshot` stores title, image URL, and progress; `HomeStore` writes it; `TopShelfContentProvider` renders it; `AppModel.signOutCurrentUser` clears it only on tvOS sign-out, not user switch.
    - Recommended fix: Clear Top Shelf before account switch and when content restrictions change; write active account scope into the App Group and render only if it matches; write an empty snapshot on Home load failure.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Offline downloaded media survives sign-out and server-side restriction changes.
    - Severity: High
    - Impact: If content is removed or restricted server-side after it was downloaded, the local record/file remains playable for the same server/user without server revalidation.
    - Affected platforms: iOS, iPadOS, macOS, visionOS, watchOS audio/download paths where enabled
    - Evidence: Download records persist full `MediaItem`, file path, server ID, and user ID; playback uses local files when a scoped record exists; sign-out removes token/user/Spotlight/Top Shelf but not downloads.
    - Recommended fix: Add account-scoped delete-local-media-on-sign-out cleanup and a user-facing control; revalidate downloaded records before playback after parental/access changes where feasible; purge on 401/403/404 or missing item.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Book file cache and exact reading progress are not scoped by server/user.
    - Severity: Medium
    - Impact: Adult books can remain in `Caches/Books/<itemID>` and exact reader locators in `book-progress.json`; another user or server with the same item ID can reuse the file/progress. Filenames include book titles.
    - Affected platforms: iOS/iPadOS Readium and non-tvOS share flow
    - Evidence: `BookFileProvider` cache lookup uses only `item.id`; destination path is `Caches/Books/<item id>/<title>.<ext>`; `BookProgressStore` keys locator JSON only by item ID.
    - Recommended fix: Include provider/server/user scope in book cache directories and progress keys; purge scoped book cache/progress on sign-out or account data deletion.
    - Confidence: High
    - Manual verification required: Useful on device, not required for code path.
  - Finding: WatchConnectivity credential snapshot is not cleared on sign-out.
    - Severity: Medium
    - Impact: The phone's last application context can retain server/user/token payload; a watch activating later can adopt and persist a session after phone sign-out.
    - Affected platforms: iOS and watchOS
    - Evidence: iPhone publishes `token` via `updateApplicationContext`; watch adopts `receivedApplicationContext` on activation; `AppModel.signOutCurrentUser` has no watch-clear call.
    - Recommended fix: Add a signed-out/clear context message and have the watch delete the matching token/current session when received.
    - Confidence: Medium
    - Manual verification required: Yes
  - Finding: Sensitive user and media names are logged as public.
    - Severity: Medium
    - Impact: Unified logs can expose Jellyfin usernames and private media titles to diagnostic collectors.
    - Affected platforms: All
    - Evidence: User names are logged public on restore/adopt/sign-in; playback logs item name public; download failures log record IDs containing server/user/item IDs.
    - Recommended fix: Mark names/titles/compound IDs `.private`, remove them, or log non-reversible short hashes.
    - Confidence: High
    - Manual verification required: No
  - Finding: On-device privacy docs understate non-download caches/system surfaces.
    - Severity: Low
    - Impact: Privacy policy discloses downloads and watch token transfer but not Spotlight indexing, Top Shelf snapshots, shared image cache, book cache, or book progress.
    - Affected platforms: App Store/support documentation
    - Evidence: App Store privacy docs list on-device storage and no developer collection but omit these local/system surfaces.
    - Recommended fix: Add a local caches/system surfaces section and document user controls/cleanup behavior once implemented.
    - Confidence: Medium
    - Manual verification required: No
- Severity of each finding: High, High, High, Medium, Medium, Medium, Low.
- Recommended fixes: Clear/deindex system surfaces on account switch and restriction changes; scope/purge local downloads/book cache by account; add watch credential clear flow; make logs private; update privacy documentation.
- Assumptions made: Jellyfin server-side parental controls and library permissions are authoritative for restricted users. `MediaItem.officialRating` can be stale in local records. App Store privacy collection means data sent to the developer, not local data or data sent to the user's Jellyfin server.
- Manual verification items: Spotlight after adult browse/child switch/sign-out; tvOS Top Shelf immediately after adult-to-child switch, Home load failure, and content-limit changes; downloaded media after server access revocation or parental changes; watch sign-out propagation; unified logs after fixes; built entitlements and App Group registration on real tvOS/macOS signing.
- Errors, limitations, or incomplete areas: Static review only; no builds, simulator/device runs, packet capture, or live Jellyfin server behavior. No live CVE/advisory research for package versions.

### Performance, Caching, and Responsiveness Expert

- Status: Complete (orchestrator-authored after the delegated performance/caching reviewer did not return)
- Files, targets, modules, or systems inspected: `CLAUDE.md`, `project.yml`, `Sources/App/GusApp.swift`, `JellyfinClientFactory`, `NetworkRetryPolicy`, `DiagnosticsHub`, `MetricKitCollector`, `LibraryStore`, `SearchStore`, `HomeStore`, `Paging`, `LibraryGridView`, `SearchResultsView`, `RootContainer`, `OfflineDownloadStore`, `DownloadSessionCoordinator`, `BookFileProvider`, `BookProgressStore`, `NowPlayingController`, `AudioPlayerStore`, `QuickConnectStore`, `RemoteSessionsStore`, `AsyncPoster`, `PosterCard`, `PerformanceBaselineTests`, `Documentation/AppStore/performance-baselines.md`, and static searches for main-thread file I/O, task lifetimes, grids/lists, and cache usage.
- Summary of findings: Gus has several good performance foundations: system `AsyncImage` with a tuned 64 MB memory / 512 MB disk `URLCache`, fixed poster image widths, paginated library/search loads, `LazyVGrid`/`List` rendering, search debounce, foreground retry policy, background download sessions, MetricKit/signpost instrumentation, and measurement docs. The main performance/caching risks are unbounded or per-account-only storage growth, synchronous file I/O on `@MainActor` paths, globally retained session/root stores after account switch, main-actor-heavy provider/store work, measurement baselines that are not enforced by CI, and the Now Playing time-observer leak already found by the media reviewer.
- Detailed findings:
  - Finding: Download, image, and book caches do not share a global storage budget or account cleanup policy.
    - Severity: Medium
    - Impact: Storage can grow beyond user expectations across multiple servers/users, because downloads enforce a 20 GB soft cap per active server/user while the 512 MB image cache and book cache are separate. Sign-out/account switch does not purge local downloads, image cache, or book cache.
    - Affected platforms: iOS, iPadOS, macOS, visionOS, watchOS where downloads/book paths apply; tvOS for image/Top Shelf cache behavior
    - Evidence: `OfflineDownloadStore.ensureDiskBudget` checks `totalByteCount(serverID:userID)` only; `JellyfinClientFactory.urlCache` creates a 512 MB disk image cache; `BookFileProvider` writes under `Caches/Books/<item id>` without size cap or server/user scope; `AppModel.signOutCurrentUser` does not clear these caches.
    - Recommended fix: Define an app-wide storage budget and per-account deletion policy. Include downloads, image cache, book cache/progress, and Top Shelf/Spotlight system data in account cleanup. Add Settings controls for clear cached images/books/downloads and delete-local-data-on-sign-out.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Book cache and exact reading progress perform synchronous file I/O on `@MainActor` and are unbounded.
    - Severity: Medium
    - Impact: Opening/sharing books or loading reader progress can block the UI, especially with many cached files or a slow disk; the cache can also grow without app-level eviction.
    - Affected platforms: iOS/iPadOS Readium flow; non-tvOS share flow
    - Evidence: `BookFileProvider` is `@MainActor` and calls `contentsOfDirectory`, `fileExists`, `moveItem`, and `URLSession.shared.download` path handling; `BookProgressStore` is `@MainActor`, loads `book-progress.json` with `Data(contentsOf:)`, and writes JSON from a main-actor task.
    - Recommended fix: Move cache path lookup, directory enumeration, JSON load/save, and file moves into a small nonisolated/actor-backed file service. Add cache-size accounting, eviction, and scoped cleanup.
    - Confidence: High
    - Manual verification required: No for code path; yes for device responsiveness.
  - Finding: Signed-in root stores are retained across session changes, causing stale state and wasted work.
    - Severity: Medium
    - Impact: `HomeStore`, navigation preferences, dynamic library sections, and possibly loaded media grids can remain attached to an old session after account switch, retaining data in memory and continuing to influence the rendered shell.
    - Affected platforms: iOS, iPadOS, tvOS, macOS, visionOS
    - Evidence: `RootContainer` variants keep `@State private var home` and only create/load it when `home == nil`; `AppModel.switchToStoredUser` replaces `currentSession` without keying the signed-in subtree. This overlaps the architecture/privacy finding but has direct memory/cache implications.
    - Recommended fix: Key the signed-in root by `SessionCredential(user: session.user).account` or reset stores via `.task(id: sessionIdentity)` / `.onChange`, and explicitly cancel or discard session-bound stores.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Provider and home-section fan-out work are main-actor-heavy.
    - Severity: Medium
    - Impact: Large library metadata mapping/filtering and latest-section fan-out may contend with UI updates as libraries grow. Network awaits do not block the main actor, but provider methods and task-group closures are main-actor isolated.
    - Affected platforms: All
    - Evidence: `MediaProviderSession` and `JellyfinMediaProviderSession` are `@MainActor`; `HomeStore.loadLatestSections` uses a `withThrowingTaskGroup` whose child closures are explicitly `@MainActor`; `LibraryStore` and `SearchStore` map/filter assigned pages on the main actor.
    - Recommended fix: Keep stores `@MainActor`, but move provider DTO mapping, content-rating filtering for page batches, and latest-section query composition to nonisolated helpers or a provider actor. Validate with Instruments on large libraries before broad refactors.
    - Confidence: Medium
    - Manual verification required: Yes
  - Finding: Performance baselines and MetricKit diagnostics are documented but not enforced.
    - Severity: Low
    - Impact: The team can collect mapper/search/playback/launch metrics, but regressions will not fail CI by default.
    - Affected platforms: All validation workflows
    - Evidence: `PerformanceBaselineTests` uses XCTest `measure` blocks; `Documentation/AppStore/performance-baselines.md` records thresholds; no tracked baseline files or explicit assertions were found. `DiagnosticsHub` and `MetricKitCollector` collect useful metrics but review is manual.
    - Recommended fix: Commit Xcode performance baselines or add explicit budget assertions for stable pure paths. For runtime flows, add a release checklist gate that compares MetricKit/signpost snapshots against recorded thresholds.
    - Confidence: High
    - Manual verification required: No for static gap; yes for baseline values.
  - Finding: Now Playing time observers can accumulate and retain players.
    - Severity: High
    - Impact: Repeated stream/track starts can leave old periodic observers attached, causing duplicate updates and memory/CPU overhead during playback.
    - Affected platforms: iOS, iPadOS, tvOS, macOS, visionOS, watchOS, CarPlay audio
    - Evidence: `NowPlayingController.start` overwrites `timeObserver` without first removing any existing observer from the previous/current player; this duplicates the media-playback finding but is also a performance/memory leak.
    - Recommended fix: Remove any existing observer and cancel artwork before replacing `player`; avoid strongly capturing the player in the observer closure.
    - Confidence: High
    - Manual verification required: Useful with Instruments.
  - Finding: Search and library list implementation has good paging foundations but needs runtime scale validation.
    - Severity: Informational
    - Impact: Static review shows appropriate `LazyVGrid`, `List`, page sizes, prefetch thresholds, and a 300 ms search debounce, but smoothness under very large libraries, slow servers, and tvOS/watchOS focus cannot be proven statically.
    - Affected platforms: All browsing/search platforms
    - Evidence: `LibraryRequest.pageSize = 60`, `SearchStore` limit defaults to 50, `Paging` provides thresholded load-more, `LibraryGridView` and `SearchResultsView` use `LazyVGrid`, and `SearchRootView.searchDebounce` sleeps 300 ms and cancels on new keystrokes.
    - Recommended fix: Keep the current pattern, then validate with a large Jellyfin library and Instruments. Add scroll hitch, memory, image cache hit-rate, and network-volume measurements to the release checklist.
    - Confidence: High
    - Manual verification required: Yes
- Severity of each finding: Medium, Medium, Medium, Medium, Low, High, Informational.
- Recommended fixes: Define global/account-scoped cache budgets and cleanup; move book cache/progress file I/O off the main actor; key/reset signed-in stores by session; de-main-actor heavy provider mapping after profiling; enforce or operationalize performance baselines; fix Now Playing observer lifecycle; validate large-library scrolling/search with Instruments and MetricKit.
- Assumptions made: Static source review was sufficient to identify cache lifetime, file I/O, and instrumentation gaps. Runtime smoothness, memory footprint, battery impact, and server/network behavior still require device/server profiling.
- Manual verification items: Large-library scroll and search on iPhone/iPad/tvOS/macOS/visionOS; watchOS battery impact for remote/audio/download flows; image cache hit rate and disk growth; multi-account storage growth and clear-cache controls; book open/share on slow devices; playback memory/observer count with repeated track/stream changes; MetricKit/signpost collection from TestFlight/device builds.
- Errors, limitations, or incomplete areas: The delegated performance/caching sub-agent did not return after repeated waits and was not used for this checkpoint. No builds, tests, Instruments traces, devices, or live Jellyfin servers were run. Findings are static and orchestrator-authored.

### Platform, Build, Dependency, and App Store Expert

- Status: Complete
- Files, targets, modules, or systems inspected: `AGENTS.md`, `CLAUDE.md`, `project.yml`, `Config/*.xcconfig`, entitlements, Info.plists, `Resources/PrivacyInfo.xcprivacy`, asset catalogs, package resolution, CI/Xcode Cloud scripts, App Store docs, and platform-sensitive source for CarPlay, Declared Age Range, Top Shelf, watchOS, downloads, Keychain, Readium, local discovery, MetricKit, and Now Playing.
- Summary of findings: No Critical static blocker was found. Main readiness risks are dependency reproducibility, entitlement-gated features being present/marketed before grants are wired, the watchOS scheme test-action mismatch, and missing third-party license notice packaging. Plists, entitlements, privacy manifest, string catalog, and asset JSON validated syntactically in static review.
- Detailed findings:
  - Finding: Dependency graph is not reproducibly pinned.
    - Severity: High
    - Impact: CI, Xcode Cloud, and App Store archives can resolve newer compatible package versions than the reviewed build, changing transitive code, licenses, privacy manifests, or platform compatibility without a source diff.
    - Affected platforms: All; Readium impact currently iOS/iPadOS only.
    - Evidence: `project.yml` uses `from` constraints for JellyfinSDK and Readium. `.gitignore` ignores the generated project, including the only observed `Package.resolved`; `git ls-files` showed no tracked `Package.resolved`.
    - Recommended fix: Track a package lock strategy. Either unignore and commit the generated workspace `Package.resolved`, or pin direct dependencies exactly and add CI that fails when package resolution drifts.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: CarPlay is declared and marketed while the entitlement is pending/unwired.
    - Severity: High
    - Impact: App Review/metadata risk: listing/docs promise CarPlay, `Info.plist` declares a CarPlay scene, but archives do not carry `com.apple.developer.carplay-audio`.
    - Affected platforms: iOS/iPadOS, CarPlay
    - Evidence: `Resources/Info.plist` declares `CPTemplateApplicationSceneSessionRoleApplication`; `Config/Gus-CarPlay.entitlements` says it is not wired; `Documentation/AppStore/app-store-metadata.md` says CarPlay brings music/audiobooks to the car.
    - Recommended fix: Before App Store/TestFlight metadata uses CarPlay, obtain the grant, wire the entitlement, regenerate, archive, and test in simulator/hardware. Until then, remove CarPlay claims from metadata and consider omitting the scene declaration from release builds.
    - Confidence: High for metadata mismatch; Medium for archive-validation behavior
    - Manual verification required: Yes
  - Finding: Declared Age Range feature is visible on OS 26 but entitlement is absent.
    - Severity: Medium
    - Impact: On iOS/macOS 26, Settings can show a “Set from Age Range” action that is expected to fail gracefully until the entitlement is wired; that is risky for release if described as supported.
    - Affected platforms: iOS/iPadOS 26+, macOS 26+
    - Evidence: `AgeRangeDefaults.swift` compiles the feature when `DeclaredAgeRange` is available; `Documentation/AppStore/signing-capabilities.md` says entitlement wiring is pending.
    - Recommended fix: Wire `com.apple.developer.declared-age-range` before release or hide/disable the button behind a release capability flag until provisioning is complete.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Deployment targets do not match an OS 26-minimum product requirement.
    - Severity: Medium
    - Impact: If Gus is intended to require Apple OS 26 platform versions, the generated project currently allows older OS installs. If lower deployment is intentional, the OS 26 requirement should be restated as an SDK/language/API posture and all OS 26 APIs must remain availability-gated.
    - Affected platforms: iOS, iPadOS, tvOS, watchOS, visionOS, macOS
    - Evidence: `project.yml` sets `xcodeVersion: "26.5"` but deployment targets are `iOS: "18.0"`, `tvOS: "18.0"`, `visionOS: "2.0"`, `macOS: "15.0"`, and `watchOS: "11.0"`.
    - Recommended fix: Decide the shipping policy. Either raise deployment targets to the OS 26 family or update release docs/tests to state that Gus builds with Xcode 26 while supporting older deployment targets through availability gates.
    - Confidence: High
    - Manual verification required: No
  - Finding: watchOS scheme has incompatible test targets.
    - Severity: Medium
    - Impact: `xcodebuild test -scheme "Gus watchOS"` is likely unreliable because the watch scheme's Test action points at iOS test bundles, even though CI only builds watchOS.
    - Affected platforms: watchOS, CI/local scheme reliability
    - Evidence: `project.yml` defines `Gus watchOS` tests as `GusTests` and `GusUITests`; the generated ignored scheme confirms those same testables.
    - Recommended fix: Remove the Test action from `Gus watchOS` until watch tests exist, or add a watch-specific test target and wire that instead.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Third-party license notices are not packaged as a release artifact.
    - Severity: Medium
    - Impact: The resolved graph includes MPL/BSD/MIT/Apache-style dependencies, but there is no bundled acknowledgements/third-party notices page or resource.
    - Affected platforms: All, especially iOS where Readium transitives are linked
    - Evidence: local `Package.resolved` resolves Jellyfin, Readium, SwiftNIO, CryptoSwift, SwiftSoup, GCDWebServer, SQLite.swift, etc.; `LICENSE.md` covers Gus itself, not third-party acknowledgements.
    - Recommended fix: Generate and ship a Third-Party Notices/Acknowledgements artifact, expose it in Settings/About, and include dependency license texts in the app bundle or support docs. Get legal review for MPL obligations around `jellyfin-sdk-swift`.
    - Confidence: Medium
    - Manual verification required: Yes
  - Finding: CI config validation does not cover all platform metadata.
    - Severity: Low
    - Impact: Future plist/entitlement mistakes in watch Info.plist, TopShelf entitlement, or CarPlay entitlement file could bypass the docs/config CI job.
    - Affected platforms: watchOS, tvOS extension, iOS CarPlay
    - Evidence: `.github/workflows/ci.yml` validates only main Info, privacy manifest, TopShelf Info, and two entitlement files. Static pass validated the omitted files successfully.
    - Recommended fix: Add `Resources/Watch/Info.plist`, `Config/GusTopShelf.entitlements`, and `Config/Gus-CarPlay.entitlements` to CI plist validation.
    - Confidence: High
    - Manual verification required: No beyond CI run
- Severity of each finding: High, High, Medium, Medium, Medium, Medium, Low.
- Recommended fixes: Track package resolution; gate or finish entitlement-backed CarPlay and Declared Age Range features; decide and encode the OS 26 deployment policy; fix the watch scheme test action; package third-party notices; broaden CI plist/entitlement validation.
- Assumptions made: `project.yml` is source of truth. Ignored generated project/build artifacts were treated as local context only. No files were edited.
- Manual verification items: Fresh XcodeGen plus build/test matrix on installed Xcode 26.5; signed Release archives in Xcode Cloud; App Group, tvOS user management, CarPlay, Declared Age Range, watchOS audio/offline behavior, screenshots, TestFlight, and App Store Connect privacy/metadata.
- Errors, limitations, or incomplete areas: No runtime builds/tests were run. No live App Store Connect, Developer Portal, Xcode Cloud, vulnerability database, or current package-maintenance lookup was performed.

### Accessibility and Localization Expert

- Status: Complete
- Files, targets, modules, or systems inspected: `AGENTS.md`, `CLAUDE.md`, `project.yml`, `Config/Shared.xcconfig`, `Resources/Localizable.xcstrings`, app/watch/Top Shelf Info.plists, `Gus`, `GusWatch`, `GusTopShelf`, Connect, Home, Search, Item, Player, Music, Books, Photos, Live TV, Settings, Downloads, Watch, CarPlay, platform modifiers/navigation, playback stream selection, representative tests, App Store accessibility docs, and the existing review log.
- Summary of findings: No Critical accessibility blockers were found statically. Gus mostly uses native SwiftUI/AVKit controls, labels many icon controls, groups poster rows for VoiceOver, respects Reduce Motion in image/slideshow paths, and exposes subtitle/audio menus. Main gaps are localization readiness, English-only formatting helpers, fixed-size large-text clipping risk, incomplete progress semantics for VoiceOver, and runtime verification for captions, focus, Switch Control, keyboard, contrast, and platform assistive technologies.
- Detailed findings:
  - Finding: Info.plist user-facing strings are outside the localization system.
    - Severity: Medium
    - Impact: System permission prompts and extension display names remain English-only even if the app is localized.
    - Affected platforms: iOS, iPadOS, visionOS, tvOS Top Shelf; app/watch display names if localized branding is desired.
    - Evidence: `Resources/Info.plist` hardcodes `NSLocalNetworkUsageDescription`; `Sources/TopShelf/Info.plist` hardcodes `CFBundleDisplayName`; only `Resources/Localizable.xcstrings` was found, with no `InfoPlist.xcstrings` or `InfoPlist.strings`.
    - Recommended fix: Add an InfoPlist string catalog or localized `InfoPlist.strings` resources for each relevant target. Localize `NSLocalNetworkUsageDescription` and extension/app display strings where product policy allows.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Localizable string catalog is incomplete for current user-facing code.
    - Severity: Medium
    - Impact: Many UI labels, accessibility labels/hints, App Intents, CarPlay strings, watchOS controls, Books, Settings, Live TV, and SyncPlay strings have no current catalog entries.
    - Affected platforms: All, especially watchOS, CarPlay/iOS, Siri/Shortcuts, Books, Settings, Live TV.
    - Evidence: `Sources/App/GusAppIntents.swift` uses `Play Media`; `Sources/CarPlay/CarPlaySceneDelegate.swift` uses CarPlay strings; `Sources/Watch/WatchRemoteView.swift` has transport labels; `Sources/Features/Books/BookActions.swift` has accessibility hints that were not present in the catalog. `jq empty Resources/Localizable.xcstrings` passed.
    - Recommended fix: Run Xcode string extraction/export, then add or review catalog entries with translator comments for all source strings, including accessibility-only labels and hints. Add a lightweight localization coverage check if feasible.
    - Confidence: High
    - Manual verification required: Partly
  - Finding: Runtime, episode, rating, and fallback labels use English-only formatting.
    - Severity: Medium
    - Impact: Visible text and VoiceOver labels can remain English-centric, non-pluralized, or locale-insensitive in translated builds.
    - Affected platforms: All
    - Evidence: `MediaItem+Display.swift` builds strings such as `S1·E3`, `1h 47m`, and uses `String(format:)`; `PlaybackReporting.swift` falls back to `Audio 1` / `Subtitle 2`; `DownloadsView.swift` formats a count as a bare string.
    - Recommended fix: Use `DateComponentsFormatter`, `MeasurementFormatStyle`, `Number.FormatStyle`, and String Catalog plural/device-specific format keys. Keep server-provided metadata raw, but localize app-created fallback labels and accessibility summaries.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Fixed-size summary cards and visionOS environment picker risk clipping under Dynamic Type and text expansion.
    - Severity: Medium
    - Impact: Larger Text, accessibility text sizes, and translated labels can truncate or overlap in item detail summaries and the visionOS environment picker.
    - Affected platforms: iOS, iPadOS, macOS, tvOS, visionOS
    - Evidence: `LayoutMetrics.swift` fixes about cards at `260x150`; `ItemDetailView.swift` applies that fixed height; `CinemaModel.swift` uses `lineLimit(1)` inside a fixed-width picker; tests assert fixed sizes.
    - Recommended fix: Let cards grow vertically or use minimum dimensions, remove one-line limits for localized labels where possible, and update layout tests to assert minimum/adaptive behavior rather than fixed heights.
    - Confidence: Medium
    - Manual verification required: Yes
  - Finding: Some progress indicators lack explicit VoiceOver context and values.
    - Severity: Medium
    - Impact: VoiceOver and Switch Control users may hear ambiguous progress without knowing whether it is playback, remote playback, or download progress.
    - Affected platforms: watchOS; downloads on app platforms
    - Evidence: `WatchRemoteView.swift` and `WatchAudioPlayerView.swift` have playback `ProgressView`s without explicit context; `DownloadsView.swift` labels progress but does not set an explicit percent/value.
    - Recommended fix: Add localized `accessibilityLabel` and `accessibilityValue` for playback position and download progress, using localized duration/percent formatting.
    - Confidence: Medium
    - Manual verification required: Yes
  - Finding: Decorative item-detail hero imagery may add VoiceOver noise.
    - Severity: Low
    - Impact: Decorative backdrop/placeholder imagery can become a low-value focus stop before meaningful title/actions.
    - Affected platforms: iOS, iPadOS, tvOS, macOS, visionOS
    - Evidence: `ItemDetailView.swift` renders the backdrop with `AsyncPoster` and uses `.accessibilityElement(children: .contain)` without hiding decorative imagery.
    - Recommended fix: Mark decorative hero artwork/gradients `accessibilityHidden(true)` or expose a single semantic hero group with title, metadata, and actions in intended order.
    - Confidence: Medium
    - Manual verification required: Yes
  - Finding: Caption and alternate-audio support is statically wired, but runtime verification remains required.
    - Severity: Informational
    - Impact: Caption rendering, SDH/CC behavior, bitmap subtitle burn-in, audio-description naming, and platform transport menu behavior depend on Jellyfin metadata, server transcode decisions, and AVKit runtime.
    - Affected platforms: iOS, iPadOS, tvOS, macOS, visionOS; watchOS video if kept
    - Evidence: `StreamURLBuilder.swift` defines subtitle delivery profiles and enables subtitles in HLS manifests; `VideoPlayerView.swift` exposes subtitle menus; `Documentation/AppStore/accessibility.md` still has caption testing unchecked.
    - Recommended fix: Validate with media containing VTT/SRT, embedded CC/TTML, bitmap subtitles, multiple audio languages, and audio-description tracks on each playback platform.
    - Confidence: High
    - Manual verification required: Yes
- Severity of each finding: Medium, Medium, Medium, Medium, Medium, Low, Informational.
- Recommended fixes: Add localized Info.plist resources; complete string catalog coverage; use locale-aware formatters/pluralization; make fixed layout surfaces adaptive; add explicit accessibility labels/values for progress; hide decorative imagery; runtime-test subtitles, captions, focus, keyboard, Switch Control, VoiceOver, contrast, Reduce Motion, RTL, and pseudolocalization.
- Assumptions made: `project.yml` is source of truth. Server-provided titles/people/genres/media metadata should generally be displayed as supplied; app-created fallback text should be localized. No runtime accessibility state was inferred beyond static SwiftUI/AVKit code.
- Manual verification items: VoiceOver order on Connect, Home, Search, Item Detail, Player, Downloads, Books, Live TV, Settings, and Watch screens; largest Dynamic Type and text expansion; pseudolocalization and RTL; Full Keyboard Access on macOS/iPadOS; Switch Control on iOS/watchOS; tvOS Focus Engine and VoiceOver; visionOS gaze/focus and immersive comfort; contrast; Reduce Motion; caption/audio-description selection with real Jellyfin media; App Intents/Shortcuts, CarPlay, and local network prompt localization.
- Errors, limitations, or incomplete areas: No builds, tests, simulators, devices, VoiceOver sessions, CarPlay entitlement run, or live Jellyfin playback were executed. `Resources/Localizable.xcstrings` passed `jq empty`.

### Testing, Dead Code, and Maintainability Expert

- Status: Complete
- Files, targets, modules, or systems inspected: `AGENTS.md`, `CLAUDE.md`, `project.yml`, `.github/workflows/ci.yml`, existing review log, unit/UI test targets in `project.yml`, `Tests/APlayaNamedGusTests/*`, `Tests/APlayaNamedGusUITests/GusLaunchUITests.swift`, `Sources/App`, `Sources/Stores`, `Sources/Services`, `Sources/Providers`, `Sources/Features/Books`, `Sources/Features/Settings`, `Sources/Features/Player`, `Sources/Watch`, `Sources/TopShelf`, `Sources/CarPlay`, and `Resources`.
- Summary of findings: The repo has meaningful unit coverage for pure service/store areas including content-rating gates, session restore, URL building, downloads, provider mapping, media rails, and serialization. Main risks are test isolation, watch/platform test gaps, shallow UI smoke coverage, missing side-effect tests for child-safety/privacy boundaries, and untested book cache/progress behavior. Static dead-code review found no definitely unused production Swift type or asset; low-reference symbols are expected lifecycle/reflection entry points. The clearest obsolete artifact is the app-icon generator script, which conflicts with current project guidance. Large mixed-responsibility files make future coverage harder.
- Detailed findings:
  - Finding: Shared mock `URLProtocol` state can make `LibraryStoreTests` nondeterministic.
    - Severity: High
    - Impact: Parallel test execution can interleave requests, recorded requests, and queued responses between tests, causing flaky failures or false passes.
    - Affected platforms: All unit-test schemes using `Tests/APlayaNamedGusTests`
    - Evidence: `LibraryStoreTests.swift` uses a single static `LibraryItemsURLProtocol.state`, static `recordedRequests`, and `configure` reset path. The response queue is global for the protocol class.
    - Recommended fix: Give each test its own mock state, for example via a unique request header/state-id pattern. A short-term mitigation is serializing the suite; per-test state is the maintainable fix.
    - Confidence: High
    - Manual verification required: No for diagnosis; run repeated parallel tests after the fix.
  - Finding: watchOS is built but has no real watchOS test target.
    - Severity: Medium
    - Impact: Watch credential handoff, remote controls, playback state, offline availability, and UI lifecycle can regress while CI remains green.
    - Affected platforms: watchOS primarily; shared watch services secondarily
    - Evidence: `project.yml` defines `GusWatch` but no `GusWatchTests`; `Gus watchOS` scheme test section references `GusTests` and `GusUITests`; CI has a watchOS build lane but no watchOS test lane.
    - Recommended fix: Add `GusWatchTests` for watch-safe pure logic and fixture-backed session/transport behavior, then wire the watch scheme and CI. If deferred, remove the misleading test action.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: UI automation only validates the signed-out launch screen.
    - Severity: Medium
    - Impact: Signed-in shell, settings, account switching, content restrictions, item detail, playback presentation, downloads, book reader entry, and platform layouts remain mostly manual.
    - Affected platforms: iOS, iPadOS, tvOS, macOS, visionOS
    - Evidence: `GusLaunchUITests.swift` checks only that the Connect button exists. iOS has large-text and pseudo-localized variants; other UI targets get the same launch smoke. `GusApp.swift` and `Scripts/screenshots.sh` already expose richer debug-preview/demo routes.
    - Recommended fix: Add a small demo-server/debug-preview UI smoke suite covering signed-in home, libraries, settings/content restrictions, item detail, player presentation, and sign-out/account switch. Add accessibility identifiers where needed.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Child-safety and privacy side effects lack regression seams.
    - Severity: Medium
    - Impact: Pure content-rating decisions are tested, but Spotlight donations, Top Shelf snapshots, offline downloads, book cache/progress, WatchConnectivity credential snapshots, and account switch/sign-out cleanup can regress without test failures.
    - Affected platforms: iOS, iPadOS, tvOS, macOS, visionOS, watchOS
    - Evidence: `ContentRatingGateTests`, `AppModelSessionTests`, and `TopShelfSnapshotTests` cover pure logic/serialization, but no tests assert side-effect cleanup or re-filtering across adult-to-child switches, restriction changes, sign-out, or system integrations.
    - Recommended fix: Introduce injectable protocols/fakes for Spotlight indexing, Top Shelf writes, download/book-cache cleanup, and watch session relay. Add tests for adult-to-child switch, sign-out, restriction change, restricted deep links, downloads, and caches.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Book cache, reader progress, and Readium integration are largely untested.
    - Severity: Medium
    - Impact: EPUB/PDF open, local cache pathing, locator persistence, remote progress reporting, and account/privacy boundaries can regress without focused tests.
    - Affected platforms: iOS, iPadOS, macOS, visionOS where book reading is available
    - Evidence: `BookFileProvider`, `BookProgressStore`, and `BookReaderModel` contain cache, persistence, debounce, and progress-reporting logic; static search found no direct tests for cache destination, sanitized filenames, local locator persistence, debounce flushing, or Readium open/resume.
    - Recommended fix: Add tests with injected temp cache directory, fake media provider/downloader/session, and controllable clock. Keep Readium rendering itself as integration/manual verification.
    - Confidence: High
    - Manual verification required: Yes
  - Finding: Performance baseline tests do not enforce documented thresholds.
    - Severity: Low
    - Impact: CI can pass even if mapper, URL-normalization, or histogram performance regresses beyond documented thresholds.
    - Affected platforms: Unit-test schemes running performance tests
    - Evidence: `PerformanceBaselineTests` uses XCTest `measure {}` blocks; `Documentation/AppStore/performance-baselines.md` documents baseline values and thresholds, but no tracked Xcode baseline files or explicit budget assertions were found.
    - Recommended fix: Commit Xcode performance baselines and ensure CI evaluates them, or replace measurement-only tests with explicit budget assertions using generous thresholds.
    - Confidence: High
    - Manual verification required: No after CI enforcement
  - Finding: App icon generator is probably obsolete and conflicts with current guidance.
    - Severity: Low
    - Impact: A maintainer could regenerate the wrong brand asset.
    - Affected platforms: All app targets if regenerated assets are used
    - Evidence: `CLAUDE.md` says the current source is `Gus.website/assets/gus-mark.svg` and notes the older pineapple generator is not current; `Scripts/generate-app-icon.swift` still generates the older pineapple-style icon; roadmap still references the script as completed icon work.
    - Recommended fix: Remove the script, mark it obsolete, or rewrite it to rasterize the current website SVG source. Align roadmap/docs with `CLAUDE.md`.
    - Confidence: High
    - Manual verification required: Yes before deletion
  - Finding: Static reachability review found no definitely unused production Swift types or assets.
    - Severity: Informational
    - Impact: No cleanup recommended from static evidence alone; several low-reference symbols are expected platform lifecycle/reflection entry points.
    - Affected platforms: All
    - Evidence: Low-reference symbols include SwiftUI app/view entry points, Top Shelf provider, CarPlay scene delegate, App Intents/App Shortcuts, platform representables, nested SwiftUI views, and asset colors/icons referenced through `project.yml`, `Info.plist`, SwiftUI lifecycle, or platform frameworks.
    - Recommended fix: Do not remove lifecycle/reflection symbols based on text reference count alone. Verify through generated project inspection and platform launches before pruning.
    - Confidence: Medium
    - Manual verification required: Yes for platform lifecycle entry points
  - Finding: Several large files concentrate responsibilities and make targeted testing harder.
    - Severity: Informational
    - Impact: Future changes are more likely to blend UI, lifecycle, provider, persistence, and platform concerns, increasing review and testing cost.
    - Affected platforms: Broad app impact
    - Evidence: Large files include `ItemDetailView.swift`, `OfflineDownloadStore.swift`, `MediaModels.swift`, `VideoPlayerView.swift`, `PlaybackStore.swift`, `JellyfinMediaProviderSession.swift`, `AppModel.swift`, `RootContainer.swift`, `AudioPlayerStore.swift`, and `StreamURLBuilder.swift`.
    - Recommended fix: Split opportunistically when touching these areas, extracting pure mappers, query builders, progress reporters, cache path builders, section views, and small coordinators with focused tests.
    - Confidence: High
    - Manual verification required: No
- Severity of each finding: High, Medium, Medium, Medium, Medium, Low, Low, Informational, Informational.
- Recommended fixes: Isolate URLProtocol fixture state; add or correct watchOS test targets; expand UI smoke coverage using debug/demo routes; add regression seams for privacy/child-safety side effects; directly test book cache/progress; enforce performance budgets; retire or update obsolete icon generator; avoid pruning lifecycle symbols without runtime verification; split large files opportunistically.
- Assumptions made: `project.yml` is authoritative. Generated Xcode project state was not treated as source of truth. Swift Testing/XCTest may run tests concurrently unless isolated. Static reachability is insufficient for SwiftUI, Objective-C/runtime, AppIntents, Top Shelf, CarPlay, and platform lifecycle symbols.
- Manual verification items: Repeated parallel unit tests around `LibraryStoreTests`; real watchOS unit target or manual watch install/credential relay/remote/playback/offline tests; demo-server/debug-preview UI smoke tests on iOS, tvOS, macOS, visionOS; adult-to-child switch/sign-out validation for Spotlight, Top Shelf, downloads, book cache/progress, WatchConnectivity; EPUB/PDF open/resume/progress with Readium; confirm whether release process invokes `Scripts/generate-app-icon.swift`.
- Errors, limitations, or incomplete areas: No builds or tests were run. Ignored local build output and ignored `.DS_Store` files were excluded. A broad localization-key scan had interpolation false positives, so no unused localization finding was reported. Runtime-only reachability for AppIntents, CarPlay, Top Shelf, SwiftUI lifecycle, and platform extensions requires build/device or simulator verification.

## Batch Summaries

### Batch 1 Summary

- Sub-agents reviewed: Apple UX and Human Interface Expert; Swift, SwiftUI, and Architecture Expert; Jellyfin Integration and Networking Expert; Media Playback Expert; Security, Privacy, and Child Safety Expert.
- Key findings: Account switching is the strongest cross-area risk. The signed-in root can retain stores from the previous account, while Spotlight, tvOS Top Shelf, downloads, book caches, and watch credential context can outlive the active Jellyfin user. Playback is AVKit-first and generally well wired, but Now Playing observer lifecycle, audio resume reporting, audiobook media typing, queue remote commands, and watchOS video reporting need fixes. Jellyfin integration is well factored but lacks central expired-token handling, complete favorites support, long-series paging, and book/audiobook resume rails. Apple-platform UX is native overall, with gaps around macOS Settings, multiwindow route scoping, custom Form rows, and watchOS transport geometry.
- Cross-cutting risks: Session identity is not consistently used as a lifetime boundary for view state, caches, system surfaces, and companion-device handoff. Runtime verification is required for system integrations whose correctness cannot be proven statically: Spotlight, Top Shelf, WatchConnectivity, Now Playing, AirPlay, PiP, CarPlay, and device-specific watch/tvOS focus. `project.yml` remains authoritative for target/build conclusions.
- Follow-up needed: Batch 2 will review performance/caching, build/dependency/App Store readiness, accessibility/localization, and testing/dead-code/maintainability. The orchestrator should then merge duplicate account-switch/privacy/cache findings, separate static evidence from manual verification items, and prioritize remediation by child-safety, privacy, playback correctness, and platform-readiness impact.

### Batch 2 Summary

- Sub-agents reviewed: Performance, Caching, and Responsiveness Expert (orchestrator-authored after delegated reviewer timeout); Platform, Build, Dependency, and App Store Expert; Accessibility and Localization Expert; Testing, Dead Code, and Maintainability Expert.
- Key findings: Performance foundations are reasonable, but cache/storage cleanup needs an app-wide policy and book cache/progress I/O should move off the main actor. App Store readiness is gated by unpinned package resolution, CarPlay metadata/scene declarations without the entitlement, Declared Age Range staging, missing third-party notices, and watchOS scheme/test mismatch. Accessibility/localization gaps center on incomplete string catalog coverage, Info.plist localization, English-only formatting helpers, fixed-size large-text clipping risks, and progress semantics. Testing is strongest for pure stores/services but weak for UI, watchOS, privacy/child-safety side effects, book cache/progress, and performance budgets.
- Cross-cutting risks: Release readiness depends on a source-of-truth cleanup pass across `project.yml`, App Store docs, entitlements, CI, and package resolution. Privacy/child-safety concerns need both implementation fixes and regression seams. Many runtime-only areas still require physical-device or simulator validation because static review cannot prove Apple system-surface behavior.
- Follow-up needed: Read all checkpoints, merge duplicate account-switch/cache/system-surface findings, and produce the final prioritized remediation plan.

## Manual Verification Items

- Item: Adult-to-child account switching across system surfaces
- Reason: Static review shows Spotlight, Top Shelf, downloads, book cache/progress, WatchConnectivity, and root stores can outlive account switches.
- Related files/systems: `AppModel`, `RootContainer`, `SpotlightIndexer`, `TopShelfSnapshot`, `OfflineDownloadStore`, `BookFileProvider`, `WatchSessionRelay`.
- Suggested verification step: Browse adult content, switch to child account, then inspect app shell, system search, tvOS Top Shelf, offline playback, books, and paired watch without restarting.

- Item: Playback system integration
- Reason: AVKit/MediaPlayer behavior cannot be proven statically.
- Related files/systems: `PlaybackStore`, `AudioPlayerStore`, `NowPlayingController`, `VideoPlayerView`, `WatchVideoPlayerView`, CarPlay.
- Suggested verification step: Test playback, pause/resume, seek, next-up, audio queue next/previous, PiP, AirPlay, lock screen/Control Center, CarPlay, watchOS video/audio, and Jellyfin watched-state reporting.

- Item: Build/archive/platform matrix
- Reason: XcodeGen config, entitlements, package resolution, and schemes need generated-project and signed-archive validation.
- Related files/systems: `project.yml`, `Config/*.entitlements`, `Config/Shared.xcconfig`, generated `.xcodeproj`, Xcode Cloud/App Store Connect.
- Suggested verification step: Run `xcodegen generate`, lint config, build/test iOS/tvOS/macOS/visionOS/watchOS targets, then archive release builds with real signing profiles.

- Item: Accessibility/localization runtime pass
- Reason: VoiceOver order, focus, captions, Dynamic Type, RTL, and pseudolocalized text need actual UI inspection.
- Related files/systems: `Resources/Localizable.xcstrings`, Info.plists, item/player/watch/settings/search/book/live TV views.
- Suggested verification step: Run VoiceOver, Switch Control, Full Keyboard Access, tvOS Focus/VoiceOver, watchOS VoiceOver/Digital Crown, visionOS gaze/focus, largest text sizes, Reduce Motion/Transparency, RTL, and pseudolocalization.

- Item: Large-library and cache profiling
- Reason: Static review cannot prove scrolling smoothness, cache hit rates, storage growth, battery impact, or server latency behavior.
- Related files/systems: `HomeStore`, `LibraryStore`, `SearchStore`, `JellyfinClientFactory.urlCache`, `OfflineDownloadStore`, `BookFileProvider`, MetricKit/signposts.
- Suggested verification step: Use a large Jellyfin library and Instruments/MetricKit to profile launch, home load, library scroll, search, image cache growth, playback startup, downloads, and watchOS battery impact.

## Deferred / Incomplete Items

- Item: Live dependency vulnerability and maintenance research
- Reason deferred: Network/live advisory lookup was not performed in this static code review.
- Recommended next step: After package resolution is pinned, audit resolved JellyfinSDK, Readium, and transitive packages against current advisories and license obligations.

- Item: Runtime Apple Developer entitlement state
- Reason deferred: Developer Portal/App Store Connect access was not used.
- Recommended next step: Confirm CarPlay audio, Declared Age Range, tvOS user-management, App Groups, and signing profile grants before release claims.

- Item: Full build/test execution
- Reason deferred: The review was static; no Xcode build/test matrix or device runs were executed.
- Recommended next step: Run generated-project validation and focused tests after remediation patches, then broaden to platform builds and UI/device validation.

## Remediation Checkpoints

### 2026-06-12 Remediation Pass

- Status: Complete for locally actionable high-priority findings covered by the remediation plan; blocked/deferred for external Apple-account gates, live Jellyfin behavior, and device/runtime verification.
- Files, targets, modules, or systems inspected/modified: `project.yml`, `.github/workflows/ci.yml`, App Store docs, roadmap icon docs, `Scripts/generate-app-icon.swift`, app/session root wiring, `AppModel`, watch credential handoff, Now Playing/audio playback, book cache/progress, offline downloads, InfoPlist string catalogs, provider display formatting, playback accessibility formatting, downloads/watch progress accessibility, library/performance tests, and focused iOS/watchOS validation schemes.
- Summary of completed fixes:
  - Session/account cleanup now runs on sign-out and account switch for Spotlight, tvOS Top Shelf, watch credentials, book cache/progress, and offline download records/files.
  - Signed-in SwiftUI root is keyed by active account identity so account switches rebuild session-owned stores.
  - Watch credential handoff supports scoped clear payloads and removes only the matching watch-side token/session.
  - Now Playing removes previous time observers before starting, classifies audiobooks as audio, weakly captures the player, and exposes optional next/previous command callbacks.
  - Audio resume initializes elapsed time before playback-start reporting.
  - Book cache paths and progress keys are scoped by account, with scoped purge hooks.
  - Offline download records/files can be deleted by account, and loaded stores can cancel/remove only their loaded account.
  - CI config lint now includes watch Info.plist, TopShelf entitlements, and CarPlay entitlements, with a policy guard preventing premature CarPlay entitlement wiring.
  - App Store/signing docs now gate CarPlay and Declared Age Range claims until entitlement/provisioning is granted, and describe the current Xcode 26-built availability-gated policy.
  - The watchOS scheme no longer wires misleading iOS test bundles in `project.yml`.
  - Added app/watch InfoPlist string catalogs; duration formatting uses native formatter support; progress controls expose accessibility values.
  - `LibraryStoreTests` are serialized to avoid shared URLProtocol races; performance tests were renamed as measurement probes.
  - The obsolete pineapple app-icon generator is retired in place and roadmap/review docs now point at the current Gus brand mark SVG source of truth.
- Detailed findings remediated:
  - High: Previous-account stores/system surfaces could survive account switch. Fixed by root identity key and account cleanup actions.
  - High: Spotlight/Top Shelf/offline downloads could leak adult-account content after user switch/sign-out. Persistent cleanup is now wired and covered by focused tests; Top Shelf/Spotlight runtime behavior still requires device verification.
  - High: Now Playing observers could accumulate. Fixed by removing any previous observer on start and avoiding a strong player capture.
  - High: `LibraryStoreTests` shared mock state could be flaky under parallel execution. Fixed with suite serialization.
  - Medium: Book file/progress cache was not scoped by server/user. Fixed with scoped paths/keys and purge APIs.
  - Medium: Audio resume and audiobook Now Playing metadata were incorrect. Fixed and covered by focused tests.
  - Medium/Low: Release metadata, watch scheme testing, CI lint coverage, Info.plist localization, progress accessibility semantics, and stale icon-generation guidance were corrected.
- Recommended follow-up fixes:
  - Add central unauthorized/session invalidation for revoked Jellyfin tokens.
  - Add paginated series episodes, Favorites modeling/actions, and book/audiobook resume rails.
  - Decide/document authenticated image URL behavior for locked-down Jellyfin deployments.
  - Add a macOS `Settings` scene and scene-scoped navigation for multiwindow platforms.
  - Add a real watchOS test target and broader debug/demo UI smoke coverage.
  - Add third-party notices/license package and resolve App Store Connect/Developer Portal entitlement gates.
- Assumptions made: Static review findings were treated as authoritative where confirmed by source. `project.yml` was used as source of truth; generated `.xcodeproj` was regenerated but not source-controlled. The live AppModel cleanup purges persistent download records/files but does not own every running `OfflineDownloadStore` instance.
- Manual verification items: Adult-to-child switch on real devices/system surfaces; in-flight download cancellation during account switch; Spotlight and tvOS Top Shelf clearing; WatchConnectivity clear delivery; lock screen/Control Center/CarPlay remote commands; AirPlay/PiP; watchOS video/audio reporting; VoiceOver/Switch Control/keyboard/Dynamic Type/RTL; live Jellyfin revoked-token/large-library/episode/favorites/image-auth scenarios; signed archives and entitlement-backed App Store readiness.
- Errors, limitations, or incomplete areas: No live Jellyfin server, physical device, Apple Developer Portal, App Store Connect, CarPlay, AirPlay, PiP, VoiceOver, or full platform build matrix validation was performed in this remediation pass.
- Validation completed:
  - `xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/AppModelSessionTests`
  - `xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/AudioPlaybackTests`
  - `xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/BookCacheTests`
  - `xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/OfflineDownloadTests`
  - `xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/ProviderArchitectureTests`
  - `xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GusTests/LibraryStoreTests -only-testing:GusTests/PerformanceMeasurementTests`
  - `xcodebuild build -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus watchOS' -destination 'generic/platform=watchOS Simulator'`
  - `xcodegen generate`
  - `jq empty Resources/Localizable.xcstrings Resources/InfoPlist.xcstrings Resources/Watch/InfoPlist.xcstrings`
  - `plutil -lint Resources/Info.plist Resources/Watch/Info.plist Resources/PrivacyInfo.xcprivacy Sources/TopShelf/Info.plist Config/Gus.entitlements Config/Gus-tvOS.entitlements Config/GusTopShelf.entitlements Config/Gus-CarPlay.entitlements`
  - CI pending-entitlement policy check for CarPlay entitlement wiring.
