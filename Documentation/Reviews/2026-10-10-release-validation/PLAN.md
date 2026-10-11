# Gus release validation plan — 2026-10-10

Status: **available local work complete** — audited, remediated, validated and prepared for local commits; release gates remain explicit in [VALIDATION.md](VALIDATION.md). This plan covers the entire current app candidate,
including existing offline/download work, UI remediation, API preparation, and changes
in the companion wiki and website. Complete the review report before implementation,
then remediate, validate the final candidate, and commit all repository changes.

The detailed execution plan is maintained in the sibling wiki:
[Release Validation Plan](https://github.com/eslutz/A-Playa-Named-Gus/wiki/Release-Validation-Plan)
(`../Gus.wiki/Release-Validation-Plan.md` locally).

## Verified planning baseline

- Local toolchain: Xcode **27.0**, build **27A266a**, Swift **6.4**, iOS SDK **27.0**.
- Installed useful runtimes: iOS 27.0 and 26.5; tvOS, watchOS, and visionOS 26.5.
  Minimum supported OS runtimes are absent; older installed runtimes are below the
  deployment targets and cannot substitute for minimum-OS validation.
- `project.yml` still declares Xcode 26.5; CI hard-codes Xcode 26.5 and macos-26.
  `Config/Shared.xcconfig` deliberately uses Swift 5 mode and minimal concurrency checks.
- Main release identity remains `dev.ericslutz.gus`, marketing version **1.0.0**,
  separate numeric build **1**. Keep three-part semver throughout.
- 145 app-owned Swift files require a review ledger. Existing committed UI tests cover
  Connect launch, largest text, and pseudolocalization; authenticated journeys need
  repeatable coverage. Earlier external harnesses are useful starting points.
- Earlier remediation evidence records 274 tests/46 suites on four platforms,
  six platform builds, selected runtime flows, and an unsigned iOS/Watch Release archive.
  These are prior results, not the final validation of the next candidate.
- Open acceptance gaps include the 40 mm Watch album-navigation stall, physical phone
  rotation/playback, native Mac window/keyboard interactions, VoiceOver, spatial input,
  loading/error recovery, and minimum-OS execution.
- Before this plan, the app tree had 853 status entries, with approximately 628 MB of
  review evidence and an untracked local `sample_media` symlink. Wiki and website also
  contain uncommitted changes. Nothing was staged.

## Execution sequence and gates

| Step | Work | Required output / acceptance |
|---|---|---|
| 1 | Inventory and preserve all three working trees; freeze toolchain, fixtures, and evidence policy. | Candidate manifest, backups/hashes, explicit disposition for every dirty path; credentials and machine-local symlink excluded from git. |
| 2 | Audit iOS 27 configuration and every app-owned source area, including SwiftUI ownership, concurrency, availability, dependencies, and public APIs. | File/target coverage ledger, compiler diagnostics, proposed settings/API changes supported by current Apple/Swift documentation. |
| 3 | Capture real signed-out and authenticated journeys across supported platforms; review UX, design, HIG alignment, and all original findings/addenda. | Fresh inspected screenshots, numbered flow steps, expected/observed behavior, deterministic reproduction of the Watch stall or a named evidence gap. |
| 4 | Run accessibility audits and the text/appearance/input matrix; test restoration and interruption/recovery. | Per-screen XCTest/Inspector results; justified false positives; no blanket suppression; assistive-device limits recorded separately. |
| 5 | Measure performance/reliability; audit privacy, capabilities, release contents, metadata and applicable App Review rules. | Traces and metrics, privacy/API-to-manifest mapping, guideline applicability matrix, release packaging evidence. |
| 6 | Finish one consolidated audit report before fixes. | Stable Blocker/High/Medium/Polish IDs; verified defects distinguished from source risks, recommendations, and environment blockers. |
| 7 | Fix verified findings and add meaningful regression automation; reconcile Xcode/CI settings and incrementally strengthen Swift concurrency. | Focused changes and tests; project regenerated; wiki/website/roadmap reflect actual behavior and remaining limits. |
| 8 | Validate the complete final candidate from an isolated copy of the reviewed staged files. | All available platform builds/tests, UI/a11y matrix, tooling checks and unsigned Release archives pass; source hashes match tested files. |
| 9 | Commit every validated repository change, including pre-existing work, after staged-diff and secret/artifact checks. | App, wiki and website commits; no unexplained unstaged/untracked/staged files; report commit SHAs and pending manual/portal gates. |

No app code/settings/tests are changed as part of creating this plan. Execution begins
with inventory and an audit; fixes follow the consolidated report. A local commit does
not require the missing App Store Connect key. Portal signing, Cloud execution, actual
TestFlight installation, and human/device acceptance remain separate release gates.
No push, upload, tester invitation, or submission is implied by the commit step.

## Evidence and completion policy

Preserve the original review folder, both addenda, and the complete screenshot set.
Include all safe versionable existing changes; do not silently discard prior work or
reduce it to only the new validation fixes. Inventory large evidence and scan it before
staging. Keep credentials, private keys, build caches, raw signing material and the
machine-specific media symlink local; document their disposition without contents.

The commit gate requires passing available automated checks, no unresolved verified
Blocker/High defects, and an explicit ledger of unavailable checks. Missing hardware,
minimum-OS runtimes, or portal credentials can leave release acceptance pending while
the validated local work is committed. Never mark those checks passed by inference.

## Sources checked for planning

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Xcode SDK/compiler support](https://developer.apple.com/xcode/system-requirements)
- [Automated accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app)
- [Swift concurrency migration](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/)

Build iOS Apps and Product Design guidance inform the workflow. Context7 was used for
official Swift migration and Apple SwiftUI Observation/task documentation; SDK-specific
claims must also be checked against installed interfaces and Apple release notes.
