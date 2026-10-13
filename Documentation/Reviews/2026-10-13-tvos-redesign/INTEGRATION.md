# Local TV and warning-fix integration — October 13, 2026

Requested by Eric in the signing/warnings chat in coordination with
“Study Swiftfin tvOS redesign” (01a13361-3d0b-7185-ae10-05b32288b082).

Combined local branch: `codex/tvos-warning-free-integration`, based on merged
main c847a27 and warning-fix commit a9fd578. The TV branch was merged locally,
including all three commits: 16a5080, 68df54c, and 53d8451. The generated project
was regenerated from the complete source tree. Compiler warning gates, the Watch
AppIntents dependency, and the LibraryStoreTests concurrency repair are retained.
All production Sources match the reviewed final TV branch; its Home closure
correction is identical to the warning fix. Original pipeline/research/planning
edits and the TV owner's three source worktrees are preserved.

## Fresh combined verification

Xcode 27.1 RC (27A9275):

- macOS, iOS/Watch, tvOS/Top Shelf and visionOS app/unit-test build-for-testing
  lanes: each exit 0, zero emitted build warnings or errors.
- Full macOS suite: 411 reported tests (408 Swift Testing plus three XCTest
  measurements), zero failures, skips or expected failures.
- Full tvOS 27 suite: 412 reported tests (409 Swift Testing plus three XCTest
  measurements), zero failures, skips or expected failures.
- Eight static release checks passed, including six warning-gate regressions,
  thirteen Cloud bootstrap tests, formatting, generated project/pins and YAML.
- Companion website production build and all three tests passed.

Compile evidence: `/tmp/gus-tvos-warning-integration-validation/results.json`.
Test bundles: `/tmp/gus-integrated-mac-tests.xcresult` and
`/tmp/gus-integrated-tv-tests.xcresult`. Static evidence:
`/tmp/gus-tvos-warning-integration-static/results.json`.

The donor branch's four native TV UI cases and screenshot/metadata checks are
recorded in RUNTIME.md; this integration did not rerun its runtime harness.
Signed-device account/iCloud and physical remote/VoiceOver/HDR/audio acceptance
remain the existing release gates. No Cloud run, push, PR or publication occurred.

## Local companion integrations

- Wiki: `/tmp/gus-integrated-wiki`, branch
  `codex/tvos-warning-free-integration`. TV commits ed62fce and aaaa984 were
  applied as 9fffa40 and cce9fc2; warning-free contributor guidance is fb25353.
- Website: `/tmp/gus-integrated-website`, same branch name. TV commit 1304b0a
  was applied as 7224a55. Its three tests passed.

Only the handed-off TV commits were applied to the companions' existing local
base commits; their unrelated working-tree edits were not transferred or changed.
