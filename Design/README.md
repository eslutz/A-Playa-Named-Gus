# Gus designs

**[Gus.fig](Gus.fig)** combines all **3,016 editable artboards** into one 4.4 MiB document: 2,896 current-app references and 120 proposed Seerr/Discover designs. Its 31 pages separate platforms, appearances, proposals, components and guidance. The CLI saved-file checks pass. The desktop editor opens it, but document and page preparation exceed the CLI’s 20-second response limit; everyday editing performance remains unverified.

The **82 files in [Gus/](Gus/)** remain the maintained inputs and practical editing fallback. [SCREEN-COVERAGE.md](SCREEN-COVERAGE.md) links each by platform, appearance and feature. The combined document is a generated review candidate; regeneration replaces edits made directly in it. Keep changes in the maintained inputs until a single-file editing workflow is validated.

## Review

Open [the interactive preview](Exports/Preview/Preview.html), then choose **Current app** or **Discover proposal**. Browser exports and their required scene data live together in `Exports/Preview/`. The preview uses synthetic data and does not connect to a server. To serve it locally, run:

```sh
python3 Design/References/Source/serve-preview.py
```

Open the printed local URL. Stop the server when finished.

For Seerr in the combined document, choose a **Proposal** page. In the split collection, open the matching `Gus/<layout>/<appearance>/05 Discover.fig` and select **Discover Proposal**. The same split file retains the existing app on **App Screens**, with proposal resources grouped in **Components** and **Guide & Coverage**. Read [DISCOVER.md](DISCOVER.md) for behavior, platform adaptation and implementation boundaries.

## Contents and maintenance

- `Gus.fig`: combined review candidate, generated from all 82 maintained files; the original files remain intact.
- `Gus/`: maintained editable documents, organized by platform, appearance and feature. Each file stands alone with its required components and variables.
- `SCREEN-COVERAGE.md`: file index and current/proposed artboard counts. `References/coverage.csv` provides the detailed screen/source matrix.
- `DISCOVER.md`: specification for the expanded Seerr integration.
- `Exports/Preview/`: shared browser review and required scene exports.
- `References/QA/`: validation records and selected visual proofs. See [the detailed review notes](References/README.md) for limitations and historical evidence.
- `References/Source/`: retained generators, manifests and font helpers. See [maintenance instructions](References/Source/README.md) and [Discover regeneration](References/Source/discover/README.md).

This follows [PumpSync’s design organization](https://github.com/eslutz/PumpSync/tree/main/Design). Gus retains platform/feature inputs and generation tools alongside the combined candidate. Update affected editable files, the combined document, preview, coverage and validation records together. Temporary intermediate files belong outside the repository.

## Fidelity and implementation boundaries

App source checkpoint: `d715c05`, October 20, 2026. Current SwiftUI source governs existing behavior. The expanded Discover proposal is a design target; it does not establish that the new behavior is implemented. Proposal coverage includes all 51 app-owned phone states in both appearances and 18 selected adaptive compositions; native system surfaces and other device permutations are documented separately. Watch has no Discover destination.

The integration checks compare saved SVG output for current and proposed screens, validate references and geometry, and check fonts and all 120 proposal raster exports. Current-app raster evidence remains sampled. Historical current-app checks are separate from proposal checks. These do not establish pixel-perfect runtime equivalence, accessibility compliance or complete native-editor interaction acceptance. The proposal preview uses static viewports; current-app scrolling remains available.

Apple-owned sheets, native materials, Dynamic Type, keyboard/focus/remote/gaze behavior and live Seerr requests require runtime acceptance. No app source was changed for this design organization. `Design/` is repository documentation outside the app’s XcodeGen source/resource paths and is not bundled into Gus.
