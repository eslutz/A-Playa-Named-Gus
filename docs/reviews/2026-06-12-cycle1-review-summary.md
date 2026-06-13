# Gus Codebase Review — Executive Summary

**Date:** 2026-06-12 | **Commit:** `0f6290a` (main) | **Platforms:** iOS, iPadOS, tvOS, watchOS, visionOS, macOS

---

## Overall Health Verdict

**Good foundation, three release-blocking categories to address before App Store submission.** The architecture is sound, the Apple-first mandate is largely honored, and the Keychain/token flow is correctly implemented. No critical bugs were found. The blocking issues are: (1) three security/privacy one-liners that are trivially fixable now, (2) three App Store submission prerequisites that are operational rather than code (demo server, website, Xcode Cloud), and (3) two playback bugs users will reliably encounter. Structural debt (VideoPlayerView platform branches, ItemDetailView size, pagination inconsistencies) is real but does not block release.

---

## Top 10 Findings

| # | Sev | Title | One-line impact |
|---|---|---|---|
| 1 | **High** | SearchStore pagination deadlock on error | After any pagination error, infinite scroll is permanently broken for that search session — no recovery without dismissing and reopening |
| 2 | **High** | No auto sign-out on mid-session 401 | Expired/revoked tokens leave the app silently broken; user must manually navigate to Settings to sign out |
| 3 | **High** | ~25 user-visible strings absent from Localizable.xcstrings | Live TV, Watch, Settings, Home, Photos, and Books feature strings are permanently English regardless of device locale |
| 4 | **High** | GusError mapping has zero unit tests | The type that drives error display, sign-in flows, and cancellation gates across 10+ feature files has no regression signal |
| 5 | **Medium** | URLCache not flushed on sign-out | User A's cached poster art and API payloads remain on disk and serve to user B on a shared device — a privacy violation |
| 6 | **Medium** | failedToPlayToEndTimeNotification not observed | Mid-stream HLS failure (network drop, server killed) leaves the player frozen on a black frame with no error state or recovery path |
| 7 | **Medium** | Content rating gate missing from Live TV channel list | Adult-rated channels appear in the channel list for users with a content limit set; only recordings are filtered |
| 8 | **Medium** | tvOS NowPlaying dual-writer race | Both AVPlayerViewController and NowPlayingController write to MPNowPlayingInfoCenter on tvOS, causing flickering metadata and artwork drops |
| 9 | **Medium** | Hardcoded demo credentials in AppModel (DEBUG-gated) | Username "gus" / password "playa-demo" compile into debug builds; credentials are readable from any intercepted binary |
| 10 | **Medium** | App Store submission prerequisites incomplete | Hosted demo server, public website pages, and Xcode Cloud workflow are all placeholders — each individually blocks first submission |

---

## Prioritized Remediation Plan

### Track 1: Security/Privacy one-liners (do now, before any beta distribution)

| Rank | Title | Complexity | Platforms |
|---|---|---|---|
| 1 | Flush URLCache in AppModel.clearAccountData() | Small | iOS, iPadOS, tvOS, macOS, visionOS |
| 2 | Apply ContentRatingGate to Live TV channel list | Small | tvOS, iOS, macOS |
| 3 | Externalize demo credentials from AppModel.swift | Small | iOS, tvOS, macOS, visionOS |

### Track 2: Correctness bugs (before TestFlight)

| Rank | Title | Complexity | Platforms |
|---|---|---|---|
| 4 | SearchStore: add defer block for isLoadingNextPage | Small | All |
| 5 | Observe failedToPlayToEndTimeNotification in PlaybackStore | Small | iOS, iPadOS, tvOS, macOS, visionOS |
| 6 | Set updatesNowPlayingInfoCenter = false on tvOS AVPlayerViewController | Small | tvOS |
| 7 | Fix task(id:) boolean collapse in PlaybackOptionsMenu | Small | iOS, iPadOS, tvOS, macOS, visionOS |
| 8 | Wrap StreamURLBuilder + DownloadSourceResolver in NetworkRetryPolicy | Small | All |
| 9 | Store bare Task handles in ConnectServerView / SignInView | Small | iOS, iPadOS, tvOS, macOS, visionOS |

### Track 3: App Store readiness (operational — before submission)

| Rank | Title | Complexity | Platforms |
|---|---|---|---|
| 10 | Provision hosted demo server at demo.gus.ericslutz.dev | Large (ops) | iOS, tvOS, macOS, visionOS |
| 11 | Publish website support/privacy/accessibility/age-suitability pages | Medium (ops) | All |
| 12 | Create Xcode Cloud workflow in App Store Connect | Large (ops) | All |

### Track 4: Quality and completeness (parallel with tracks above)

| Rank | Title | Complexity | Platforms |
|---|---|---|---|
| 13 | Add GusErrorTests.swift unit test suite | Small | All |
| 14 | Add centralized 401 → auto-sign-out handler | Medium | All |
| 15 | Populate ~25 missing strings in Localizable.xcstrings | Medium | All |
| 16 | ScaledMetric for AudioPlayerView play/pause button | Small | iOS, iPadOS, tvOS, macOS, visionOS |
| 17 | Replace .red/.green with semantic system colors | Small | iOS, iPadOS, macOS, watchOS |
| 18 | Move Spotlight indexing to background Task | Small | iOS, iPadOS, macOS, visionOS |
| 19 | Raise episode/album/watch fetch limits (300 → 1000) | Small | All |
| 20 | Add ADR or refactor for import Get in GusError/DownloadSourceResolver | Small | All |

### Track 5: Structural refactors (plan separately)

| Rank | Title | Complexity | Platforms |
|---|---|---|---|
| 21 | Extract platform branches from VideoPlayerView into Sources/Platform/ | Large | All |
| 22 | Decompose ItemDetailView.swift (802 lines) into sub-files | Large | All |
| 23 | Implement toggleWatched / toggleFavorite in MediaProviderSession | Large | iOS, iPadOS, tvOS, macOS, visionOS |
| 24 | HDR pixel format in StereoFrameRenderer (visionOS Cinema) | Large | visionOS |
| 25 | Photo viewer sibling window + ring-buffer pagination | Medium | iOS, iPadOS, macOS, visionOS |

---

*Full findings with file paths, symbol names, and manual verification items in `GUS_CODEBASE_REVIEW_LOG.md`.*
