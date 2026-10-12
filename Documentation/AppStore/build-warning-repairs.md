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
are unchanged. Full Xcode 27.1 RC builds, current-source unit execution, zero
warning issue ledgers, and the subsequent signed TestFlight retry remain pending.
