# Gus Cloud optimization — October 22, 2026

Applied live in App Store Connect; no application code or GitHub CI changes.

| Workflow | Start | Tests | Archives / distribution | Clean |
| --- | --- | --- | --- | --- |
| Gus Validation (`84346672-9b14-4462-9033-0b9619a7ce6b`) | Manual, exact main | Full iOS unit scheme, explicit iPhone 17 / iOS 27.2 | None | False |
| Gus Internal TestFlight (`559f9de9-14d5-4b85-a091-8c3598fa346f`) | Manual, exact main | Original iPhone+iPad, Mac, recommended Apple TVs, Vision Pro matrix | Original four internal archives and Gus Internal post-actions | True |

Both are enabled with no automatic branch/PR/tag/scheduled triggers. Existing toolchain and architecture environment variable were copied to validation. The full release matrix has not been narrowed, and existing deferred Duo and physical/Watch acceptance boundaries remain unchanged. Routine validation provides a subset of platform coverage; it cannot replace release qualification.

## Verification

- Apple's GET API returned exactly two workflows after final save.
- Assertions confirmed clean=false, one required test action, one explicit iPhone destination, main-only manual starts and absence of all automatic triggers.
- Release action definitions exactly equal the pre-change snapshot (all eight test/archive actions, including destinations).
- App Store Connect UI verified copied architecture environment variable and retained four release distribution post-actions.
- No Cloud builds or TestFlight releases launched. Runtime success, actual cache restoration and quota savings remain unmeasured.
- Apple rejected API PATCH with HTTP 405; configuration was applied through App Store Connect UI and independently read back through GET.

## Rollback

1. In Gus Internal TestFlight, restore the branch-change condition from `workflow-before-optimization.json`: exact main, auto-cancel enabled, and the original ten build-input file rules. Keep the original eight actions, clean=true and four distribution post-actions.
2. Deactivate Gus Validation if returning to the old single-workflow behavior. Do not delete build history.
3. Re-read both workflows to verify the restored starts and actions before running anything. No credential or signing changes are needed.

The original file rules remain historical evidence; manual-only workflows do not need automatic file filters. Do not restore the filters without also intentionally restoring automatic releases.

Saved evidence: `workflow-before-optimization.json`, `workflows-after-optimization.json`, and `workflows-saved.png`. JSON snapshots exclude environment-variable values and distribution-post-action configuration because Apple's public workflow resource does not expose them.
