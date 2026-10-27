# Internal TestFlight release

The internal release is not yet available to the tester. The native Icon Composer source at `f1a387f` passed Cloud Build 8 without issues, but its GitHub matrix passed 12/13: the iPad audio completion test received no native end notification within its wait. The icon/EPUB tests passed. No failed attempt is counted as acceptance.

The October 12 policy now requires PRs into protected main. GitHub runs the full PR matrix; the saved main-only Cloud workflow has four required unit-test actions (six device types) plus four internal-only archives. All required actions must pass before group post-actions distribute. The separate compile-only workflow is deleted. [Policy and saved proof](pipeline-policy.md).


Historical Xcode Cloud Build 4 (`33eae093-33a9-4dd9-a12e-b8b9a306054a`) completed **FAILED** at `2026-10-12T03:10:29Z` for exact source `64505d9dfd337c90f390c7c66503912eac252d3f`. iOS export and Mac App Store Connect preparation failed; tvOS and visionOS uploads are valid, but all four distribution post-actions were skipped and `Gus Internal` has no builds. Group access, invitation delivery, and installation remain unaccepted. Final release summary.

## Preceding candidate prerequisite

Current-source [GitHub run 38194318738, attempt 2](https://github.com/eslutz/A-Playa-Named-Gus/actions/runs/38194318738/attempts/2) has **13/13 successful checks**: six builds, five unit lanes, lint, and docs. Each accepted unit lane passed 288 Swift Testing cases in 49 suites plus three distinct XCTest performance measurements. Only iPad reran; the other 12 successes were carried forward from attempt 1. Its unchanged-source retry passed actual native completion/replay and deletion/no-stream cases; the first iPad completion failure remains recorded with an unresolved cause. Matrix, accepted lane counts, first failure.

Cloud Build 3 independently passed all four iOS/macOS/tvOS/visionOS **BUILD** actions at the same source on Xcode 27.1 RC, with zero errors and seven unchanged warnings. This satisfied the user's all-pipelines-pass prerequisite for proceeding with internal distribution. Cloud result, results image.

## Saved release configuration

| Setting | Verified configuration |
|---|---|
| App | Gus, App Store Connect ID `6778382140`; marketing version `1.0.0` |
| Workflow | `Gus Internal TestFlight`, ID `559f9de9-14d5-4b85-a091-8c3598fa346f` |
| Start | Manual start on exact branch `main`; no automated triggers |
| Toolchain | Xcode 27.1 RC (`27A9275`), macOS Golden Gate 27.2 beta 2 (`26B5091g`) |
| Actions | Four required Release ARCHIVE actions: iOS, macOS, tvOS, visionOS |
| Distribution preparation | TestFlight (Internal Testing Only) for each archive |
| Post-actions | Four platform-specific internal TestFlight post-actions targeting `Gus Internal` |
| Group | `Gus Internal`, ID `cc95594c-6adf-4f5b-82b1-85cb92a8165f` |

The saved native workflow exposes all four archive preparations and group post-actions. The API independently confirms four required `ARCHIVE` actions with `INTERNAL_ONLY` preparation, exact `main` manual start, absent automated start conditions, and the selected toolchain; its workflow resource omits post-actions, so the saved UI supplies that configuration proof. Configuration image, saved UI tree, API snapshot. The persisted English beta localization has a description, feedback email, marketing URL, and privacy-policy URL; the presence-only API proof excludes their values. Beta information. Watch is embedded in the iOS archive and Top Shelf in tvOS; these are not separate archive actions.

Read-only API verification at `2026-10-12T02:51:55Z` confirmed an internal group and exactly one tester selected through the native picker from the existing eligible App Store Connect account. The tester was `NOT_INVITED` and the group had no builds before archive execution. Membership does not establish invitation delivery, install access, or installation. Group membership proof.

## Build 4 result

The API issue ledger at `2026-10-12T03:06:12Z` reports iOS `ExportArchiveStep` failure for App Store distribution, with additional development/ad-hoc export warnings. An iOS `.xcarchive` artifact exists (51,273,230 bytes); this proves archive production, not export or upload success. The public error directs inspection of the logs artifact and does not establish the underlying cause. iOS issues, archive/artifact metadata.

The run was manually queued from `main` at 22:59 EDT on October 11, 2026. The final `03:12:28Z` API snapshot has `executionProgress=COMPLETE` and `completionStatus=FAILED`. Two required archive actions succeeded and two failed. Run, actions.

| Platform | Archive action | Errors / warnings | Upload processing / internal beta readiness |
|---|---|---|---|
| iOS | Failed at App Store export after archive production | 1 / 8 | No accepted upload |
| macOS | Failed preparing build for App Store Connect | 1 / 2 | No accepted upload |
| tvOS | Succeeded | 0 / 0 | Version `1.0.0`, build `4`: `VALID`, `READY_FOR_BETA_TESTING`, `INTERNAL_ONLY` |
| visionOS | Succeeded | 0 / 0 | Version `1.0.0`, build `4`: `VALID`, `READY_FOR_BETA_TESTING`, `INTERNAL_ONLY` |

Mac's error is `PrepareBuildForAppStoreConnect`; its issue ledger also warns that no app category is set and records the existing Declared Age Range concurrency warning. The generic preparation error alone does not identify the cause. Mac issues. iOS retains six existing compile warnings plus two export warnings; the error is the App Store export failure. Final action counts.

All four named TestFlight distribution post-actions are `SKIPPED`; their API `actionType=TEST` identifies distribution post-actions here, not executed unit tests. The uploaded tvOS/visionOS builds have empty beta-group relationships; the group has zero associated builds and its one tester remains `NOT_INVITED` in the final API snapshot. Upload readiness does not establish account access. Uploaded builds, group builds, tester state.

### Repair and retry preparation — October 12, 2026

The downloaded iOS export log identifies the missing prerequisite: automatic signing could not register `dev.ericslutz.gus.watchkitapp` and found no matching App Store provisioning profile for the embedded Watch bundle. The exact identifier was then registered through Apple's Developer UI. Independent API verification confirms `Gus Watch`, record `X7N8FKWCC6`, platform `UNIVERSAL`, team `QS3GC3CT43`; no optional capabilities were added. This accepts identifier registration, while a generated distribution profile and successful signed export remain unproven. Export diagnosis and sanitized log provenance, iOS excerpt, registration proof.

Mac's export log reports `EXPORT SUCCEEDED` before the later generic App Store Connect preparation failure. The available log bundle contains no detailed fatal validation code; the observed missing-category warning is not proven to be its cause. The [Info.plist repair](../../Resources/Info.plist) adds the Entertainment app category and copyright metadata; plist parsing and the shared-project check passed. This corrects the known metadata omission but does not establish resolution of the preparation failure. Mac export excerpt.

Build 4's failure and preceding `64505d9` CI/BUILD results remain historical evidence. Corrected-source CI, a new signed archive/export attempt, successful distribution post-actions, group build access, and invitation/install acceptance are still pending; no retry success is claimed.

## Pending acceptance and limits

Build 4's iOS export failure, Mac preparation failure, skipped post-actions, and absent group build associations prevent full release acceptance. The registered Watch identifier still requires a successful provisioned export; Mac's precise preparation failure remains unconfirmed. A successful Cloud workflow alone will not establish that the tester received access or installed and launched the app through TestFlight; those results require separate verification.

The completed phone flows used build 11. Later-source physical and full Mac UI acceptance, exact minimum-OS runtime execution, manual VoiceOver, and broader Duo video/navigation/sheet transitions remain open. Sampled Duo audio transitions cover the preceding app candidate and do not measure audible gaps or black-frame duration. Current build/unit success includes the later decorative-artwork repair but does not establish its manual VoiceOver or fresh Duo/physical runtime acceptance. See the [repair report](../Reviews/README.md) for scoped evidence and resource-cleanup limits.

## Warning repair gate

Cloud Build 6 passed all four required BUILD actions at `8d09dcc` with zero errors and warnings. The correction in `bd01514` changes only a regression-test URL conversion; app source remains identical. Its replacement GitHub CI run `38230709289` must pass before the signed release retry. [Warning repair evidence](build-warning-repairs.md). No new signed release is claimed by this compilation result.

## Historical release retry — Build 7

The corrected source `bd01514072a575cb5153f2729ab7c96ebbf573eb` passed GitHub CI `38230709289` **13/13**, including all five test lanes and the three new EPUB regressions on both iPhone and iPad. Cloud Build 6 passed all four required BUILD actions with zero issues; `bd01514` changes only a test URL conversion from that warning-free app source. This gate was verified immediately before starting the release.

Signed Cloud Build 7 (`7d7435a0-677a-4c25-b35b-209a24d53af6`) was manually started on exact `main` after the gate passed. Independent API verification confirms its source is `bd01514072a575cb5153f2729ab7c96ebbf573eb`. Its final action outcomes are recorded below. The pre-retry group baseline remains one tester, `NOT_INVITED`, and zero builds; availability is not claimed until the new uploads and group access are verified.

Build 7 finished FAILED at `2026-10-12T10:13:46.098Z`. All four platform App Store exports were produced; iOS main/Watch and tvOS main/Top Shelf signatures, matching versions and profiles are verified from the exports. Mac signed app/package inspection passed with its sandbox and approved network entitlements. Mac, tvOS and visionOS uploads processed as VALID/READY_FOR_BETA_TESTING. iOS failed the later generic PrepareBuildForAppStoreConnect step, and all group post-actions were skipped. The downloaded export logs prove EXPORT SUCCEEDED; their session-proxy store-configuration warning is not proven to be the later failure cause. Independent Apple validation subsequently identified the concrete icon rejections below. Run result.

Independent Apple validation of the exact signed Build 7 IPA returned `90396` (Watch icon alpha) and `90717` (Watch/iOS large icon alpha). The corrected default icons are published at `64b9de6`, with a native pixel comparison confirming zero changes in previously opaque artwork and a CI metadata guard. This establishes the concrete preparation rejection, replacing the earlier generic-error uncertainty. Build 7 used PNG catalogs. The missing editable source has since been recreated in native Icon Composer at `f1a387f`; [source](icon-composer-source.md). [Repair details](icon-upload-repair.md).
