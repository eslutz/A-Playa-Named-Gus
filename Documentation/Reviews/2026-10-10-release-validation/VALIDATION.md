# Gus final local validation — October 10–11, 2026

**Available local validation completed. Release acceptance remains pending.** This
records the entire staged app candidate, existing offline/download work, UI remediation,
API preparation, and safe companion documentation/website changes. No push, upload,
submission or tester invitation was performed.

Execution began October 10 and continued October 11. Xcode 27.0 (`27A266a`), Swift 6.4, SDK 27.0, arm64 host, macOS 27.0.1. Marketing
version **1.0.0**, separate numeric build **1**. Deployment targets remain iOS/tvOS 18,
macOS 15, Watch 11 and Vision 2. Host-local timestamps use America/New_York; UTC dates
in test results retain their actual date; execution can cross local midnight.

## Reproducible candidate and evidence

The maintained runner is `Scripts/validate-release.py --phase all`; it requires the
rights-cleared local demo service for authenticated UI tests, resolves compatible
standard simulator UUIDs, pins dependencies, runs sequentially and rejects failures,
skips, expected failures and empty results. The final run used a materialized Git index
at `/tmp/gus-staged-candidate`, excluding ignored local configuration and credentials.
All inputs remained unchanged during each recorded phase. Candidate 11 fixes a Release-only
session-restoration test flag and the launch-helper product path. Fresh static checks
and all four Release archives validate the final source. The six Debug builds, four
unit suites and five maintained UI lanes are retained from candidate 10: the recovered
prior source matches its frozen hash and all active DEBUG tokens are identical. Fresh
expanded runtime/sanitizer tests exercise the final source; five actual launch runs
validate the helper. This reuse is explicit in `evidence/final/core/validation-provenance.json`;
earlier failed archive-content inspection remains history. Final static hashes match
staged Git blobs; older phases retain their original manifests without relabeling.
See `evidence/final/core/*/source-hashes.json` and `evidence/staged-source-verification.json`.
Vision visual evidence uses read-only native simulator captures because XCUIScreen
returns 1×1 placeholders. The capture observer records request/finish times and each
rendered image receives independent visual inspection; those times are not asserted
to equal a XCTest attachment timestamp.
The app-owned review ledger covers 146 Swift files, with 52 changed since the audit;
compiler/static coverage is distinguished from deep critical-path review in REPORT.md.

The original review folder's 497 files (496,940,241 bytes), all screenshots and both
addenda remain byte-identical in Git. Existing safe evidence stays in the commit.
Large new result bundles, unsigned archives and traces remain in ignored
`build/release-validation-2026-10-10/`; compact summaries, hashes, commands and selected
native captures are versioned. Failed/superseded runs are historical, not acceptance.
Credentials, private keys, machine-local media symlink and generated caches are excluded.

## Automated matrix

| Lane | Result | Duration |
|---|---|---|
| format | Pass | 0.64 s |
| api-format | Pass | 0.08 s |
| cloud-bootstrap | Pass | 0.68 s |
| project-pins | Pass | 0.48 s |
| asc-self-test | Pass | 1.32 s |
| whitespace | Pass | 0.05 s |
| yaml | Pass | 0.2 s |
| build-ios | Pass | 69.38 s |
| build-ipad | Pass | 16.29 s |
| build-mac | Pass | 44.48 s |
| build-tv | Pass | 44.47 s |
| build-vision | Pass | 45.87 s |
| build-watch | Pass | 29.29 s |
| unit-ios | 282 passed; 0 failed/skipped/expected | 159.73 s |
| unit-mac | 282 passed; 0 failed/skipped/expected | 48.8 s |
| unit-tv | 282 passed; 0 failed/skipped/expected | 70.48 s |
| unit-vision | 282 passed; 0 failed/skipped/expected | 52.51 s |
| ui-ios | 11 passed; 0 failed/skipped/expected | 357.32 s |
| ui-ipad | 11 passed; 0 failed/skipped/expected | 323.11 s |
| ui-tv | 3 passed; 0 failed/skipped/expected | 64.88 s |
| ui-vision | 3 passed; 0 failed/skipped/expected | 53.1 s |
| ui-watch | 1 passed; 0 failed/skipped/expected | 96.41 s |
| archive-ios | Pass | 204.45 s |
| archive-tv | Pass | 99.83 s |
| archive-vision | Pass | 100.21 s |
| archive-mac | Pass | 117.91 s |
| mac-thread-sanitizer | 282 passed; 0 failed/skipped/expected | 52.86 s |
| mac-address-sanitizer | 282 passed; 0 failed/skipped/expected | 55.27 s |
| release-performance-fixed | 3 passed; 0 failed/skipped/expected | 126.43 s |
| iphone-dark-contrast-ax5 | 4 passed; 0 failed/skipped/expected | 203.61 s |
| iphone-narrow-se | 6 passed; 0 failed/skipped/expected | 325.95 s |
| iphone-large | 2 passed; 0 failed/skipped/expected | 132.48 s |
| ipad-mini | 2 passed; 0 failed/skipped/expected | 142.63 s |
| tv-1080p | 2 passed; 0 failed/skipped/expected | 68.09 s |
| watch-large | 1 passed; 0 failed/skipped/expected | 175.61 s |
| ios-26-fallback | 2 passed; 0 failed/skipped/expected | 183.35 s |
| vision-native-capture | 2 passed; 0 failed/skipped/expected | 61.12 s |
| audio-ax5-landscape | 1 passed; 0 failed/skipped/expected | 41.21 s |

External native state suite: **8 passed**, no failures/skips; pending
Connect cancellation, Downloads management rotation, More → Settings → Navigation
rotation, refused-connection recovery, photo opening/rotation/slideshow toggle, genuinely
paused video rotation/Close, actual system accessibility setting
inventory, and Reduce Motion/Reduce Transparency/Differentiate Without Color/Bold Text.
All four settings are asserted active for the movie capture and restored afterward.
Refused-connection recovery completed after approximately 91 seconds, consistent with
the configured 90-second resource budget; the harness permits a bounded 120-second wait
and requires enabled Connect/no Cancel. Cancel remains available while pending.
The earlier 30-second failure is historical, not a passing result.
The external harness and expanded-lane commands are retained under `evidence/harness/`.
Native macOS maintained UI startup was attempted and stopped after 311 seconds without
starting app assertions. Xcode records a canceled runner error; zero app UI executions
completed. This is an inconclusive environment/startup lane, not a pass or a product
assertion failure; no signing/TCC root cause is established. Raw desktop attachments
remain local and are excluded from versioned visual evidence.
Website: 3 tests pass, no skips, and Eleventy production build passes. Wiki: 12 Markdown
pages validate, all non-example interpage links resolve, and `_Sidebar.md` stays absent.
Final staged whitespace and secret/artifact checks are recorded in
`evidence/final-repository-checks.json`. Commit SHAs and observed clean post-commit
status are saved locally in ignored `build/release-validation-2026-10-10/commit-verification.json`.

## UI/UX, design and accessibility review

Accepted native screenshot provenance lists **171 captures** in
`evidence/final/native-capture-manifest.json`. Captures support the following scoped
journeys; the smallest phone lane is an isolated 375×667 SE viewport.
The synchronous external Vision bridge retains stable detail images; late observer
detail images showing closed scenes are excluded. No global accessibility, HIG or App Review certification is implied.

| Surface | Evidence / limits |
|---|---|
| Connect | Standard and verified AX5 native text, complete typed URL, >=44-point native row, scoped hit-region/text-clipping audit; native double-length localization has a doubled-label assertion. |
| Movie/album/book | Loaded primary actions, bounded artwork and portrait/landscape layouts on narrow/large phones and large/mini iPads; movie metadata has an opaque white-on-black text surface. |
| Book reader | Actual EPUB-rendered title text, landscape, exact reader Done, web view gone and reachable Read afterward. Full chapter, pagination, PDF and assistive reading remain manual. |
| Audio | Rotation, Done, persistent Now Playing, reopen and Stop; focused actual AX5 landscape ScrollView Pause/Play/reopen reachability and >=80-point native transport frame; TV Menu/focus/select and Vision close/reopen; visual transport state does not prove audible output. |
| Synopsis | Long heading wraps semantically, real supplied overview and explicit Done; tested at actual largest text in the appearance matrix. |
| RTL | Apple's native writing-direction switches and mirrored Done-position assertion; existing English catalog, not an Arabic translation claim. |
| Watch | 40 mm and 46 mm album → tracks → audio Pause/Play; actual Crown, route-picker output, remote hardware and battery remain manual. |
| Appearance | Native dark + Increased Contrast + actual AX5, reduced effects/color distinction/Bold Text; baseline settings restored. Older iOS 26.5 exercises the audio-session fallback. |
| Recovery | Pending Connect Cancel returns an enabled Connect control; cancellation/re-entry, stale detail/search, error, paging and offline-account races have unit regressions. |

The strict iPhone rated-movie screen audit requests contrast, hit region and sufficient
element description. Xcode 27 reports identified native Done and Play contrast false
positives. Original element samples measure approximately 20.65:1 and 6.51:1. The
maintained test classifies only these exact identified enabled controls, then requires
actual hittability and a fresh central-label pixel sample >=4.5:1 after the native audit.
The native iPad form-sheet contrast scanner repeatedly samples clipped/offscreen text
against the underlying Home surface. That check is **blocked, not passed** (RV-015);
iPad retains native hit-region/description audits and independent visible Done/Play
pixel checks. Source-backed opaque hero text and inspected images support the scoped
design review, not complete iPad contrast acceptance.
Unknown/unlocated issues and other types fail. This coarse local guard is not proof for
all pixels, all artwork or all states. The Connect URL text-clipping exception is limited
to that exact single-line, hittable field with the complete value asserted and its native
row >=44 points; ordinary horizontal entry is intentional. No blanket issue suppression.

Design judgment used actual native screens: primary actions remain realized above
secondary lazy content, semantic text wraps, navigation and player ownership survive
rotation, artwork stays bounded, and native controls retain their platform behavior.
The deliberate opaque hero text surface makes metadata contrast predictable over arbitrary
artwork; glass remains on controls. Earlier mislabeled AX5/RTL/en-XA runs are superseded
by RV-014's verified native test modes. TV focus and default Vision window layouts have
simulator evidence; live Mac resizing, spatial input and physical assistive interaction
remain separate.

## Swift, reliability, privacy and packaging

Complete concurrency checking is enabled across app/test targets. Watch, Top Shelf,
tvOS and visionOS app use Swift 6; iOS/macOS use Swift 5 with complete checking. Five
unique first-party diagnostics remain at four Readium APIs and Apple's Declared Age
Range action. They are documented migration boundaries, not a completed Swift 6
migration or proof of SDK thread safety. See SWIFT-CONCURRENCY.md and the final warning
inventory. Retry actor inheritance, provider calls, diagnostics/download locks,
Sendable socket/delegate bridges, cancellation and ordered audio-session activation
have focused regression coverage. Sanitizers cover the shared macOS unit corpus,
not Readium UI, every platform framework or physical playback.

Release archive inventory verifies app/Watch/Top Shelf identities, semver 1.0.0 and numeric
builds, app-owned `CA92.1` UserDefaults and `E174.1` disk-space refusal reasons, all
bundled dependency privacy manifests and executable hashes. Debug demo/route/session-reset
launch strings are absent from Release binaries. Archives are unsigned; distribution
signing, approved entitlements and Apple's upload validation have not been established.
Private logging, Keychain credential ownership, account-scoped local downloads and public
Apple-framework/availability use were reviewed. Portal privacy answers and reviewer access
must still match the actual distributed build. CarPlay remains unwired pending approval.

## Performance scope

Optimized test-enabled Release pure-logic metrics (coverage off), five-run Debug simulator process-spawn timing, and bounded
native Instruments attempts are recorded in `evidence/final/` and
`Documentation/AppStore/performance-baselines.md`. Process spawn is not first usable frame.
Each attached trace follows a movie-detail route request and two-second settle; loaded rendering
is not asserted per trace. A bounded trace is not a navigation peak, leak soak, battery or thermal measurement.
Time Profiler exported 2,968 actual samples (988 main-thread); one auxiliary table
reported an unavailable input. Standard SwiftUI Hitches is unsupported on this simulator.
Any successful Leaks attempt without allocation/leak tables is inconclusive, not zero leaks.
Compatible attached and launch-time SwiftUI recordings also warn of no SwiftUI data;
the exported attached update table has zero rows. SwiftUI runtime profiling and leak
validation remain inconclusive. The final attempt/data dispositions are recorded
in the profile evidence.
Do not compare these directly with the older Xcode 26.5/iPhone Debug baselines; environment
and configuration differ. Production MetricKit/device acceptance remains pending.

## Remaining release gates

- Connect the physical iPhone/TVs and validate the signed candidate, real media/codecs,
  streamed and downloaded pause/rotate/seek/close, background/lock/cold offline relaunch,
  interruption, AirPlay/PiP, remote output and storage-pressure behavior.
- Resolve/retest the documented native iPad contrast-scanner fault and complete full
  iPad contrast acceptance; no native iPad contrast pass is claimed.
- Execute minimum deployment OS runtimes, native Mac window/keyboard/menu workflows,
  VoiceOver focus/rotor/escape, Voice Control/Switch Control/Crown and Vision spatial input.
- Validate real tuner/EPG/recording capabilities, photo/paging/media variants, restricted
  accounts, EPUB/PDF reading depth and caption/alternate audio with suitable media.
  Unit/source evidence and selected screenshots do not close every runtime combination.
- Resolve upstream isolation contracts or a reviewed confined reader service for Readium
  and the Declared Age Range action before migrating iOS/macOS to Swift 6.
- Add the unavailable App Store Connect key at its documented ignored private path, perform
  read-only API connectivity, verify app/bundle/workflow records, then authorized Cloud
  signing/build/upload and a TestFlight installation. Local API self-tests are not portal
  verification. No key or credential value was committed.
- Finish accurate listing/privacy/accessibility disclosures, approved entitlements,
  rights-cleared current store screenshots and reviewer-accessible server verification.

The audit's verified High findings (Watch navigation, disk-space declaration and book
primary-action reachability) have passing scoped retests. Manual/portal acceptance and
five SDK migration diagnostics remain explicit. App Review/HIG/developer-policy mapping
is in REPORT.md and the readiness packet; Apple approval is not inferred.
