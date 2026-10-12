# Build 11 local reproduction and repair

Baseline: `d6a15cf`, Xcode 27.1 RC. Local validation uses a disposable Git snapshot and two compiler jobs. The user's checkout and physical phone were not moved, installed, or tested.

## Confirmed local reproductions

1. Swift 6 object compilation of StereoFrameRenderer reproduces Cloud's region-isolation error at `packed.withUnsafeBuffer({ split($0) })`. Type-check-only validation does not run the compiler stage that emits this diagnostic. The repair consumes the borrowed source pixel buffer and enqueues both eye buffers inside the callback, returning only Void; pool-owned buffers no longer cross a sending-result boundary. Strict Swift 6 simulator object compilation and optimized whole-module visionOS device compilation both pass with warnings treated as errors.
2. Xcode `build-for-testing` succeeds for Gus macOS Unit Tests. Running its `.xctestproducts` with the disposable source checkout temporarily hidden executes 24 focused tests: 17 fail with missing source/entitlement/icon/plist files, reproducing Cloud's separate-worker failures. Tests must not depend on the build machine's absolute `#filePath` checkout.

## Portable test inputs

All four unit-test targets package the exact source and reviewed configuration/artwork inputs into their own test bundle before signing. The shared fixture locator loads only those packaged inputs, without a checkout fallback. The packaging script excludes local signing configuration, environment files, private keys, and other developer credentials. Production app resources are unaffected. Source assertions are retained, rather than skipped when files are absent.

After rebuilding, the full Mac suite is run with `test-without-building` and the source snapshot hidden again: **286 tests passed, zero failed**, exit 0. Machine-readable before/after counts are saved alongside this report. The temporary checkout was restored after each run.

## Destination failure reproduced and configured workaround

Creating iPhone 17 against the installed iOS 27.1 runtime fails locally with CoreSimulator error 403, “Incompatible device.” The runtime's profile is restricted to device type V68 (Duo). The selected RC runtime therefore cannot support the workflow's iPhone/iPad destinations despite Apple's broad API device inventory listing them. The old Vision Pro (2732×2048) device profile has a maximum runtime of 2.99, incompatible with visionOS 27.

The live workflow now selects Xcode 27.2 beta 2, explicit iOS 27.2 for iPhone 17/iPad/Duo, and the current Apple Vision Pro model with explicit visionOS 27.2. Apple’s API advertises these compatible pairings. Saved configuration was independently verified through the API; all required test/archive actions and main triggers are preserved. The deployment minimum remains OS 27.0. The newer beta toolchain/runtime pairing was not installed locally and requires acceptance in the next Cloud run; it is a configured workaround, not a claim that Apple's test workers have already passed.

Other checks: SwiftFormat lint, generated-project/pinned-package consistency, and diff checks pass. Full remote acceptance is pending the next build; local compiler acceptance does not establish device rendering behavior.
