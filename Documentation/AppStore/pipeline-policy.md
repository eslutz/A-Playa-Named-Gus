# Pull request and release gates

Requested October 12, 2026. Main is protected, including administrators: changes require a pull request, all 13 GitHub Actions checks must pass on an up-to-date branch, conversations must be resolved, and linear history is required. Force pushes and deletion are disabled. No additional reviewer approval is required; the PR and CI gate still apply to the owner.

GitHub CI runs only on pull requests targeting main, with read-only repository permissions and cancellation of superseded runs for the same PR. It keeps six builds, five unit-test lanes, lint, and configuration checks.

The saved Gus Internal TestFlight Cloud workflow accepts only exact main for automatic branch changes and manual starts. It requires unit tests using dedicated iOS, macOS, tvOS, and visionOS schemes before its internal TestFlight post-actions can distribute. iOS runs on iPhone 17, iPad Pro 11-inch (M5), and Duo; Mac, recommended Apple TVs, and Apple Vision Pro complete the device matrix. Four required internal-only archives produce the app products; Watch is embedded in iOS.

Cloud's available iOS runtime menu showed 27.1, 17.5, and 16.4. It offered no iOS 18 runtime, so minimum-OS execution remains unverified. The known iPad native audio end-notification failure is retained in run 38242041231 evidence and is not counted as a passing gate.

Saved configuration does not establish successful execution or tester eligibility. The PR matrix, subsequent merged-main Cloud run, and group association must pass before availability is claimed.

The old compile-only Gus Multiplatform Validation workflow was permanently deleted after explicit confirmation; Apple says associated builds are no longer shown by default. Saved diagnostic evidence remains in this repository. Superseded main release builds are automatically cancelled when a newer main update starts.

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
