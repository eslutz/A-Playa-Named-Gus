# Pull request and release gates

Requested October 12, 2026. Main is protected, including administrators: changes require a pull request, all 13 GitHub Actions checks must pass on an up-to-date branch, conversations must be resolved, and linear history is required. Force pushes and deletion are disabled. No additional reviewer approval is required; the PR and CI gate still apply to the owner.

GitHub CI runs only on pull requests targeting main, with read-only repository permissions and cancellation of superseded runs for the same PR. It keeps six builds, five unit-test lanes, lint, and configuration checks.

The saved Gus Internal TestFlight Cloud workflow accepts only exact main for automatic branch changes and manual starts. It requires unit tests using dedicated iOS, macOS, tvOS, and visionOS schemes before its internal TestFlight post-actions can distribute. iOS runs on iPhone 17 and iPad Pro 11-inch (M5); Mac, recommended Apple TVs, and Apple Vision Pro complete the device matrix. Four required internal-only archives produce the app products; Watch is embedded in iOS.

At the original October 12 configuration check, Cloud's iOS runtime menu showed 27.1, 17.5, and 16.4 with no iOS 18 option. That observation is historical; the current deployment floor is OS 26.0. The later saved Duo-deferral screenshot shows iOS 27.2 selected for iPhone and iPad. Earlier iPad native audio failures remain in the investigation history below; final merged-main action results and remaining acceptance limits are recorded separately.

Saved configuration does not establish successful execution or tester eligibility. The PR matrix, subsequent merged-main Cloud run, and group association must pass before availability is claimed.

The old compile-only Gus Multiplatform Validation workflow was permanently deleted after explicit confirmation (see [confirmation dialog](pipeline-policy-evidence/delete-validation-confirmation.jpg)); Apple says associated builds are no longer shown by default. Saved diagnostic evidence remains in this repository. Superseded main release builds are automatically cancelled when a newer main update starts.

The retained iPad audio failure message now captures the native asynchronous audio-session activation result (success and error domain/code) in Debug builds. Release behavior and the native end-event requirement are unchanged; this gathers root-cause evidence without treating a retry as a fix.

## Automatic start file filters — 2026-10-12

The live main-only branch-change condition uses `START_IF_ANY_FILE_MATCHES` with ten matchers: `Sources/`, `Tests/`, `Resources/`, `Config/`, `ci_scripts/`, `Scripts/`, `A Playa Named Gus.xcodeproj/`, plus filenames `project.yml`, `Package.resolved`, and `Package.swift`. Documentation and unrelated file-only changes do not match. A mixed code/documentation commit still starts a run. New build-input locations must be added to this allowlist. Manual main-only starts remain available.

The four TestFlight post-actions associate each platform archive with Gus Internal after the required workflow actions succeed; they are the distribution stage, not additional tests or public App Store submission.

Saved UI proof: `pipeline-policy-evidence/cloud-path-filters.jpg`. Independent Apple API proof: `pipeline-policy-evidence/cloud-path-filters.json`.

## iPad native completion investigation — run 38251008247

The unmuted audio replay case failed its first natural completion: audio activation succeeded, item status was ready, time reached 1.0 seconds (duration 1.0), and neither a native end nor failure notification arrived. Core Audio reported an I/O overload during the failing playback. The muted case and subsequent offline completion case passed. This rules out activation failure for this occurrence, but does not establish why native rendering stalled.

The next controlled CI experiment isolates PlaybackIntegrationTests from unrelated concurrent Swift Testing suites and executes it three times without failure retries, then runs the remaining tests separately. A result-count assertion rejects a filter that accidentally runs zero tests. Runtime playback behavior and completion assertions remain unchanged. This is an investigation, not a confirmed fix; the experiment must pass and its executed test identities must be inspected before acceptance.

The isolation experiment (run 38257402157, 8863ae0) failed on the first unmuted playback. Later repetitions passed, but xcodebuild correctly returned failure. The unrelated-suite contention hypothesis is not established, and the experimental split/repetition has been removed. The unchanged iPhone control also failed its first unmuted completion.

A concrete fixture/production difference was identified next: the replay test eagerly constructed AVPlayer before audio-session activation, whereas production invokes its player factory only after activation. The fixture now constructs its player lazily inside the factory, preserving both mute modes and all real end-notification/replay assertions. This lifecycle-alignment hypothesis requires validation; no runtime playback change or beta-toolchain root-cause claim is made. GitHub's hosted Xcode 27.1 is build 27A9269, while Cloud uses RC 27A9275; the remote Mac comparison was unavailable because its configured hostname did not resolve.

The first lazy-factory run exposed a stale test reference on Mac: initial playback completed natively, but the replay assertion kept inspecting the old player after the factory constructed a new one. The replay check now observes the latest factory-created player, requires distinct player and item identities, and verifies its second native completion. This fixes the diagnostic fixture itself; the cold iOS result remains a separate validation gate.

Run 38262931632 (f324ec7) passed 12/13 checks, including iPad, but iPhone again failed the first unmuted native end notification. Lazy player construction therefore did not eliminate the failure. Temporary, separately compiled bare-AVPlayer controls now compare asynchronous and synchronous audio-session activation on separate fresh iPhone runners. They use the same PCM asset and real notification requirements, with no AudioPlayerStore or Now Playing owner. Normal tests remain unchanged and must still pass; the diagnostic job/conditional methods must be removed after the cause is established.

The initial standalone diagnostic selector matched zero tests (the diagnostic flag was present on GusTests). Its exact-count guard failed the job; this is not an activation result. The Swift Testing method selectors now include their `()` signatures.

The corrected bare asynchronous control executed one real test and passed. The synchronous-activation control executed one test but expired while the item was still unknown/waiting at time zero, before playback started. The old 8-second completion budget therefore included asynchronous native startup. The fixture now waits separately (bounded at 45 seconds) for a ready, playing item with an advancing media clock, or an already-delivered native end event, then uses the unchanged 8-second completion budget. Replay preparation is also bounded separately. No completion is inferred from time/duration and both native completion events remain mandatory. The new distinction requires a fresh full validation run; activation has not been changed.

The temporary activation comparison jobs and conditional test methods have been removed. The label “legacy” described the older synchronous Apple API used by that diagnostic, not a shipped compatibility mode. Production activation is unchanged; the normal platform checks validate the startup/completion fixture correction.

## OS 26 compatibility / OS 27 feature policy

All supported Apple platforms require OS 26.0, including the embedded Watch app and tvOS Top Shelf. Build with Xcode 27.1 or newer and retain OS 27.x functionality through availability checks and native OS 26 fallbacks. The conditional iOS tab accessory requires 26.1; 26.0 uses the Now Playing return bar. OS 27 retains asynchronous audio-session APIs, the tvOS sidebar account header, and the visionOS sample-buffer receiver. The iOS 27.1 Duo division API remains availability-guarded. Development-era storage/credential/DTO migrations removed by the earlier OS 27-only change remain removed; lowering the OS floor does not restore those migrations. Existing development installs may still need to sign in again and recreate local downloads and queues.

The local compatibility report is [OS 26 validation](../Reviews/2026-10-21-os26-compatibility/VALIDATION.md). Required GitHub checks, merged-main Xcode Cloud actions, raw-log review, and TestFlight group availability must be verified for the release commit.

On 2026-10-12, the user deferred required Duo simulator testing until the device is released and compatible runtimes are available. Duo functionality and its SDK compilation requirements remain in the app. [Saved destination evidence](pipeline-policy-evidence/duo-testing-deferred.png) shows the retained iPhone and iPad selections. All other required platform tests, archives, and main triggers are retained.

## Merged-main action results — 2026-10-13

[PR #22](https://github.com/eslutz/A-Playa-Named-Gus/pull/22) merged as `a794a7f308c3c4281e6b98a5f2f908f3a684207b` after all 13 GitHub checks passed and both review conversations were resolved. The source tree matches the final checked branch commit `3c631386a154b099d8376facc938913e2ee483a5`.

[Xcode Cloud Build 17](https://appstoreconnect.apple.com/teams/1f3fb703-e0b0-42fc-bc0b-d00a3bfdf58e/xcode-cloud/products/f2e5bb18-7cd2-44ab-b88c-9d54ac63b512/builds/af959737-7e61-4452-bfcc-4c59dec0013b/summary) ran that exact merge SHA. All four tests, four archives/signing/export paths and four internal TestFlight actions succeeded. Apple's API returned empty issue lists for all 12 actions. This confirms the reported action results, but does not establish that their raw logs were warning-free. Build 17's raw test/archive log inspection is not recorded here, so strict warning-free acceptance remains unresolved. [Build 18's raw-log review](../Reviews/2026-10-13-collections/CLOUD-BUILD18.md) subsequently demonstrated why empty issue lists are insufficient. Physical playback, VoiceOver and multi-device CloudKit acceptance also remain separate. Future changes must satisfy the same [warning-free policy](warning-policy.md).

## Build 23 test-runner preflight failure — 2026-10-15

[Build 23](https://appstoreconnect.apple.com/teams/1f3fb703-e0b0-42fc-bc0b-d00a3bfdf58e/xcode-cloud/products/f2e5bb18-7cd2-44ab-b88c-9d54ac63b512/builds/b5294752-1328-42e1-a75f-9d441a8bfa99/summary)
ran merged main `97a4eeb`. All six test-runner logs (iPhone, iPad, two Apple TV
destinations, Mac, and Vision Pro) reported `Apple Silicon enforcement missing`
from `ci_pre_xcodebuild.sh` during `test-without-building`. The inspected tvOS
`build-for-testing` log succeeded with zero build diagnostics and no Intel actions.
This was a shared preflight failure, not a failing test assertion or tvOS UI compiler error.

Cloud transfers built test products and custom scripts to separate execution
runners; source files may be unavailable there. The preflight now exits before
accessing the checkout only for `test-without-building`. Compilation, analysis,
`build-for-testing`, and archives still require the global architecture xcconfig;
Mac test-host signing remains confined to `build-for-testing`. This follows
[Apple's custom script lifecycle](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts).

The regression reproduced eight failures before the fix, then passed all 19
bootstrap tests, including all four platform runners without a checkout and
16 compilation/platform combinations that still reject missing architecture
configuration. All 11 warning-gate tests and generated-project checks also passed.
A fresh merged-main Cloud run remains required to establish hosted recovery and
TestFlight distribution; Build 23 is not accepted.
