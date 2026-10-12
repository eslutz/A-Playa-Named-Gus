# Build warning repairs — October 12, 2026

The user requested removal of all six iOS and one Mac warnings observed in Cloud
Build 5 at `2546563`. The same age-range warning appears on both platforms; the
other five iOS diagnostics concern EPUB loading and resource comparison.

| Diagnostic | Change |
|---|---|
| DeclaredAgeRangeAction lacks Sendable/actor annotation in the installed Apple SDK | Keep the view and request task explicitly on the main actor, retain the single-request guard, and scope `@preconcurrency` interoperability to DeclaredAgeRange only. This handles a framework annotation gap; it does not claim the SDK type is Sendable. |
| Readium AssetRetriever, PublicationOpener, and Publication cross the UI actor during async calls | Create one retriever/parser/opener graph per load in a nonisolated concurrent operation. Resolve table of contents and the initial locator before transferring the completed publication once through a `sending` result to the main-actor model. No Readium checking suppression or unchecked Sendable conformance is used. |
| Strict Readium URL `==` is deprecated | Use the pinned toolkit's normalized `isEquivalentTo` comparison; retain the final-page progression and account-writer checks. |

The EPUB flow keeps local exact-locator precedence, provider-gated server-fraction
fallback, chapter data, and readable failure messages. Three iOS/iPadOS tests use
an original 1,681-byte EPUB fixture to exercise concurrent independent readers,
local resume without a server read, and malformed-file failure. The fixture is
included only in unit-test bundles; no new runtime dependency is added.

Compiler-only checks of the actual age-range source passed against the RC's iOS
27.1 and Mac 27.0 SDKs with complete concurrency checking and warnings as errors.
They used a minimal compile-only content-limit definition and never requested
anyone's age range. A probe containing the exact EPUB loading method and actor
ownership handoff also passed strict warning-as-error checking using the matching
cached Readium/iOS 27.0 toolchain. This does not replace the full RC build.

Formatting, plist/project consistency, and independent source/fixture review
passed. The generated project includes the new test source and fixture; all 12
previously passing scheme files and target references are preserved. The 16 pins
are unchanged. At patch publication, full RC build/test verification and the
signed TestFlight retry were still pending. The subsequent results follow below.

## Full Cloud validation

[Cloud Build 6](https://appstoreconnect.apple.com/teams/1f3fb703-e0b0-42fc-bc0b-d00a3bfdf58e/xcode-cloud/products/f2e5bb18-7cd2-44ab-b88c-9d54ac63b512/builds/f62c41a1-6948-4d38-bdba-c158e05c66b5/summary) passed all four required iOS, macOS, tvOS, and visionOS BUILD actions at `8d09dcc99a41ff9c04d404c4d6dac23c7a5225fe` with **zero issues on every platform**. The same Xcode 27.1 RC toolchain that emitted Build 5's seven warnings now reports none. [API summary and issue ledgers](cloud-onboarding-evidence/run-6/summary.json), [iOS proof](cloud-onboarding-evidence/run-6/ios-no-issues.jpg), [Mac proof](cloud-onboarding-evidence/run-6/macos-no-issues.jpg).

GitHub CI `38229756528` found a compile error in the new exact-locator regression test: Readium's Locator requires a URLConvertible URL, while Link.href is a String. Commit `bd01514072a575cb5153f2729ab7c96ebbf573eb` changes only that test to use Link.url(); the app source is identical to Cloud Build 6. The superseded matrix was cancelled after diagnosis. Corrected CI `38230709289` is pending; no test execution success is claimed yet.

The corrected iPhone and iPad lanes each executed and passed all three EPUB regressions and 291 Swift Testing cases in 50 suites, plus the separate XCTest measurements. [iPhone execution](cloud-onboarding-evidence/github-ci/run-38230709289-iphone-tests.txt), [iPad execution](cloud-onboarding-evidence/github-ci/run-38230709289-ipad-tests.txt). The remaining CI build/test lanes and signed release remain pending at this snapshot.

## Completed test gate

[Corrected CI run 38230709289](https://github.com/eslutz/A-Playa-Named-Gus/actions/runs/38230709289) passed **13/13 checks** at `bd01514072a575cb5153f2729ab7c96ebbf573eb`, without a rerun: six builds, five unit lanes, lint and docs. iPhone/iPad passed 291 cases in 50 suites each; Mac/tvOS/visionOS passed 288 cases in 49 suites each. All lanes also passed the separate XCTest measurements. [Final matrix](cloud-onboarding-evidence/github-ci/run-38230709289-summary.json). The preceding compile-error run remains historical evidence; it is not counted as a passed matrix.

The requested seven compiler warnings are resolved and regression acceptance is complete. The signed internal TestFlight release is tracked separately in [the release report](internal-testflight-release.md).
