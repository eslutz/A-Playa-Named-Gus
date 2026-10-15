# Cloud Build 18 — completed, strict warning-free acceptance unresolved

[Build 18](https://appstoreconnect.apple.com/teams/1f3fb703-e0b0-42fc-bc0b-d00a3bfdf58e/xcode-cloud/products/f2e5bb18-7cd2-44ab-b88c-9d54ac63b512/builds/1f1cb2c0-6386-4cb2-8fe4-17615e4b7178/summary) ran PR #23's exact merged commit `e710ce6720f8e9acdef60098e40aff8a79f9846c`. Apple reports `SUCCEEDED`, finished October 14, 2026 at 04:29:55 UTC. All 12 actions succeeded: four platform tests, four archives and four internal TestFlight actions. All 12 action issue lists are empty.

Raw logs qualify that result. Every package-resolution, build-for-testing and archive compiler log has zero warning/error text. Six test destinations completed: iPhone and iPad (442 tests each), Mac (439), two Apple TV destinations (440 each), and Vision (439). These totals combine the three XCTest cases with the Swift Testing summary. Test execution succeeded on each destination.

Two raw `xcodebuild` warnings remain, neither represented in Cloud's issue API:

- macOS `test-without-building` uses `-destination platform=macOS`. The worker matches arm64e, arm64, x86_64, and other platform variants, then selects the first.
- visionOS `test-without-building` uses a simulator UUID. The worker matches both native visionOS and the Designed for iPad/iPhone variant, then selects the first.

Both commands use `-testProductsPath`, without a project or scheme. The saved workflow destination settings and Apple's `CiTestDestination`/`CiAction` schema expose device/runtime selection, but no explicit test architecture or variant. No supported override was established. Changing production architectures, removing native platform tests, suppressing diagnostics, or replacing Apple's command with a toolchain shim would not constitute a verified fix. The coordination session confirmed it has no established override either. No source or workflow setting was changed.

Archive export logs also contain DVTServices messages about creation of the Cloud worker's UserData/Capabilities directory. Test runtime logs contain system service failures and missing test artwork messages. These are distinct from compiler diagnostics and test failures; their presence means the entire raw log cannot be described as error-free. No source defect or supported Cloud remediation was established from these messages.

The strict [warning policy](../../AppStore/warning-policy.md) remains unmet. The remaining destination warnings require a verified change to Apple's generated test invocation or a supported Cloud/toolchain correction; a successful run with empty issue lists is insufficient.

[evidence/cloud-build18.json](evidence/cloud-build18.json) records exact action results, artifact hashes, raw warning excerpts, and log diagnostic counts. Raw ZIP bundles remain locally under `/tmp/gus-collections-cloud-logs/`; signed URLs, credentials and full distribution logs are not copied into repository evidence. All 18 available log bundles were inspected. Evidence and this report are local additions, not a new published change.

Apple references: [test action phases](https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions), [test destination fields](https://developer.apple.com/documentation/appstoreconnectapi/citestdestination), [custom script boundaries](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts).
