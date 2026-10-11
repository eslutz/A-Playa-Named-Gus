# Gus UI remediation — October 10, 2026

The implementation addresses all 24 findings from the [original report](../2026-10-09-ios-ui/REPORT.md), [physical-device addendum](../2026-10-09-ios-ui/PHYSICAL-DEVICE-ADDENDUM-2026-10-10.md), and [multiplatform addendum](../2026-10-09-ios-ui/MULTIPLATFORM-SIMULATOR-ADDENDUM-2026-10-10.md). The approved behavior is implemented: Done keeps prepared audio playing with a persistent Now Playing return, and compact iPhone navigation uses an explicit More list.

**Code and automated checks pass. Release acceptance remains incomplete.** Simulator evidence covers the stated flows below; it does not establish physical playback continuity, VoiceOver behavior, Mac window/keyboard behavior, spatial input, or Watch audio readiness. The original review folder and both addenda remain intact. Changes are local and uncommitted, preserving the checkout's pre-existing offline/download work.

## Implementation by finding

“Implemented” describes the code change. The validation column deliberately distinguishes deterministic tests, observed runtime behavior, and remaining manual checks.

| ID | Implemented change | Validation / remaining scope |
|---|---|---|
| 001 | Session-owned audio queue; persistent Done/Stop; Now Playing return; TV Menu closes presentation. Closing during preparation cancels work. | iPhone and both iPad sizes: close, rotate, reopen, Stop. TV: Menu, remote focus, reopen. Vision: controls visible in default window. Mac interaction pending. |
| 002 | Video loading/error Close and Retry; book preparation Done and Retry; cancellation guards prevent late publication. | Deterministic late-video and late-audio tests; actual EPUB opens, rotates and closes; slow/failed book UI still needs manual verification. |
| 003 | Audio layout adapts horizontally or vertically, scrolls when needed, and uses reachable transport hit regions. | iPhone portrait/landscape at normal and actual AX5 text; iPad Pro/mini rotation. Watch's changed player was not reached; see follow-up. |
| 004 | Audio loading/failure/retry UI; observe playback-item failures after URL resolution. | Missing-local-file and late-resolution tests; demo startup/playback. Hardware/network interruption acceptance pending. |
| 005 | RootNavigationState owns selected section, per-section NavigationPath, search, cached stores, scroll anchors and presentation intent above adaptive layouts. | Downloads management, Navigation settings, prepared audio, paused video and EPUB survive tested phone rotation; deterministic identity/path/search remount tests. Physical streamed/downloaded video and iPad live window resizing pending. |
| 006 | Library/search scan at most three raw pages per attempt, retain raw offsets, expose Continue when admitted results remain absent, and stop on empty inconsistent pages. | Deterministic restricted-page, continuation, raw-offset and inconsistent-total tests. |
| 007 | Connect Refresh and Manage Downloads receive minimum 44-point bounds. | Standard Connect assertions and targeted audit; Downloads route/rotation exercised. Physical edge tapping pending. |
| 008 | Album artwork/info and Play/Shuffle switch to stacked layouts when horizontal content does not fit. | Loaded album portrait/landscape on phone and representative iPad sheets. Translated metadata remains a manual case. |
| 009 | Hero actions use an adaptive grid or accessibility-size vertical stack; Read/Share are stacked; hero grows with content. | Phone normal/AX5 book controls, iPad book sheets, Vision Share shape; actual reader launch and rotation. |
| 010 | About cards grow intrinsically; Show More presents the complete synopsis in a scrollable native sheet with Done. | Actual AX5 Show More opens the synopsis sheet and Done dismisses it; source confirms the full text is scrollable. End-to-end reading with VoiceOver remains manual. |
| 011 | Detail, seasons/episodes and Navigation errors expose local retry. | Selected-season retry test; successful detail/Navigation flows. Each server failure UI still needs manual injection. |
| 012 | Favorite/watched mutations serialize, disable while busy, show errors, and reconcile failed post-mutation refresh before another toggle. | Deterministic concurrent failure and successful-mutation/failed-refresh tests prevent a duplicate toggle. Production user data was not mutated. |
| 013 | Season/episode request generations reject obsolete successes, failures and cleanup. | Reversed completion and stale-failure tests. |
| 014 | Search generations, child cancellation and immediate reset prevent old pagination publishing into a new query. Debounce belongs to session state. | Stale success/failure, pagination and layout-remount tests. |
| 015 | Missing artwork uses a static placeholder; loaded artwork remains independently constrained. | Source verified; actual demo placeholders and loaded poster/card captures. |
| 016 | Photo collection merges and deduplicates the opened photo before presenting it, even when absent from the first page. | Deterministic opened-photo-outside-page test. Long physical photo library remains untested. |
| 017 | Connect has Cancel; tracked request generations and cancellation checks prevent navigation after dismissal. | Actual pending connection → Cancel → Connect available; no real server/account was added. |
| 018 | Short native Connect title plus a wrapping “Connect to Jellyfin” content heading. | Actual AX5/dark/Increase Contrast capture shows the full heading. |
| 019 | The named Connect labels/helper text use semantic primary foreground. | Original candidate measured below regular-text contrast in scoped baseline samples; corrected light capture measures 18.82:1–21:1. See measurement limits below. |
| 020 | ArtworkTile gives layout ownership to the tile; image pixels render in a clipped overlay and cannot expand cards. | Loaded wide movie art on phone, iPad, TV and Vision fits its assigned card; placeholders are separate evidence. |
| 021 | Detail content takes the actual available pane width; hero background cannot size its parent; title/actions can stack and grow. | Loaded phone/iPad/TV/Vision details fit sampled panes. Narrow Mac and spatial window resizing pending. |
| 022 | Typed Settings destinations share one section stack; explicit iPhone More replaces system overflow nesting. | More → Settings → Navigation exposes one header, Edit/Done works, and the destination survives rotation. |
| 023 | Filled Play/Read actions use an appearance-aware contrasting foreground, with white hero text scoped separately. | Enabled movie Play measured 6.05:1 light and 10.99:1 dark; TV and Vision captures corroborate the corrected appearance. |
| 024 | TV content links push into the selected section's full navigation destination. | Full-width movie link, remote focus movement, and Menu return to Home. Other TV media/link combinations remain manual cases. |

Implementation details are reviewable in the [delta against the initial dirty checkout](evidence/implementation.patch), [change scope](evidence/change-scope.json), and [new regression tests](../../../Tests/APlayaNamedGusTests/UIRemediationTests.swift). No broad staging or commits were performed.

## Automated verification

| Target | Result |
|---|---|
| iOS 27 simulator | 274 tests in 46 suites passed; final build passed |
| iPadOS 27 simulator | Final iPad build passed |
| Native macOS | 274 tests in 46 suites passed; final build passed |
| tvOS 26.5 simulator | 274 tests in 46 suites passed; final safe-area Now Playing change retested with the full suite |
| visionOS 26.5 simulator | 274 tests in 46 suites passed; final build passed |
| watchOS 26.5 simulator | Companion build passed |

The suite includes 17 new deterministic remediation tests. [Unit summaries](evidence/checks/unit-summary.txt), [commands/results](evidence/checks/unit-and-build-results.json), [final build results](evidence/checks/final-build-results.json), and the [last TV test](evidence/checks/final-tv-test.json) are saved with the report. The last source adjustment is confined to the tvOS conditional branch and was rebuilt/retested separately.

Scoped SwiftFormat lint passed for all 40 changed/new Swift files; `git diff --check` passed. The String Catalog parses, adds nine entries, and changes none of the existing entries. XcodeGen was rerun for new files/resources. [Local website generation and its three Node tests](evidence/checks/website-validation.txt) passed using the bundled Node runtime; wiki and website changes remain local.

## Accepted runtime evidence

Tests use the real local demo Jellyfin server and existing debug launch routes. They are external acceptance harnesses, not new production app entry points. Native simulator screenshots are used for orientation evidence. Later collection waits for a localhost capture service before navigating away, avoiding the original XCTest landscape transform and a timing race in early collection.

- **Phone normal text:** loaded [Home](evidence/iphone-max/home-portrait.png), [movie](evidence/audio-closure/movie-contrast.png), [album return](evidence/audio-closure/album-audio-return.png), [Downloads rotation](evidence/downloads-rotation/downloads-management-landscape.png), and [single Navigation header](evidence/iphone-remaining/more-settings-navigation-portrait.png). Actual [EPUB landscape](evidence/players-final/book-reader-landscape.png) and [paused video landscape](evidence/players-final/video-paused-landscape.png) retain the player/reader presentation.
- **Phone AX5:** applied simulator content size, dark appearance and Increase Contrast, rather than a launch override. [Book actions](evidence/ax5-final/book-large-actions.png), [audio landscape](evidence/ax5-final/audio-landscape.png), and [Now Playing after rotation](evidence/ax5-final/audio-closed-compact.png) are correctly framed. [Connect heading](evidence/ax5-final/connect-top.png) wraps completely, [Refresh](evidence/ax5-final/connect-standard.png) remains reachable after scrolling, and [Show More opens the synopsis sheet](evidence/ax5-final/full-synopsis.png) with working Done.
- **iPad Pro 13-inch:** synchronized [movie landscape](evidence/ipad-pro-final/movie-landscape.png) and [book landscape](evidence/ipad-pro-final/book-landscape.png) fit the native sheet. Audio exit/reopen and rotation assertions passed. Early unsynchronized captures are excluded from visual acceptance.
- **iPad mini:** [audio landscape](evidence/ipad-mini-final/audio-landscape.png), [Now Playing return](evidence/ipad-mini-final/audio-closed-now-playing.png), and loaded [movie](evidence/ipad-mini-final/movie-landscape.png), [book](evidence/ipad-mini-final/book-landscape.png), and [album](evidence/ipad-mini-final/album-landscape.png) details provide narrow-sheet coverage. Both final audio and layout tests completed successfully.
- **Apple TV 1080p:** [full detail](evidence/tv-final/tv-detail-full-screen.png), [opaque audio surface](evidence/tv-final/tv-audio-player.png), [Menu return control](evidence/tv-final/tv-audio-closed.png), and [remote reopening](evidence/tv-final/tv-audio-reopened.png). The return uses a native safe-area inset because the TV root toolbar did not expose it.
- **Vision Pro:** [Home](evidence/vision-final/home.png), [movie](evidence/vision-final/movie.png), [book](evidence/vision-final/book.png), and [audio](evidence/vision-final/audio.png) were inspected in the default simulator window. These establish layout/control presence, not gaze, hand input, audible output, or resized-window acceptance.

The [runtime harness](evidence/runtime-harness.swift), [TV harness](evidence/tv-runtime-harness.swift), [Watch harness](evidence/watch-runtime-harness.swift), and [final log summaries](evidence/checks/ui-summary.txt) preserve assertions and failures. A passing collector or issue handler does not imply accessibility conformance.

### Contrast measurements

The named Connect labels/helpers measured 3.29:1–3.44:1 before the semantic-primary change and 18.82:1–21:1 afterward in standard light appearance. Enabled movie Play measured **6.05:1 light** and **10.99:1 dark**. [Connect measurements](evidence/contrast/connect-measurements.json), [light Play](evidence/contrast/play-light.json), and [dark Play](evidence/contrast/play-dark.json) include sampled colors, crops and capture scope.

These are sRGB core-glyph/fill sample pairs from the stated captures. The regular-text reference is 4.5:1; disabled controls are treated separately under [WCAG's contrast-minimum guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html). Samples do not establish conformance across every backdrop, focus state, accessibility setting, or platform. The targeted automated audit intentionally records issues without failing collection; its disabled Connect, debug footer, and text-field clipping warnings remain separately scoped.

## Remaining acceptance and observed follow-up

1. **Physical phone:** the paired iPhone remains disconnected. Reinstall/launch evidence and paused streamed/downloaded video rotation on the actual phone are pending; existing device downloads were not changed.
2. **Mac:** Computer Use independently reported a locked host. Native narrow/wide window resizing, keyboard navigation, Escape, sheets and player-window close/reopen remain unverified. The unlock request did not produce an unlocked session during this run.
3. **Watch:** the 40 mm Watch reaches Remote, Browse and Music, but selecting the album stalls before the changed audio player is reached. The runner times out and a sample records the main thread busy in SwiftUI view-graph updates. [Stalled screen](evidence/watch-small/album-stalled.png) and [thread sample](evidence/watch-small/album-stalled-stack.txt) are retained. WatchAlbumView/WatchPoster were unchanged from the initial checkout; the cause is not established. This is an unresolved follow-up, not successful audio acceptance or a proven simulator-only issue.
4. **Assistive/platform input:** VoiceOver speech/focus/rotor, Switch Control, physical hit tolerance, Digital Crown, spatial input/window resize, translated/very long metadata, minimum-OS runtimes, and all loading/error/network interruption transitions remain manual gates. iOS 18 deployment builds, but no iOS 18 simulator runtime was available.

Early book-reader evidence that still showed detail, old transparent TV audio, malformed/late iPad captures, the iPad Pro cold-launch capture showing only the launch screen, and interrupted runners are excluded from acceptance. A cleanup command overlapped two new UI runs; the unfinished checks were rerun and those interruptions are not attributed to Gus. The final summaries identify exactly which test assertions completed.

The demo server configuration/media are preserved. [Cleanup verification](evidence/checks/cleanup-results.json) records stopped audit players, capture service and simulators, and restoration of the phone simulator's original light/Large/Increase Contrast off settings. A stalled simulator control channel required a CoreSimulatorService restart after the audit devices were shut down. No production server, publication, physical app installation, commit or PR is part of this implementation.
