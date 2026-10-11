# Gus release validation audit — October 10, 2026

Initial audit recorded before implementation. **Available local remediation and
validation are complete; release acceptance remains pending.** Findings below preserve
the starting candidate and intermediate failures. The final dispositions and
[validation record](VALIDATION.md) supersede those historical states.

## Candidate and review scope

The app, wiki and website starting hashes and dirty-path dispositions are preserved in
[baseline-inventory.json](evidence/baseline-inventory.json). Recovery copies and binary
diffs are at `/tmp/gus-validation-baseline-2026-10-10/`. All existing safe changes and
the original review folder, screenshots and both addenda are included in the commit
scope. Credentials, caches and the local media symlink remain local.

Xcode 27.0 (`27A266a`), Swift 6.4 and SDK 27.0 compile the app. Deployment targets remain
iOS/tvOS 18, macOS 15, watchOS 11 and visionOS 2. Version remains **1.0.0**, build **1**.
The [source inventory](evidence/source-inventory.json) covers all 145 app-owned Swift
files with hashes, compiler/static API/isolation/ownership inventory and area. This
is not a claim that every feature received a device walkthrough. Deep source tracing
covered authentication/Keychain, session/root ownership, search and library generations,
playback/reporting/presentation, downloads/delegate delivery, Watch browsing/relay,
privacy/diagnostics, provider boundaries, SharePlay, Top Shelf, CarPlay, and availability.

The complete-concurrency iOS/Watch build passes in Swift 5 mode. Its
[40 unique first-party diagnostics](evidence/complete-concurrency-baseline.txt) remain
actionable. Package diagnostics are separate; changing language mode globally would
also modify third-party compilation and is not an acceptable migration experiment.
Cloud bootstrap: six tests pass. Shared project/pins check passes (11 schemes, 16 pins).
SwiftFormat fails in two of 189 input files.

## Findings

| ID | Priority / evidence class | Finding and required disposition |
|---|---|---|
| GUS-RV-001 | **High — verified runtime defect** | Watch Music → PUBLIC DOMAIN album never reaches tracks. Native XCTest fails after 270 seconds; the event loop fails to idle. A 3-second stack sample shows continuous SwiftUI graph transactions, including repeated WatchPoster construction; observed CPU reaches one full core. Cause is not yet proven. Fix and retest the real album → track → pause journey before calling Watch validation complete. |
| GUS-RV-002 | **High — verified manifest mismatch** | `OfflineDownloadStore.ensureDiskBudget` checks free capacity and refuses a download, while the manifest declares only `85F4.1` (display storage). Apple's `E174.1` covers refusing downloads when space is insufficient. Align the declaration and documentation with the observable behavior; inspect both app and Watch Release bundles. |
| GUS-RV-003 | **Medium — compiler/source risk** | Minimal checking hides 40 first-party complete-concurrency diagnostics. Boundaries include retry closures, provider task groups, mutable delegate singletons, Readium and newer Apple APIs. Strengthen checking, fix ownership/locking where justified, and perform target-scoped Swift 6 experiments. Record a concrete dependency boundary if a target cannot migrate safely. No blanket unchecked/preconcurrency suppression. |
| GUS-RV-004 | **Medium — verified automation failure** | SwiftFormat rejects `StreamURLBuilder.swift` and `SignInView.swift` for unwrapped single-line if bodies. Format and rerun the entire source/test set. |
| GUS-RV-005 | **Medium — verified validation gap** | Durable UI tests cover only three Connect smokes. Authenticated rotation, dismissal/reopening, failure recovery and per-screen accessibility audits live in external harnesses. Move useful assertions into maintained suites with explicit fixture prerequisites, screenshots and issue dispositions. A collector that returns true for every accessibility issue is not a passing audit. |
| GUS-RV-006 | **Medium — verified configuration/documentation drift** | CI/project declare Xcode 26.5 despite local SDK 27; readiness docs claim all features functional and MetricKit-proven battery behavior without matching acceptance evidence. Top Shelf docs incorrectly say it fetches nothing. Wiki has a sidebar contrary to its documented convention. Reconcile against current source and verified runner availability; retain manual release gates. |
| GUS-RV-007 | **Medium — source-supported privacy risk** | General network/error descriptions and a media title are logged publicly. WebSocket/stream URLs can contain access tokens; server-provided errors and metadata are private even if no leak was observed. Make user/server/error payloads private and keep public diagnostic fields numeric/boolean or fixed status. Scan retained evidence before committing. |
| GUS-RV-008 | **Medium — source-supported recovery defect** | Several loading states return on cancellation without leaving `.loading`; `ItemDetailStore.load`, SignIn, Live TV and Watch loads then refuse a later load. A view-owned task can be cancelled on disappearance while its store survives. Add a cancellation/re-entry regression and reset only the current request's state; prevent late cancelled results from publishing. |
| GUS-RV-009 | **Polish — observed truncation** | Full synopsis body is available, but the sheet's large heading truncates a long movie title. Allow that heading to wrap and verify at largest text. This does not reopen the original missing-synopsis defect. |

GUS-RV-001 evidence: [stalled Music screen](evidence/runtime/watch/album-stalled.png),
[native stack sample](evidence/watch-stall-sample.txt),
[failed-run summary](evidence/watch-baseline-summary.txt). This is a product failure,
not an established simulator-only limitation.

GUS-RV-002 source: `Sources/Services/OfflineDownloadStore.swift:879–885`,
`Resources/PrivacyInfo.xcprivacy`. Apple's approved reasons distinguish storage
display from an observable low-space refusal.
[Apple required-reason reference](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

## Native journey / design / accessibility evidence

1. **Book detail → Read reachable:** fresh iPhone baseline passes its control/reachability
   assertions. [Detail actions](evidence/runtime/iphone/book-large-actions.png) fit the
   viewport; decorative missing art does not expand the hero.
2. **Audio → landscape → Done → Now Playing → reopen → Stop:** all assertions pass.
   [Landscape](evidence/runtime/iphone/audio-landscape.png) has reachable Done/Stop and
   bounded art/transport controls. This supports presentation continuity, not physical
   audio-output or interruption acceptance.
3. **Connect → scroll → Refresh:** minimum 44-point hit bounds pass.
   [Current screen](evidence/runtime/iphone/connect-standard.png) preserves heading,
   labels and explanatory text. The targeted XCTest audit records one unlocated contrast
   issue and a text-field clipping warning. They are unresolved audit candidates until
   element-specific and largest-text checks establish disposition. Disabled-button
   contrast is evaluated separately from enabled controls; no blanket suppression is
   acceptable in the maintained suite.
4. **Show More → synopsis → Done:** passes. The
   [synopsis capture](evidence/runtime/iphone/full-synopsis.png) shows the entire supplied
   synopsis and a truncated title (GUS-RV-009).
5. **Watch Remote → Browse → Music → album:** fails as GUS-RV-001. Decorative row art is
   excluded from accessibility, but framework graph churn prevents reliable interaction.
6. **iPad / TV / Vision:** fresh build and runtime collection are continued in the final
   evidence matrix. Earlier screenshots are retained as historical comparison, never
   relabeled as proof of this execution. TV's complete-checking build passes.

The first iPhone layout collection was interrupted by an external native capture
request timing out during the Watch hang. That is a harness failure, not proof of
navigation loss. The failed run is retained, and the layout audit is repeated using
XCTest screenshot attachments. Separate builds must not share DerivedData concurrently;
an initial Vision build hit the build-database lock and was restarted after TV completed.

Design review uses the real native app, its existing brand, semantic system typography,
adaptive grids and native navigation/presentation. Glass remains scoped to controls;
artwork geometry belongs to its tile. No Figma redesign or web reproduction substitutes
for native acceptance. Contrast samples and screen audits cannot establish all backdrop,
focus, appearance or assistive-technology states.

## Original findings and both addenda

All GUS-UI-001–024 remain traceable through the
[remediation report](../2026-10-10-ui-remediation/REPORT.md). This audit retains its
implementation mapping and tests rather than inventing new versions of those IDs.

| Original IDs | Retest basis and remaining scope |
|---|---|
| 001, 003, 005 | Fresh audio rotation/close/reopen assertions; final phone/iPad/TV suites extend this. Physical paused streamed/downloaded video and live window resizing remain separate. |
| 002, 004, 011, 012–014, 017 | Existing cancellation, stale-response, failure and mutation regressions are included in the final unit matrix; new cancellation re-entry coverage is required for RV-008. |
| 006 | Existing raw-offset/restricted-page continuation and empty-page termination tests; final candidate must rerun them. |
| 007–010, 018–023 | Fresh book/Connect/synopsis/audio captures plus final detail/appearance/text matrix. RV-009 is title polish; unresolved automated contrast/clipping candidates stay visible. |
| 015–016 | Missing-art behavior and opened-photo merge/deduplication have deterministic tests; final photo journey is scoped separately. |
| 024 | TV full-screen detail / Menu / focus journey in maintained native suite. |

## App Review / developer-policy applicability

| Guideline / capability | Source-supported assessment | Acceptance still required |
|---|---|---|
| 2.1 completeness, 2.4 compatibility | Native media, download and reader features exist; Watch currently fails a core journey. | Resolve RV-001; final builds/tests/archives; reviewer-accessible demo server. |
| 2.3 metadata, 4.2 functionality | Listing must state user-provided Jellyfin requirement; shipped features are substantive. | Accurate platform/CarPlay claims, rights-cleared current screenshots, final metadata review. |
| 2.5.1 public APIs | Apple native frameworks + pinned Jellyfin and iOS Readium; compiler/platform guards inspected. | Final release binary/resource inventory; Apple upload validation. |
| 2.5.4 background behavior | Background audio and URLSession are linked to user-initiated playback/downloads; remote polling is frontmost-owned. | Physical background/relaunch, interruption, thermal/battery tests; measured Release performance. |
| 4.8 authentication | User-selected self-hosted server accounts; no app-operated identity service/social login. | Review notes explain authentication; no absolute promise of App Review approval. |
| 5.1 privacy/security | Tokens in Keychain; app-account scoped local files; SharePlay has metadata, not tokens; Watch uses Apple's channel. | RV-002/RV-007; dependency/privacy bundle inventory; portal privacy answers match actual data flows. |
| 5.2 IP | Developer distributes no media; demo rights/license inventory retained. | Review screenshot/publication contents and server availability. |
| Top Shelf | Credential-free JSON snapshot can serve unauthenticated artwork URLs; fallback has static links. | Signed App Group behavior on Apple TV; correct docs. |
| CarPlay / Declared Age Range | CarPlay grant is pending and unwired; age-range mapping has fallback/manual control. | Entitlement grants, signed execution and accurate store claims. |
| HIG accessibility/materials | Native semantic controls, explicit dismissal, adaptive layouts and reduced-effect handling exist. | Current-screen audits, VoiceOver/rotor/speech, Switch Control, keyboard/remote/Crown/spatial input. |

Required-reason inventory: app-owned UserDefaults → `CA92.1`; capacity queries →
`E174.1` needed. App code does not directly call the listed boot-time, timestamp or
active-keyboard APIs in the static inventory. Dependency and actual bundle manifests
are inspected separately; that source scan is not a binary attestation.

## Unavailable / incomplete acceptance

The paired physical iPhone is currently unavailable. Physical TVs are paired/available,
but a signed installation has not been performed by this local unsigned audit. Minimum
deployment OS runtimes are absent. Native Mac interaction, spatial input, VoiceOver,
Switch Control, audible output, real tuner service, background transfer relaunch,
interruption and minimum-OS acceptance require actual execution. App Store Connect
key/signing/Cloud/TestFlight checks remain separate; missing credentials do not prevent
local validation or commits. No such gate is marked passed by source inference.

## Remediation and final validation

Implementation starts after this initial audit record. Fix High findings first, then
compiler/recovery/privacy/automation/documentation issues. Record final source hashes,
maintained UI results, per-screen audit dispositions, performance/sanitizer scope,
six platform builds, four unit platforms and four unsigned Release archives in
`VALIDATION.md`. Validate a materialized staged candidate without ignored local config.
Commit every safe existing/new app, wiki and website change only when available gates
pass and no verified High core defect remains. Do not push or submit.

Sources checked October 10, 2026:
[HIG](https://developer.apple.com/design/human-interface-guidelines/),
[App Review](https://developer.apple.com/app-store/review/guidelines/),
[Swift migration](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/),
[automated accessibility](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app),
[Xcode 27 runner label](https://github.blog/changelog/2026-07-16-xcode-27-runner-image-now-in-public-preview/),
[installed runner tools](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md).

## Additional finding from the candidate retest

**GUS-RV-010 — Medium, verified runtime diagnostic:** Xcode 27's iOS unit run emitted
AVAudioSession warnings about synchronous activation/deactivation and category changes
on the main thread. Installed AVFAudio headers introduce asynchronous activation and
deactivation for iOS/tvOS/visionOS 27; Watch activation already exists on Watch 5.
The warning and API inventory led to a serialized audio-session queue shared by the
audio/video owners. Category changes and legacy calls run off MainActor; OS 27 uses
native completion APIs. A regression checks delayed activation → dismissal → replacement
ordering, and playback generations reject cancelled/obsolete preparation after activation.
The final matrix must retest this change, including the older-runtime fallback.

[Apple activation API](https://developer.apple.com/documentation/avfaudio/avaudiosession/activate(options:completionhandler:)),
[Apple deactivation API](https://developer.apple.com/documentation/avfaudio/avaudiosession/deactivate(options:completionhandler:)).

**GUS-RV-011 — High, verified primary-action reachability:** On iPhone 17e/iOS 27,
Read becomes unreachable after detail rotation or EPUB → rotate → Done. The stronger
retest waits for real EPUB text and identifies the reader's Done button explicitly;
it still reproduces. Initial interpretation of an underlying Home accessibility entry
as navigation loss was corrected after inspecting the native PNG (see correction below).
The book detail sheet remains present, but its primary actions are absent from the
visible landscape area. Resolve this defect before committing the final candidate.

**GUS-RV-012 — Medium, verified accessibility geometry:** The album's Play button
measures 34.33 points high at AX5, including after bounded scrolling. Movie Play passes;
the album uses a separate fixed-size button without the large-control treatment or a
minimum label height. Give album Play/Shuffle native large controls with >=44-point
label bounds, then retest standard/AX5 and narrow layouts.

### RV-011 evidence correction and implementation

Inspection of the native `book-reader-dismissed` PNG from the second retest shows
the Dracula detail sheet still present. The earlier Home interpretation used an
underlying accessibility-tree entry and was incorrect. The verified High finding is
loss of reachable Read/Share actions after rotation, not proven navigation loss.
The primary book actions were embedded in the hero's secondary lazy grid. Moving
them above that grid keeps them realized and gives them primary-action placement.
The strengthened test still requires real EPUB text, the exact reader Done button,
and a reachable Read action afterward. Stable root/Now Playing modifier identity
and explicit player-owner dismissal are retained to prevent presentation teardown
when size classes change. The final native retest determines acceptance.

**GUS-RV-013 — Medium, verified rendered metadata contrast:** The reduced-effects
movie capture places opaque `#4F7C82` rating text over bright artwork. A pixel sample
from the rating region confirms the foreground; nearby background pixels are around
`#80807A`, producing approximately 1:1 contrast rather than legible small text.
The hero scrim alone cannot guarantee contrast against arbitrary artwork. Give the
metadata row a dark bounded surface, use white rating text, and run a strict native
contrast audit on the rated, long-title movie. The superseded final-build attempt was
intentionally interrupted for this correction; it is not a product compile failure.
Final source hashes and available gates must be refreshed.

### RV-013 retest and native audit dispositions

The final hero uses opaque white title/metadata/synopsis text on a bounded opaque black
surface, preserving artwork outside the text block. The rated movie's strict native
contrast/hit-region/description audit passes in the focused retest. Xcode 27 produces
two identified native-glass contrast false positives: `ContentLink.detailDone` and
`Detail.play`. Their exported element pixels show approximately 20:1 black-on-white
and over 6:1 white-on-teal contrast. The maintained audit accepts only these exact
identified, enabled, hittable controls after a fresh central-label pixel sample is
>=4.5:1. Unknown issues and all other contrast/geometry/description issues still fail.
This is a local rendered-color guard, not an all-screen or assistive-technology claim.
See `evidence/runtime/contrast/` for original rating failure and native element samples.
The complete matrix, including dark/largest text, remains required for final acceptance.

**GUS-RV-014 — Medium, verified test-configuration defect:** Final screenshot review
showed the supposed AX5 captures using ordinary text, and the supposed RTL captures
retaining the ordinary layout. The literal accessibility category string was invalid;
`en-XA` and an unsupported Arabic app language did not prove Apple's localization
stress modes were active. Use UIKit's exported accessibility category `rawValue`,
assert rendered headline growth, and use Apple's documented `NSDoubleLocalizedStrings`,
`AppleTextDirection` and `NSForceRightToLeftWritingDirection` switches. Assert a doubled
Connect label and mirrored native Done position. Earlier results remain useful for
standard layout, not largest-text or RTL acceptance. Rerun the affected maintained
suites and appearance matrix with the corrected test source.

[Apple localization testing](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPInternational/TestingYourInternationalApp/TestingYourInternationalApp.html),
[UIKit content categories](https://developer.apple.com/documentation/uikit/uicontentsizecategory).

**GUS-RV-015 — Medium, verified native audit false positive:** The final iPad strict
movie audit flags the Studios heading. Its native element PNG contains black text on
a light surface; the exact pixel evidence is retained in
`evidence/runtime/contrast/native-studios-false-positive.*`. Genre/studio headings now
have stable identifiers. Only the identified, hittable Studios heading can receive a
contrast disposition, and only when a fresh local rendered-label sample is >=4.5:1.
Other headings, missing/unlocated issues and other audit types still fail. The earlier
iPad run remains a failed audit, not a passed final matrix.

The next iPad issue identifies Cast & Crew below the form sheet's visible clip. Its
native `Element Screenshot` contains only the underlying Home background, with no
Cast & Crew text (`native-cast-offscreen-sample.png`). The retest uses bounded scrolling
to reveal an exact unique heading before a fresh pixel measurement. The only additional
qualifying labels are immutable primary-style section headings on the plain detail
surface: Cast & Crew, About, Genres and Recommended. Each still requires the exact
static-text label, a unique node, actual hittability and a fresh >=4.5:1 sample.
Unlocated, duplicate, unreachable or failing-color cases and all other types fail.
This addresses stale/clipped form-sheet sampling, not a broad contrast waiver.

### RV-015 final disposition: SDK check blocked

Repeated strict iPad attempts continue sampling clipped/offscreen studio/cast/section
text against the underlying Home surface. The native element evidence establishes the
sampling fault; expanding classifications to every label would weaken the audit. The
final maintained iPad test therefore requests native hit-region and sufficient-description
audits and independently measures visible enabled/hittable Done and Play controls.
**Native iPad form-sheet contrast auditing remains blocked by the observed Xcode 27
sampler; it is not a passed check or an accessibility sign-off.** Full iPad contrast and
assistive-device acceptance remain release gates. The iPhone still requests the strict
contrast/hit-region/description audit and measures only its two identified native
control false positives. All unknown issues fail. Measurements now occur after the
native audit to keep reveal/scroll operations from moving its remaining cached samples.
The earlier Studios/header/studio-chip classifier experiments are superseded and are
not part of the final maintained exception set.

## Additional finding from the cross-platform final retest

**GUS-RV-016 — High, verified Vision audio return regression:** The final Vision
audio journey loads the track with Pause visible, taps Done, then returns to Home
without the persistent Now Playing control. Native XCTest hierarchy and recorded
screen frames confirm the control is absent; this is not an identifier-only failure.
The recently added stable `ZStack` presentation anchor is needed for iOS width changes,
but was applied to every platform. Preserve the native root hierarchy elsewhere and
retest loaded audio → Done → Now Playing → reopen → Stop on Vision before accepting
the candidate. Its previous passing result cannot substitute for this changed source.

XCUIScreen screenshots on this Vision runtime are 1×1 placeholders; native XCTest
screen recordings contain actual 3840×2160 frames. Do not label those placeholder
attachments as visual evidence. Retain native recorded frames with their source and
time offset for the final Vision review.

### RV-016 cause correction and remediation

Removing the cross-platform wrapper alone does **not** fix the failed Vision journey;
the initial attribution was unproven. The failure survives with the original root
hierarchy. The return control uses automatic toolbar placement beside the searchable
Home navigation bar and is absent in both the hierarchy and native recording.
Keep the presentation wrapper confined to iOS, and put Vision's persistent return
control in its native, bounded bottom ornament. This gives it an explicit platform
placement without displacing the search field. A complete focused retest must prove
loaded audio → Done → return control → reopen → Stop.

[Apple bottom-ornament placement](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/bottomornament)
is verified in the installed Xcode 27 SwiftUI interface for Vision.

**GUS-RV-017 — Medium, verified launch-tooling path mismatch:** The generated project
and `Config/Shared.xcconfig` produce `A Playa Named Gus.app`. The launch baseline helper
and an install example incorrectly use `Gus.app`. This was caught against the actual
build products before collecting accepted performance numbers. Correct the quoted
default path and exercise the corrected helper against the validated app. Keep the
compiled candidate frozen while its build/test phases run; this tool-only correction
requires fresh static checks and actual launch measurements, not relabeling old results.


**GUS-RV-018 — Medium, verified Release packaging failure:** All four candidate-10
unsigned archives built, but binary inspection found `--gus-skip-session-restore` in
every main app executable. The demo/route/preview flags were absent. `GusApp.init`
parsed the skip-session flag outside its `#if DEBUG` block. Confine that argument
parsing to Debug and set Release session restoration explicitly to true, then rerun
packaging inspection. The earlier archive-build passes are not acceptance of their
contents. No credential bypass or authentication bypass was observed; this flag only
skips automatic session restoration. Debug fixture behavior remains unchanged.


## Final local disposition

All six builds, four 282-test unit suites, 29 maintained native UI executions,
22 expanded UI executions, eight state/recovery tests and four unsigned Release
archives passed within their recorded candidate scope. The final Release-only fix has fresh
archives/static checks and an identical-active-DEBUG-token proof for retained Debug
build/unit/UI results; new expanded/sanitizer tests exercise the final source. Thread and Address Sanitizers each
passed the 282-test shared macOS corpus. Three Release performance tests passed.
Native captures were inspected, and every retained result has a scoped disposition in
[VALIDATION.md](VALIDATION.md). Earlier failed experiments remain historical evidence.

| Finding | Final disposition |
|---|---|
| RV-001 | Fixed: stable value navigation and independent Watch page stacks. Actual album → tracks → audio Pause passes on 40 mm and 46 mm simulators. Physical output/Crown/battery remain open. |
| RV-002 | Fixed: E174.1 low-space refusal reason; app and embedded Watch archive manifests verified. Portal privacy answers remain open. |
| RV-003 | Partial migration: complete checking everywhere; Watch/Top Shelf/tvOS/visionOS app Swift 6. Five Readium/Declared Age Range diagnostics remain explicit iOS/macOS migration boundaries. |
| RV-004 | Fixed: complete source/test/API-tool SwiftFormat checks pass. |
| RV-005 | Fixed within local scope: maintained authenticated suites and an external reproducible state matrix; assistive-device acceptance remains open. |
| RV-006 | Fixed: Xcode 27 project/CI, truthful readiness/Top Shelf/CarPlay docs, no wiki sidebar. Hosted workflow/signing remains unverified. |
| RV-007 | Fixed: user/server/error/title payloads private; staged evidence receives key/token/artifact pattern checks. |
| RV-008 | Fixed: cancellation/re-entry and obsolete result guards with unit regressions. |
| RV-009 | Fixed: semantic wrapping synopsis heading; actual largest-text appearance retest passed. |
| RV-010 | Fixed: ordered off-main audio-session work with native async OS 27 APIs; ordering regression and iOS 26.5 fallback passed. |
| RV-011 | Fixed: eagerly realized book primary actions survive rotation and reader Done. Full chapter/PDF/device reading remains open. |
| RV-012 | Fixed: native large album actions with minimum 44-point label; verified AX5 retest passed. |
| RV-013 | Fixed: bounded opaque white-on-black hero text; strict iPhone audit and narrow fresh native-control pixel guards pass. |
| RV-014 | Fixed: exported UIKit AX5 category plus rendered-growth assertion, native doubled-string assertion and RTL Done-position assertion; corrected suites and appearance matrix pass. |
| RV-018 | Fixed: session-restoration argument parsing is Debug-only; all four fresh Release archive executables exclude it and always restore sessions. |
| RV-017 | Fixed: quoted launch-helper default and install example match the observed product name; fresh static checks and five actual launch runs validate the tool-only correction. |
| RV-016 | Fixed: Vision uses a bounded native bottom ornament; loaded audio → Done → Now Playing → reopen → Stop passes. Synchronous native simulator IO captures replace unusable 1×1 screenshots; failed-run recording frames retain the regression history. |
| RV-015 | **Blocked SDK contrast check**, not passed: iPad native form-sheet samples offscreen/clipped text against Home. Geometry/description and visible primary-control pixel checks pass; full iPad contrast/device acceptance remains required. No header/studio/cast waiver survives in the final test. |

No verified High product finding remains in the locally exercised journeys. This does
not close missing minimum-OS, physical/assistive input, media variants, native Mac,
SDK migration, portal signing, upload or TestFlight installation gates. Nothing was
pushed, uploaded, submitted or sent to testers. Original review artifacts, including
all screenshots and both addenda, remain byte-identical.
