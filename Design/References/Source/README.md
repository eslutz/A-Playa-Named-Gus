# Design maintenance

Canonical editable files live in [Design/Gus](../../Gus/). Review the [shared preview](../../Exports/Preview/Preview.html), [screen coverage](../../SCREEN-COVERAGE.md) and [Discover specification](../../DISCOVER.md). The expanded proposal uses the [Discover generator and coverage contract](discover/README.md).

Current-app edits are made in the editable files. `sync-preview-from-splits.mjs` refreshes their saved SVG exports and navigation metadata; `full-preview.py` rebuilds the shared review and indexes. Keep proposal edits in its generator before regeneration. `verify-splits.mjs` checks every saved file; `verify-publication.py` audits scene exports, coverage and links and refreshes the file manifest; `preview-tests.mjs` checks scroll/clipping behavior; `cli-qa.py` performs sequential baseline font/raster checks. Historical one-off reconstruction and correction scripts have been removed.

The tools use OpenPencil 0.16, CanvasKit and locally installed licensed Apple fonts. `fonts.mjs`, `cli-fonts.mjs` and `openpencil` are required helpers. No font binaries are redistributed. See the CLI runner for the pinned install command. The SDK can be configured with `GUS_OPENPENCIL_SDK_ROOT`; the CLI with `GUS_OPENPENCIL_CLI_ROOT`. Apple static font faces are expected under `/Library/Fonts/` on macOS.

All commands run from the repository root. Run checks sequentially. These tools do not build Gus, launch a simulator or contact a media server.

## Combined document

`combine.mjs` uses the CLI's installed OpenPencil 0.16 SDK to transfer all artboards and dependencies into a fresh document, deduplicate equivalent resources, and save [Gus.fig](../../Gus.fig). It preserves editable text, components, auto-layout and variables. It does not modify the 82 inputs. Build and verify sequentially through the CLI:

```sh
Design/References/Source/openpencil eval 'Design/Gus/watchOS-46mm/Dark/01 Watch.fig' \
  --code 'const m=await import("file://"+process.cwd()+"/Design/References/Source/combine.mjs"); await m.combine()' --json
Design/References/Source/openpencil eval 'Design/Gus/watchOS-46mm/Dark/01 Watch.fig' \
  --code 'const m=await import("file://"+process.cwd()+"/Design/References/Source/combine.mjs"); await m.verify()' --json
Design/References/Source/openpencil fonts Design/Gus.fig --json
```

The small Watch file initializes the headless CLI; the merge creates a separate graph and never writes to that seed. [combined-manifest.json](../combined-manifest.json) maps every source artboard to its saved page and ID, records source-file hashes and compares saved SVG output. See [combined acceptance](../QA/combined-acceptance.json) for the desktop-import limitation. Regeneration overwrites edits made directly in the combined candidate; continue maintaining the split inputs until native-editor usability and a single-file maintenance workflow are established.
