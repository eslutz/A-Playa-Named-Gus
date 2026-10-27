# Xcode Cloud dependency onboarding diagnosis

**Current policy (October 12):** protected main requires PRs and all GitHub checks. The saved main-only Cloud release tests iPhone/iPad/Duo, Mac, TV and Vision before internal distribution. Native Icon Composer source is restored and Cloud Build 8 passed without issues; CI run 38242041231 retained one iPad native audio completion failure. Tester availability remains unconfirmed until the new gates pass. [Pipeline policy](pipeline-policy.md), [release status](internal-testflight-release.md).


Assessment date: **2026-10-11**. Initial Gus Cloud onboarding with package references
requires connections for public upstream packages and keeps **Next** disabled. This
was reproduced with Xcode 27.0 and 27.1 RC. A disposable local project without package
references subsequently completed onboarding against Gus's existing app and primary
repository. This bypasses the failing dependency-connection step; the internal Apple cause is
**not confirmed**. The complete repairs were published directly on `origin/main`;
Cloud Build 1 verified the source commit but stopped at a bootstrap identity comparison.
The repaired bootstrap and full pinned project passed all four required Cloud BUILD
actions in Build 2. Runtime and distribution acceptance remain separate.

## Observed failure and expected behavior

1. Open `A Playa Named Gus.xcodeproj` with the signed-in Apple Account.
2. Start **Integrate → Create Workflow** and select Gus's existing app record.
3. Continue to the repository/dependency connection step. The primary repository is
   connected, but upstream packages such as `apple/swift-collections` and `readium/Fuzi`
   require **Connect**.
4. Click **Connect**. Apple's browser flow asks to install/authorize access under the
   upstream organization. GitHub offers the user's own account/organizations, not
   administrator access to `apple` or `readium`.
5. Return to Xcode: dependencies remain unconnected and **Next** remains disabled.
   An approved wizard restart and retry in the other Xcode version did not resolve it.

Apple's [Making dependencies available to Xcode Cloud](https://developer.apple.com/documentation/xcode/making-dependencies-available-to-xcode-cloud)
says publicly accessible Swift packages and Git submodules require no separate
configuration. Its provider authorization process applies to private dependencies.
The observed permission requirement therefore appears to treat these public packages
as repositories needing private-access authorization. This is a diagnosis of the
visible behavior, not proof of a particular server or Xcode implementation defect.
Obtaining upstream organization administrator rights is not a valid recovery path.

## Verified local dependency graph

Gus declares **two direct packages** in `project.yml`: Jellyfin SDK (`from: 2.1.0`) and
Readium (`from: 3.9.0`). The shared project and committed `Package.resolved` contain
**16 unique resolved package identities**:

| Repository | Pinned version | Source |
|---|---|---|
| `jellyfin/jellyfin-sdk-swift` | 2.1.0 | Direct |
| `readium/swift-toolkit` | 3.9.0 | Direct |
| `kean/Get` | 2.2.1 | Jellyfin |
| `apple/swift-nio-transport-services` | 1.28.0 | Jellyfin |
| `apple/swift-nio` | 2.100.0 | NIO Transport Services |
| `apple/swift-atomics` | 1.3.0 | NIO / NIO Transport Services |
| `apple/swift-collections` | 1.5.1 | NIO |
| `apple/swift-system` | 1.6.4 | NIO |
| `krzyzanowskim/CryptoSwift` | 1.10.0 | Readium |
| `marmelroy/Zip` | 2.1.2 | Readium |
| `ra1028/DifferenceKit` | 1.3.0 | Readium |
| `readium/Fuzi` | 4.0.0 | Readium |
| `readium/GCDWebServer` | 4.0.1 | Readium |
| `readium/ZIPFoundation` | 3.0.1 | Readium |
| `scinfu/SwiftSoup` | 2.13.5 | Readium |
| `stephencelis/SQLite.swift` | 0.16.0 | Readium |

Gus's unused `ReadiumAdapterGCDWebServer` linked product was removed and the generated
project updated. GCDWebServer remains resolved because Readium 3.9 declares it; this
is not a stale pin. Package resolution can include optional products not linked by Gus.

Read-only checks found no local explanation for the permission requirement:

- All 16 pin locations use normal HTTPS GitHub URLs. SwiftPM workspace state agrees
  with the committed pins, including the exact `swift-collections` and Fuzi URLs.
- No Git `insteadOf`/`pushInsteadOf` URL rewrites, submodules, package mirrors,
  project SCM blueprints, or additional workspace references were found.
- The workspace references only `self:`; build caches and user workspace state are
  ignored. SwiftPM checkout origins point to its local bare caches, whose origins are
  the expected upstream HTTPS URLs.
- A normal `.git` suffix variation for Jellyfin does not produce a duplicate identity
  and does not explain the failures for `swift-collections` or Fuzi.

## Isolated onboarding experiment

**Succeeded:** a disposable local clone outside the current build caches, with package
references removed only in that copy, completed Xcode 27.1 RC onboarding immediately.
The wizard recognized the existing `dev.ericslutz.gus` app and primary repository,
did not require upstream connections, and showed **Setup Complete** with a **Default**
workflow. No Git commits or pushes were made. The package-free project was not published.

This confirms that primary-repository authorization can complete and that bypassing
the package-connection step permits onboarding. Because the copy also has fresh local
workspace state, this experiment does not distinguish a local discovery-state defect
from a server visibility defect. At that stage it did not prove that Cloud could resolve/build the
full package graph. The authenticated API subsequently confirmed Gus product
`f2e5bb18-7cd2-44ab-b88c-9d54ac63b512`, primary repository
`af9d4248-65b2-413a-a7bd-25a8885ff13e`, and workflow
`A15758DF-3577-4ED3-99F5-4B549E19BD8F` with four BUILD actions: iOS, macOS, tvOS,
and visionOS. The real project’s saved workflow configuration is verified by the API: manual starts only, Xcode 27.1 RC (27A9275), and compatible macOS GoldenGate 27.2 beta 2 (26B5091g). It has no distribution audience or post-actions. The repaired real project passed all four required BUILD actions in Build 2.

## Main publication and first remote build

The complete local app/UI/download/playback/chapter repairs, shared generated project,
root-safe Cloud bootstrap, and all 16 dependency pins were pushed directly to
`origin/main` as `755ff09c9d69872a945fcd1f464aa7a7ea701153`. The package-free experiment
was not committed or published.

The guarded API preflight verified the enabled, clean, manual-only four-platform
workflow and canonical `main` reference. The single `POST /v1/ciBuildRuns` request
returned HTTP 405 `METHOD_NOT_ALLOWED`; a subsequent read confirmed zero runs. This
unexpected response does not establish a key-permission or request-body defect.
No key rotation, permission expansion, or blind POST retry was performed.

App Store Connect's **Start Build** dialog then successfully started **Build 1**
using **Gus Multiplatform Validation → main**. Run ID:
`5c1749b4-56a3-461c-a93c-4f3b8fe17b9c`. Authenticated API verification confirms its
actual source commit exactly matches the published SHA above. It used
Xcode 27.1 RC and the configured compatible macOS image. All four required BUILD
actions failed in `ci_post_clone.sh` before compilation or package-build acceptance. This is a validation workflow with no
distribution or TestFlight action.

### Build 1 bootstrap failure and focused repair

The expanded Cloud log identifies the shared exit-65 cause:
`CI_TEAM_ID` was `1f3fb703-e0b0-42fc-bc0b-d00a3bfdf58e`, the verified App Store Connect
account/team UUID, while the script compared it with signing Team ID `QS3GC3CT43`.
This is the correct configured account, not evidence of an unexpected team.
Apple's [environment-variable reference](https://developer.apple.com/documentation/xcode/environment-variable-reference)
describes a ten-character development-team example; the actual current run supplied
the Cloud team UUID instead. The repaired bootstrap passes nine focused checks, including both expected identities,
wrong/missing accounts, signing output, preserved pins, and working directory.
It distinguishes the two known identities,
accepts either expected form, and continues rejecting an unrelated account before
writing signing configuration. `DEVELOPMENT_TEAM` remains `QS3GC3CT43`.

Actual failed bootstrap log,
Build 1 summary, and
failed overview preserve the
failure. Source fetching and project configuration checks passed in the sampled iOS
log; complete build acceptance was still pending at that stage and was subsequently
established by Build 2 below.

### Build 2 real package-fetch acceptance

The tested bootstrap repair was pushed directly to `main` as
`084a470683a78256e939bd63b416bc2fb0150bb2`. App Store Connect started a new manual
Build 2, run `635600e9-4fa2-4d68-8369-05e1bf1a0dc0`; authenticated API verification
matches that complete source SHA.

The inspected iOS log confirms the bootstrap passed in 0.9 seconds and dependency
resolution passed in 24 seconds. Cloud fetched all 16 original package repositories
and checked out the committed versions, including `apple/swift-collections` 1.5.1
and `readium/Fuzi` 4.0.0. Public dependencies are usable by the real Cloud build
without upstream administrator connections. The initial wizard's internal cause
remains unconfirmed. Build 2 finished `COMPLETE/SUCCEEDED`, with all four required
BUILD actions successful and no build errors.

Inspected resolution log,
resolution proof, and
authenticated run record this stage.

### Final validation result and limits

Cloud Build 2 passed **4/4** required actions: iOS, macOS, tvOS, and visionOS, using
source commit `084a470683a78256e939bd63b416bc2fb0150bb2` on Xcode 27.1 RC. The built
source SHA is recorded independently of later documentation/evidence and CI
configuration changes, which do not change the app source.
Final authenticated summary,
action results, and
completed-build proof confirm the result.

There are zero errors. iOS reports six warnings and macOS one: the previously
recorded DeclaredAgeRange/Readium Swift 6 isolation boundaries and deprecated
Readium URL equality. tvOS and visionOS report none. These warnings are preserved
in the issue list; build success does
not erase the documented migration work.

The workflow contains BUILD actions, no Cloud TEST, archive, distribution, or
TestFlight action. Local unit/UI acceptance is recorded in the repair report.
The sampled live Duo audio transition/control check has separate simulator
evidence.
Minimum-OS runtime, manual VoiceOver, broader Duo video/navigation/sheet flows,
signed archives, and TestFlight acceptance remain separate gates. No further
physical-phone automation was started. Website and wiki updates remain local to
their sibling repositories.

### Separate GitHub toolchain compatibility

GitHub run [38185709518](https://github.com/eslutz/A-Playa-Named-Gus/actions/runs/38185709518)
selected Xcode 27.0 (`27A266a`) and its iOS/iPadOS builds failed because that SDK has
neither `ArrangementView` nor `GeometryProxy.reservedRegions`. Runtime availability
checks cannot hide missing compile-time SDK declarations. The hosted
[`xcode-27` software manifest](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
provides the `/Applications/Xcode_27.1.app` alias and iOS 27.1 SDK. At this inspection
it resolves to build `27A9269`; the
[RC rollout](https://github.com/actions/runner-images/issues/14850) remains pending.

CI's selection is repaired to use that 27.1 SDK and reject an older iOS simulator
SDK explicitly, preserving every matrix job. Availability in the software manifest
alone did not prove compatibility; the subsequent compilation result is recorded
below. Cloud's four successful RC BUILD actions above remain separately verified.

Sanitized failure excerpts
and runner manifest
record this diagnosis. The same run's macOS unit test job failed while launching
its test runner (`IDELaunchErrorDomain 20`, `RBSRequestErrorDomain 5`,
`NSPOSIXErrorDomain 162`), before an app assertion could execute. Its underlying
host launch failure is unconfirmed and must be distinguished from a failed app
test. The repeated matrix will verify both compilation and test-runner acceptance.

GitHub run `38186826599` subsequently passed both iOS/iPadOS builds with Xcode 27.1
`27A9269`, including actual compilation of `SessionPlayerHost.swift`; the previously
missing Duo symbols now compile. Its iPhone unit tests and Watch build also passed:
**288 Swift Testing tests across 48 suites and three XCTest tests**, with
test evidence.
iPadOS compilation evidence
distinguishes this source acceptance from live Duo runtime acceptance.

The Mac unit host still failed before assertions. Its log packages the restricted
production capabilities but signs ad hoc, while the successful local tests used
development signing. [Apple TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
explains the provisioning requirement for restricted Mac entitlements. The launch
error alone does not prove that this mismatch is its cause.

The Mac unit job now creates temporary entitlements with exactly sandbox, network
client, and the approved network server permissions. An ignored local configuration
selects them only for that hosted Mac unit job; production entitlements, other
jobs, and Cloud signing remain intact. It refuses to overwrite existing local
configuration. If launch still fails, a non-gating diagnostic collects signature/
profile presence and limited app-specific signing messages with redaction.
Remote acceptance passed in [run 38187673465](https://github.com/eslutz/A-Playa-Named-Gus/actions/runs/38187673465)
at exact commit `aaebc323be81f391f9e9436b00f6c86d21a7b10e`. The signing fixture step
succeeded, the Mac host launched, and **288 Swift Testing cases in 48 suites plus
three separate XCTest performance-measurement cases passed**, with no failures.
Mac success evidence
clears the hosted launch/execution gate. This does not establish interactive Mac
UI acceptance or provisioned production/archive signing.

The completed run passed **12/13 jobs**: all six platform builds, Mac/iPad/tvOS/visionOS
unit lanes, lint, and documentation checks. The iPhone lane compiled and launched,
passed its three XCTest measurement cases, and ran all 288 Swift Testing cases,
but recorded one completion-wait issue in the audio replay regression. A separate
600-second simulator diagnostics timeout accounts for the long finish.
Run summary,
exact iPhone failure.
Native player/audio overload messages are context, not proof of the underlying cause.

Source inspection found independent playback suites activating/deactivating the same
process-wide audio session while Swift Testing runs sibling suites concurrently.
The replay suite's existing serialization does not serialize its unrelated peers;
[Apple documents this scope](https://developer.apple.com/documentation/Testing/Parallelization).
A focused test-only repair groups the stateful playback suites under one native
serialized parent and adds completion-failure diagnostics. Actual WAV completion
assertions and their deadlines remain; no tests are skipped and app playback behavior
is unchanged. The nested test identifiers change, so future focused selectors must
include `PlaybackIntegrationTests`. Formatting, syntax and shared-project checks pass;
its isolation-run result and final hosted acceptance are recorded below.


### Repeated iPhone completion failure after isolation

The isolation run [38190182036](https://github.com/eslutz/A-Playa-Named-Gus/actions/runs/38190182036)
at exact commit `deeedcac0136fa538e4985b2b0b765643c491020` also finished **12/13**.
All six platform builds and Mac/iPad/tvOS/visionOS test lanes passed. Each test lane
executed 288 Swift Testing cases in 49 suites and three XCTest measurement cases;
the iPhone recorded one issue in its first natural-completion wait. The player
remained ready/playing, rate 1.0, item time 0.4 seconds; the following deletion replay
case passed. Summary,
failure with native state.

The suite isolation hazard is repaired, but it did not resolve this observed failure.
No completion-observer defect is established. A focused test-only investigation uses
a one-second 48 kHz PCM fixture with matching metadata and captures actual native
end/failed-end events. Real playback, completion/replay/deletion assertions and the
eight-second deadline are retained. There is no forced completion, skipped case or
production workaround. The subsequent hosted result is recorded below; the earlier
four successful Cloud RC BUILD actions are unaffected.

### Final required GitHub CI acceptance

[Run 38192282611](https://github.com/eslutz/A-Playa-Named-Gus/actions/runs/38192282611) completed **13/13 jobs successfully** at exact commit `edd06e6636cd32b877622dbcb4ccb34524a1b3c1`: six platform builds, five native unit lanes, lint, and docs. Every iPhone/iPad/macOS/tvOS/visionOS lane passed **288 Swift Testing cases in 49 suites** and **three separate XCTest measurements**, with no failures or observed skipped test-case lines. Summary, lane metadata, completed log excerpts.

Both strengthened native audio cases passed in all five lanes. On iPhone, natural completion/replay passed in 4.338 seconds and automatic-deletion/local-only no-stream in 1.303 seconds. Enforced expectations verify exactly one actual end event and zero failed-end events per completed item, replay item replacement/two provider resolutions, and zero server resolution after local deletion. iPhone proof, all native cases. The test-only one-second 48 kHz PCM fixture retains the eight-second deadline and actual natural completions. The earlier 400 ms/8 kHz failure's cause is still unproven; no product workaround was added. That tested app source and production configuration match the successful Cloud `084a470` build. Required CI acceptance is complete for historical `edd06e`. Current-source GUS-UI-040 has Cloud Build 3 compilation and GitHub attempt 2 build/unit acceptance below; the unchanged-source iPad retry passed while its first-attempt failure remains recorded with an unresolved cause. Saved Duo runtime acceptance predates the edit. Physical, minimum-OS, manual VoiceOver, full Mac UI, broader Duo, signed archive, and TestFlight acceptance remain separate.

## Recovery and acceptance

Keep the isolated project local and discard it after the experiment. The workflow is configured against the real repository, real shared scheme, and
appropriate Xcode version. Cloud successfully built the complete committed Gus
project with its original package declarations and pins.
Do not publish a package-free project, force automatic package resolution, or add
unnecessary upstream repository permissions to make the setup appear complete.

If isolation still fails, capture the precise failing step and use Apple's supported
Cloud connection recovery/support path. This acceptance requirement is now met: an authenticated API/UI check confirms
Gus's product/workflow and a successful build of the real repository. A connected
primary repository alone would not have established it.

## Evidence and status caveat

Durable sanitized evidence: created product and workflow,
blocked dependency wizard,
and successful setup.
Original project, pins, and project.yml hashes still match the pre-experiment baseline.

- Configuration: `project.yml`, `A Playa Named Gus.xcodeproj/project.pbxproj`, and
  `A Playa Named Gus.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Local resolver evidence: `build/duo-validation/SourcePackages/workspace-state.json`
  and the pinned package manifests under its `checkouts/` directory.
- Temporary screenshots: `/tmp/gus-device-repair/cloud-dependency-stall.png`,
  `/tmp/gus-device-repair/cloud-public-dependency-approval.png`, and
  `/tmp/gus-device-repair/cloud-public-repository-blocker.png`; successful isolated
  setup: `/tmp/gus-device-repair/cloud-setup-complete.png`.
- Original project/pins/configuration hash baseline:
  `/tmp/gus-cloud-original-hashes.txt`. Recheck it before closing the experiment.
- Read-only API snapshots: `/tmp/gus-device-repair/asc-gus-inspect.json` and
  `/tmp/gus-device-repair/asc-onboarding-current.json` report Gus app ID `6778382140`
  with an empty Cloud product list. These are earlier diagnostic snapshots, not proof
  of current state after subsequent retries; repeat `swift Scripts/app-store-connect.swift inspect`
  before reporting final onboarding status.
- Temporary files and ignored build caches are local evidence, not durable release
  artifacts. No key material or bearer tokens are included in this report.

### Preceding-source Cloud Build 3 and CI gate

Cloud Build 3 (`db702224-7ba1-4c39-964c-0e1796b8a0d4`) completed **4/4 BUILD actions successfully** at exact source `64505d9dfd337c90f390c7c66503912eac252d3f` on Xcode 27.1 RC (`27A9275`) / macOS 27.2 beta 2. It includes GUS-UI-040. API pagination is complete: zero errors, six iOS and one Mac warnings, with messages unchanged from Build 2; tvOS and visionOS have no reported issues. API summary, issue ledger, results image. The 16 committed pins are unchanged. No Build 3 package-fetch log was exported, so Build 2 remains the evidence for its recorded 16-repository resolution. Cloud BUILD success does not establish Cloud tests, signed archives, upload or TestFlight distribution.

Current [GitHub run 38194318738, attempt 1](https://github.com/eslutz/A-Playa-Named-Gus/actions/runs/38194318738/attempts/1) passed **12/13 jobs**: all six builds, four non-iPad unit lanes, lint/docs. All five lanes ran 288 Swift Testing cases in 49 suites plus three separate XCTest performance measurements. iPad recorded one first-natural-completion issue at `AudioPlaybackTests.swift:250`, with native end/failure counts zero at current time/duration 1.0; its following deletion/no-stream case passed. First-attempt summary, iPad failure. The unchanged-source targeted iPad rerun passed in [attempt 2](https://github.com/eslutz/A-Playa-Named-Gus/actions/runs/38194318738/attempts/2), completing **13/13 successful checks**; the other 12 successes were carried forward from attempt 1. The accepted iPad lane passed 288 Swift Testing cases in 49 suites (50.658 seconds), three distinct XCTest performance cases, native completion/replay (5.097 seconds), and deletion/no-stream (1.278 seconds). All five accepted lanes passed both native cases; no skips or production workaround were introduced. Current matrix, accepted lane counts, iPad success excerpt, native cases. Required current-source build/unit CI is accepted after retry. The first failure’s cause remains unresolved; no reliable fixture or platform-only fix is claimed. Internal-only TestFlight is authorized and its all-pipelines-pass prerequisite is met; signed archive/upload/distribution and manual VoiceOver, minimum-OS, current physical/full Mac, and broader Duo acceptance remain pending. Saved sampled Duo proof covers the preceding source.


### Internal TestFlight archive attempt

The authorized manual `Gus Internal TestFlight` workflow is saved with four required internal-only Release ARCHIVE actions and four group distribution post-actions. Its Build 4 (`33eae093-33a9-4dd9-a12e-b8b9a306054a`) completed **FAILED** at exact `64505d9`: iOS App Store export and Mac App Store Connect preparation failed; tvOS/visionOS uploads are valid and ready for beta testing. All four distribution post-actions were skipped. `Gus Internal` has zero associated builds and its eligible selected account tester remains `NOT_INVITED`; upload readiness alone does not provide tester access. Current GitHub 13/13 and Cloud Build 3 4/4 BUILD acceptance remain valid, while release/distribution/install acceptance is unmet and the underlying errors require log diagnosis. [Release report](internal-testflight-release.md), final API proof.

### Warning repair and current release gate

Cloud Build 6 passed all four BUILD actions with zero issues after the six iOS/one Mac compiler warnings were repaired. Runtime code then passed corrected CI `38230709289` 13/13, including new EPUB regression execution on iPhone/iPad. Build 7 exported signed products but iOS preparation rejected alpha-bearing store icons; the three other platforms processed successfully, while group distribution was skipped. The opaque default-icon fix and semantic cross-platform artwork assertion are published in `64b9de6`/`f354c7a`; corrected CI `38237504737` and the signed retry are pending. This is an icon upload-validation issue, not a reopened package-connection blocker. [Warning proof](build-warning-repairs.md), [icon diagnosis](icon-upload-repair.md), [release status](internal-testflight-release.md).
