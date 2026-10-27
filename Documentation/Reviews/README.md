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
  uses system reorder controls.
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
- The current iPhone R5 designs await acceptance. The [per-screen Build 32
  comparison](2026-10-26-build32-design-comparison/report.md) records review
  questions, not accepted design decisions. Later-device design remains pending.

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
