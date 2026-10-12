# Stale media-reference recovery — October 12, 2026

## Confirmed failure

The iPhone's saved Trespass (1992) Next Up entry referenced an obsolete Jellyfin ID. Its tagged backdrop and primary image URLs returned 404 on the phone's configured server. The current library entry has a different ID; backdrop, primary, and thumbnail images return 200. No missing server artwork was found.

## Implementation

Saved references retain account/provider scope and external identities separately from cached display metadata. Next Up migrates to a versioned envelope with stable entry UUIDs and an original-file backup. Only a unique compatible external-ID match reconnects automatically; legacy and ambiguous entries stay visible with Retry, Choose Replacement, and Remove. Resolution protects remote actions, system links, download metadata, and checkpoint uploads. Downloaded files keep their original identity. Playback positions require confirmation before transfer; book locators remain file-specific. Ordered artwork fallbacks use Jellyfin's explicit inherited-artwork owner.

The independent review identified and prompted repairs for replacement seeking, downloaded-byte aliases, cache identity isolation, account/version checks before progress writes, queue error visibility, and unavailable-progress recovery controls.

## Verification

- The pinned-metadata regression failed against the original implementation, then passed after the repair.
- The inherited-artwork regression failed against the original image builder, then passed after using ParentBackdropItemId.
- macOS: final Xcode 27.1 RC run passed 304 tests in 51 suites.
- iOS 27 simulator: 307 tests in 52 suites passed with Xcode 27.1 RC.
- iPhone, iPad, tvOS, visionOS, and watchOS builds passed with Xcode 27.1 RC. Compatible OS 27 tvOS/visionOS/watchOS simulator runtimes are unavailable, so their unit suites were not executed locally.
- Shared project/scheme/dependency checks, SwiftFormat lint (0/201 files requiring formatting), whitespace checks, string-catalog JSON validation, and companion website tests passed.
- Physical iPhone: installed and launched the local signed candidate **1.0.0 (1)**. The live legacy queue migrated to schema 1 without losing its single entry; its backup SHA-256 matches the original file byte for byte.
- The first physical automation attempt timed out enabling automation mode. After confirming the phone was unlocked and launching the candidate normally, the isolated native UI recovery test passed **1/1** in 19.781 seconds. It opened Choose Replacement, verified the candidate label included Trespass and 1992, selected it, and returned to Home.
- A second native physical test passed **1/1** in 13.418 seconds, opening the repaired movie details and Downloaded library, then returning Home. Read-only metadata confirms two complete download records remain (3,282,127,450 stored bytes). This verifies navigation and record preservation; no media playback/deletion was exercised.
- Visual inspection of the resulting physical screenshot confirms Trespass's blue widescreen artwork displays in Next Up. A subsequent read-only container copy confirms the queue UUID is unchanged, the reference now points to the current library item, availability is available, and two external identities are retained.
- Local evidence is under `build/stale-reference-evidence/` and `/tmp/gus-stale-physical/AcceptanceRetry.xcresult`. Personal-library screenshots, account-scoped queue files, and full UI trees are deliberately not committed.

## Limits

Jellyfin item IDs can change at any time. A server mutation between validation and an action may still return 404; Gus must recover safely rather than claim IDs never become stale. SDK 2.1 lacks ID sorting and external-ID filters, so replacement scans use supported name ordering, detect repeated IDs/changed totals/incomplete pages, and refuse to establish uniqueness from an incomplete scan. Automatic episode recovery currently requires the same series ID and season/episode locator; replacing both series and episode requires selection.

No Jellyfin configuration, library metadata, media, or watch history was changed during diagnosis. No TestFlight build has been published by this task.
