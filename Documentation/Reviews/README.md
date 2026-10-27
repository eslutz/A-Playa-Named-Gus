# Review decisions and open acceptance

This document consolidates historical reviews. Earlier test results describe the
specific revisions tested and do not establish the state of the current build.
Raw build logs, screenshots, result bundles, and Cloud snapshots do not belong
in source. Historical records remain in Git history.

## Product and implementation decisions

- Jellyfin owns playlist and collection names, membership, ordering, and access.
  Gus retains account-scoped offline edits and supplemental playback cursors and
  Next Up intent. Native lists reject duplicate title membership; legacy Gus lists
  require explicit import and must not silently lose repeated entries.
- Video playlist shuffle is a playback-session sequence; it does not reorder the
  saved list. Mixed-media entries remain individually playable. Native list editing
  uses system reorder controls; iOS leading handles use public drag-and-drop in a scroll container because native List owns its trailing handle.
- Seerr is account-scoped. Request review evaluates standard and 4K permissions
  independently; fresh settings and quota gate submission. Preference saves use
  snapshots of submitted values, and unresolved writes require recovery rather
  than blind retry. Live-server acceptance remains open.
- The OS 26 deployment floor covers every platform. OS 27 APIs remain available
  behind guards; OS 26 fallbacks include audio session activation, the tvOS account
  menu and visionOS stereo rendering. The iOS 26.0 player uses the return bar
  where the conditional tab accessory is unavailable.
- iOS and macOS remain in Swift 5 language mode with complete concurrency checks
  because of the Readium and Declared Age Range isolation boundaries. See
  [Swift concurrency](2026-10-10-release-validation/SWIFT-CONCURRENCY.md).
- The iPhone implementation now follows the user-selected live Gus iPhone Sketch
  document (Screens, States and Components). The historical R5/Build 32 review
  records remain reference material. Current Light-mode simulator comparisons
  stay outside source; physical acceptance and later-device design remain pending.

## Acceptance still needed

- Revalidate the actual release candidate: warning-free platform builds and tests,
  required hosted checks, signed archives and distribution, and tester access are
  distinct gates. Earlier TestFlight delivery is not acceptance of current source.
- Exercise exact OS 26.0 where supported and confirm platform-specific fallbacks.
  Build success alone does not prove minimum-OS runtime behavior.
- Complete live Seerr and Jellyfin behavior, physical-device playback and account
  flows, accessibility/VoiceOver, Dynamic Type and remote/focus acceptance.
- Verify signed iCloud provisioning and cross-device cursor/Next Up synchronization,
  including offline recovery. Downloads remain device-local.
- Complete physical Apple TV focus, Back/Menu, display/HDR/audio, and account
  switching acceptance. Simulator results do not substitute for a physical TV.

## Release workflow

The saved Cloud workflow configuration and current release gates are described in
[the pipeline policy](../AppStore/pipeline-policy.md). Routine validation does not
replace full release qualification. Recheck the live configuration before relying
on it; Cloud execution and actual tester installation remain separate outcomes.

## Reproducing an iPhone design comparison

Use the local `gus-demo-jellyfin` server and one fixed iPhone simulator for both revisions. `GusDesignCaptureUITests` captures Light-mode scenes into an external XCTest result bundle; its optional-category walkthrough temporarily changes the synthetic account's navigation preferences, so back up and restore those preferences. Seerr UI regressions additionally require `Scripts/discover-fixture-server.py`.

Export attachments outside the repository, organize original PNGs by matching scenario filenames, then run `Scripts/generate-ui-comparison.py --before <baseline> --after <candidate> --references <mapping.json> --notes <scope.txt> --device <device-and-OS> --baseline <commit> --output <external-directory>`. The generator refuses an output directory inside this repository and reports incomplete pairs explicitly. Its manifest records image dimensions and hashes.

For subsequent review fixes, preserve the original comparison and append a third image with `Scripts/generate-ui-comparison.py --next-iteration <captures> --output <existing-external-report> --notes <scope.txt> --findings <checklist.json>`. This retains original assets, captions, notes and before/after manifest fields; new scenarios explicitly mark missing historical captures. Keep the numbered checklist, validation details and report backups outside source.

For focused feedback after that third column, use `--follow-up <captures>` in place of `--next-iteration`. Matching existing scenarios gain a fourth Review follow-up image; all three historical columns remain intact. The synthetic Next Up walkthrough saves additional demo titles through the app to make the list presentation reviewable.
