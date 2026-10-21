# Design maintenance

Canonical editable files live in [Design/Gus](../../Gus/). Review the [shared preview](../../Exports/Preview/Preview.html), [screen coverage](../../SCREEN-COVERAGE.md) and [Discover specification](../../DISCOVER.md). The expanded proposal uses the [Discover generator and coverage contract](discover/README.md).

Current-app edits are made in the editable files. `sync-preview-from-splits.mjs` refreshes their saved SVG exports and navigation metadata; `full-preview.py` rebuilds the shared review and indexes. Keep proposal edits in its generator before regeneration. `verify-splits.mjs` checks every saved file; `verify-publication.py` audits scene exports, coverage and links and refreshes the file manifest; `preview-tests.mjs` checks scroll/clipping behavior; `cli-qa.py` performs sequential baseline font/raster checks. Historical one-off reconstruction and correction scripts have been removed.

The tools use OpenPencil 0.16, CanvasKit and locally installed licensed Apple fonts. `fonts.mjs`, `cli-fonts.mjs` and `openpencil` are required helpers. No font binaries are redistributed. See the CLI runner for the pinned install command. The SDK can be configured with `GUS_OPENPENCIL_SDK_ROOT`; the CLI with `GUS_OPENPENCIL_CLI_ROOT`. Apple static font faces are expected under `/Library/Fonts/` on macOS.

All commands run from the repository root. Run checks sequentially. These tools do not build Gus, launch a simulator or contact a media server.
