# Review decisions and acceptance

Use this index for product and design QA. Results apply only to the tested source
and artifacts. Keep raw logs, screenshots, result bundles, and Cloud snapshots
out of Git.

## Product and implementation decisions

- Jellyfin owns native playlist and collection names, membership, ordering, and
  access. Gus maintains account-scoped offline drafts/journals and supplemental
  playback cursors and Next Up intent. The server rejects duplicate membership;
  already-returned occurrences stay in order. Video shuffle changes the playback
  sequence, not the saved order.
- See [behavior and regression guide](../behavior-and-regression-guide.md), the [Seerr API contract](../Seerr-api-contract.md),
  [concurrency rationale](../engineering-guide.md#swift-concurrency-boundaries), and
  the [Sketch design guide](../../Design/README.md) for the owning details.

## Acceptance still needed

For a candidate, distinguish compilation, exact minimum-OS runtime behavior,
native archives/distribution, and actual tester access. Track remaining live
Jellyfin/Seerr, iCloud sync/recovery, and accessibility or physical-device
acceptance as explicit follow-up where relevant; do not treat them as ordinary
authorized local validation or claim success from simulator evidence.

## Release workflow

Follow the [pipeline policy](../AppStore/pipeline-policy.md) for current
local-only simulator qualification, hosted PR checks, and separately authorized
archive and distribution gates.

## Reproducing an iPhone design comparison

Use the local `gus-demo-jellyfin` server and one fixed iPhone simulator for both revisions. `GusDesignCaptureUITests` captures Light-mode scenes into an external XCTest result bundle; its optional-category walkthrough temporarily changes the synthetic account's navigation preferences, so back up and restore those preferences. Seerr UI regressions additionally require `Scripts/discover-fixture-server.py`.

Export attachments outside the repository, organize original PNGs by matching scenario filenames, then run `python3 Scripts/generate-ui-comparison.py --before <baseline> --after <candidate> --references <mapping.json> --notes <scope.txt> --device <device-and-OS> --baseline <commit> --output <external-directory>`. Reference mapping and notes are optional for the initial report. The generator refuses an output directory inside this repository and reports incomplete pairs explicitly. Its manifest records image dimensions and hashes.

For subsequent review fixes, preserve the original comparison and append a third image with `python3 Scripts/generate-ui-comparison.py --next-iteration <captures> --output <existing-external-report> --notes <scope.txt> --findings <checklist.json>`. This requires an existing report with `index.html` and `manifest.json` and retains original assets, captions, notes and before/after manifest fields; new scenarios explicitly mark missing historical captures. Keep the numbered checklist, validation details and report backups outside source.

For focused feedback after that third column, use `--follow-up <captures>` in place of `--next-iteration`. Only matching existing scenarios gain a fourth Review follow-up image; all three historical columns remain intact. The synthetic Next Up walkthrough saves additional demo titles through the app to make the list presentation reviewable.

## Platform icon composition

Use the [tvOS and visionOS icon layer viewer](platform-icon-review/index.html)
to resize the composition and toggle the layers. The preview does not establish
native focus, lighting, or parallax. See the
[icon source guide](../AppStore/icon-composer-source.md) for regeneration and
native verification.
