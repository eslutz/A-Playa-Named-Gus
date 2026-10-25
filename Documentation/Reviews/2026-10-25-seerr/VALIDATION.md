# Seerr integration validation — October 25, 2026

Native Seerr 3 discovery, authentication, movie/season requests and recovery, personal history, manager review, and supported issue/blocklist/preferences are implemented and locally qualified. **GitHub CI and Cloud/TestFlight distribution remain pending.**

## Candidate and evidence

The candidate is isolated on `codex/seerr-integration`, based on protected-main `f53eaf37`; the original unfinished design checkout is preserved. Xcode 27.1 (`27A9275`), Apple Silicon, saved package pins and the repository warning gate were used. [Initial local matrix fingerprints](evidence/final-source-hashes.json) identify the baseline qualified below. Subsequent automation-only CI corrections are documented separately.

All Swift runtime and Swift test sources match across the baseline final build, unit, history UI, archive and static matrices. After runtime testing, two unchanged English navigation labels (`Integrations`, `Seerr`) were added to the string catalog. Final builds, archives and static checks include that resource completion; [the exact delta](evidence/resource-only-delta.json) and [runtime fingerprints](evidence/runtime-source-hashes.json) preserve this distinction.

## Local qualification

| Check | Result |
|---|---|
| Debug builds | Six passed: iPhone, iPad, macOS, tvOS, visionOS, Watch. [Commands/results](evidence/final-builds-results.json). |
| Unit tests | iOS 528, macOS 525, tvOS 526, visionOS 525: **2,104 passed**, zero failures/skips/expected failures. Counts repeat shared tests across platforms. [Results](evidence/final-tests-results.json). |
| Authenticated UI | Six baseline flows passed across iPhone/iPad before the narrow history-refresh fix: connect/restore/request/history/cancel, uncertain-response readback with one POST, manager approval. [Results](evidence/baseline-focused-ui-results.json). |
| Final history UI | Four additional flows passed on iPhone/iPad, verifying cancellation empties My Requests and approval removes the Pending queue row. [Results](evidence/final-history-ui-results.json). |
| Release archives | All four passed: iOS (embedded Watch), tvOS (Top Shelf), visionOS and macOS. Unsigned local qualification. [Results](evidence/final-archives-results.json), [bundle/privacy/debug-route inventory](evidence/final-archive-inventory.json). |
| Static checks | Eight passed: format, API-tool format, bootstrap regressions, project/pins, warning-gate regressions, offline ASC self-test, whitespace and YAML. [Results](evidence/final-static-results.json). |

Every accepted build/test/archive lane has an empty build-diagnostic list. The candidate adds no runtime dependencies. Companion website tests passed 3/3; changed wiki links and whitespace checks passed locally. Temporary fixture services were stopped after UI testing.

Reviewed synthetic captures: [iPhone Discover](captures/iphone-discover.png), [iPad Discover](captures/ipad-discover.png), [uncertain response](captures/iphone-uncertain-request.png), [canceled history](captures/iphone-cancellation-history.png), [approved Pending queue](captures/ipad-pending-history.png). The fixture intentionally uses placeholder artwork.

## PR review follow-up

The [two PR comment fixes](PR-COMMENT-FIXES.md) add format-independent request-review entry and submitted preference snapshots. Their full local iOS suite passes 530 tests without build diagnostics. Earlier broad matrix results remain baseline evidence; the final corrected head requires fresh hosted checks.

## Release gates and limits

The user approved publication and [PR #34](https://github.com/eslutz/A-Playa-Named-Gus/pull/34) is open. An embedded Watch metadata warning in the first hosted iOS build prompted an [automation-only layout correction](CI-WATCH-METADATA.md); fresh checks on that corrected head remain required. Protected-main merge and the manual **Gus Internal TestFlight** workflow remain outstanding. Distribution requires the intended merged source, raw warning-policy review, successful signed exports/uploads, processing and all four internal beta group associations. **No new TestFlight build is claimed.**

Tests used synthetic loopback Seerr/Jellyfin fixtures. Live Seerr, exact OS 26.0 runtime, physical-device, VoiceOver/assistive and remaining platform GUI acceptance are unverified. Watch has no Discover destination.

Raw logs and result bundles remain under `/tmp/gus-seerr-validation/`. Compact evidence and screenshots are preserved here; [SHA-256 hashes](evidence/sha256.json) cover those saved files. Older evidence remains provenance, not the final qualification basis.
