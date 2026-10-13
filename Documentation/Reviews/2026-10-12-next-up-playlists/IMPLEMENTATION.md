# Unified Next Up and Jellyfin video playlists

Approved scope: one Next Up rail/list ordered by genuine recent activity, ordered Jellyfin movie/episode playlists with repeated entries and persistent playback cursor, and private iCloud sync across independently authenticated devices. External provider integration and public sharing are deferred.

Work takes place on feature/unified-next-up-playlists in the current checkout; existing pipeline evidence and Disney research/plan files are unrelated and preserved.

## Ledger

- Issue status: #8/#15/#16 updated on GitHub with merged implementation and outstanding runtime acceptance. No issue qualifies for evidence-backed closure yet.
- Baseline: 305 macOS Swift Testing cases in 51 suites passed.
- Task 1: unified Next Up derivation, timestamps, Home and Top Shelf implemented and locally verified.
- Task 2: playlist domain, durable CRUD, playback and navigation implemented and locally verified.
- Task 3: CloudKit private synchronization, conflict handling and account partitioning implemented; signed service acceptance remains blocked.
- Acceptance: local matrix and simulator UI passed; physical/iCloud signing/device validation remains open.

## Implementation rulings

- Use the server-reported ID and user ID for cross-device Jellyfin account matching; leave existing AccountScope.storageKey unchanged.
- Recent activity dates describe playback or explicit list intent, never refresh time. Undated legacy entries retain their original order.
- Existing saved-media recovery remains the authority for reimported/missing media; never auto-match by title alone.
- User selected a feature branch in this checkout instead of a worktree. The independent Home and storage/sync tasks use subagents under the subagent-driven-development skill; integration is owned by the parent.

## Verification and review progress

- Baseline macOS: 305 Swift Testing cases in 51 suites passed before source changes.
- RED: new playlist sequencing and domain references failed to compile before implementation (`/tmp/gus-playlist-red.log`).
- First integrated compile passed; macOS suite reached 324 tests, with six expectation failures exclusively from existing navigation tests omitting the new Playlists destination. Legacy navigation assertions now filter the added section; separate tests verify it remains required and window payloads retain distinct playlist entry identity.
- Storage/sync focused harness: 15 tests passed against real domain/store/transport sources and a minimal matching MediaReference model; not a substitute for the full app test matrix.
- Website source: npm test passed (three static checks plus production Eleventy build).
- Review repaired saved-intent feedback/resurrection risks, current-entry deletion cursor behavior, deletion during asynchronous preparation, restricted-entry recovery and accessibility dismissal checkpoint ordering. Fresh review found no remaining findings; integrated tests passed.
- Provisioned macOS build failed because the existing team profile lacks iCloud capability/container. Local tests run unsigned; signed iCloud/device/production acceptance remains open.

Ruling: existing cloud saved-intent UUIDs remain stable through reference replacement; deterministic canonical identity is used only for initial intent creation/import. Metadata/rebind writes cannot restamp membership, preventing an offline refresh from undoing a concurrent remove.
Ruling: CKSyncEngine requires silent remote notifications; add the native APNs capability/background mode alongside CloudKit. This adds no user-facing event notifications from issue #12.

## Earlier local matrix (Xcode 27.1 RC)

- iPhone iOS 27: 344 Swift Testing cases in 59 suites passed; native XCTest measurements also passed.
- macOS: 341 Swift Testing cases in 58 suites passed.
- iPad iOS 27: 344 Swift Testing cases in 59 suites passed.
- Generic tvOS, visionOS and watchOS simulator builds passed. Compatible OS 27 runtimes for their unit/UI execution are unavailable locally; build success is not runtime acceptance.
- Fresh code review confirmed the original five findings and the later external-cloud-reset finding are resolved. External resets retain durable-ID local removal tombstones rather than resurrecting cached queue entries.
- Final series-activity inheritance, status copy and native name editor passed the final checks below.
- Companion docs: wiki `b7b9e46`, website `ee1606e` on matching local feature branches. Only task-owned fragments were staged; unrelated wiki/support edits remain uncommitted. Website npm test passed.

## Native UI acceptance

- The demo playlist test passed in 150.809 seconds: two distinct copies of the 29-second Sneeze film followed by the 31-second May Irwin film played through AVKit to the playlist's actual natural completion state. No manual completion or Skip was used.
- Rename regression reproduced twice: the field displayed the new value but the native alert action persisted the previous name. Reading a projected binding in the alert did not resolve it. Creation/rename now use a native SwiftUI Form sheet with editor-owned state.
- The resulting create → rename → terminate/relaunch → confirm delete test passed in 72.415 seconds. [Inspected edited name](evidence/rename-native-form.png). The first two failed runs were stopped during prolonged Xcode diagnostics collection; their unfinished result bundles are not treated as successful evidence.
- These are simulator editing/playback checks, not physical iCloud, account/rating, VoiceOver or airplane-mode acceptance for issues #8/#15/#16.

## Final checks and remaining gates

- Final macOS suite after #20: 347 Swift Testing cases/58 suites passed (10.212s).
- Final iPhone suite after #20: 350 Swift Testing cases/59 suites passed (10.125s).
- Final tvOS, visionOS and watchOS builds passed after the native Form and #20 fixes. iPad passed the preceding shared-code matrix; no signed device acceptance is inferred.
- SwiftFormat lint, String Catalog JSON, generated project/scheme/pin validation, and diff whitespace checks pass.
- iCloud provisioning remains blocked: Xcode 27.1 RC reports no account; automatic signing with the configured team key reports authentication failure. A separate App Store Connect GET succeeds, so read access is not proof of provisioning access.
- Sign in to Xcode 27.1 RC Accounts with the developer team or supply working provisioning authentication; enable CloudKit plus silent push and associate `iCloud.dev.ericslutz.gus`; refresh development/distribution profiles. Then verify signed iPhone → Apple TV/Mac sync, offline edits/conflicts/cursor continuation, iCloud/Jellyfin account switching, production schema, and TestFlight signing separately.
- Physical offline/background/VoiceOver gates for #15/#16 and live two-participant SharePlay for #8 remain open. No issue was closed on incomplete acceptance evidence.

## Post-merge reference recovery findings (#20)

Issue #20 was opened during implementation and directly affects playlist/Next Up recovery. Its three findings are fixed on this branch: old locators require a positive matching saved external identity; manual replacement and asynchronous refresh stage local progress transfer only after their version-checked update commits; adopting a new detail ID reloads related content and seasons/episodes, rejecting late responses from prior loads.

Regression verification used existing recovery suites: with these fixes removed, the 26 tests in three suites failed 11 assertions across all three original behaviors; with fixes restored, all 26 passed. Progress tests use an injected temporary store. No actual provider progress or downloaded file is altered by these tests.

CI compile jobs now explicitly use unsigned builds so compilation is independent of private capability profiles. Mac unit tests retain their existing isolated sandbox entitlement host. Xcode Cloud and physical acceptance remain responsible for provisioned release checks. #20 remains open until the fixes are merged.

A fresh read-only review of the #20 fixes and CI signing separation found no remaining findings.

Final same-code UI rerun passed both cases: ordered duplicate-entry natural completion (155.387s) and create/rename/relaunch/delete (51.623s), with no failures. Inspected screenshots: [entries](evidence/playlist-duplicate-entries.png), [natural completion](evidence/playlist-natural-completion.png), and [native name form](evidence/rename-native-form.png). All final platform checks exited zero; counts and timings are retained in [the local matrix](evidence/local-matrix.json).

## tvOS CI follow-up

[Initial PR CI](https://github.com/eslutz/A-Playa-Named-Gus/actions/runs/38350387524/job/115141212262) passed 12/13 jobs, but tvOS failed two assertions in `NavigationPreferencesTests.hideAndReorder`. The test's hardcoded move offset omitted the newly required Playlists section on platforms without Downloaded, leaving Music after Libraries. The production move correctly followed that requested offset.

The test now derives the offset between Music and Libraries from the current visible movable sections; its exact expected order assertions remain unchanged. No production source changed. The seven-test navigation suite passed on macOS (Xcode 27.1 RC); SwiftFormat and diff checks passed. The CI log establishes the original tvOS failure. Compatible tvOS 27 runtime execution is unavailable locally, so actual tvOS verification runs on the updated PR's CI.
