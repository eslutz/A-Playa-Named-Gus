# Gus — Apple App Design

Start with [../SCREEN-COVERAGE.md](../SCREEN-COVERAGE.md). The integrated deliverable contains **82 editable OpenPencil files and 3,016 artboards**: 2,896 current-app references plus 120 proposed Seerr/Discover artboards. Each part has App Screens, Guide & Coverage and Components. Ten existing Discover files also have a **Discover Proposal** page. Shared resources remain inside each standalone file; the proposal adds its own resources without changing the current app references.

All editable app designs, including the Seerr proposal, are in **../Gus/**. Use **[Preview.html](../Exports/Preview/Preview.html)** for the current app or **[Discover proposal mode](../Exports/Preview/Preview.html#discover-proposal)** for the expanded feature. [../DISCOVER.md](../DISCOVER.md) defines its behavior and lists the matching files. Current app and proposed behavior are explicitly labeled; no standalone Seerr master/review file is needed.

Superseded master/review/test copies, old rollback snapshots and duplicate exports were removed on October 20, 2026. The current Split files, feature design, browser data, generators and validation evidence remain.

**Source checkpoint:** `d715c05`, October 20, 2026. No app source was changed. Source takes precedence over older screenshots. Existing Figma work was reconstructed from saved source-based specifications and component definitions; the Figma file was not modified.

## Current verification

The official **OpenPencil CLI 0.16.0** now handles bulk work in headless file mode. The current-app baseline of **82 files / 2,896 artboards** passed expected-count, faithful-font, strict-font-export and unchanged-input checks before proposal integration. The older CLI report records that baseline. Integration additionally compares all current and proposed screen SVGs before and after transfer, so adding the proposal does not change current app visuals. Saved-file readback separately checks shared resources, finite geometry and component/text-style references. Every part retains editable text, vectors and auto-layout. See `QA/cli-acceptance.json` and `QA/split-verification.json`.

One screen from each part was rendered and visually reviewed through the CLI: **82 current proofs**, plus **31 other current split-file proofs**, for **113 distinct sampled artboards** across all ten layouts. This is representative visual review, not individual pixel or accessibility acceptance of every artboard. Current CLI images and contact sheets are in `QA/CLI/`; the other selected renders are in `QA/Split/`.

Historical native-editor evidence: the editor was restarted with explicit approval after a verified interface/rendering crash. Both saved Gus tabs were restored and the current iPhone Discover part opened through the CLI. Its live font status reports faithful fonts with no issues. This is a historical editor session observation, not a current PumpSync process-status check. Repeated desktop loading/closing of all 82 parts is not verified, and permanent prevention of the app's interface bug is not established. File mode avoids that UI for bulk checks.

**Contrast/style review is complete for the sampled discrepancies; lint is not clean.** Contrast flags fell from 6,868 to 675. Remaining cases include exact source accent/red colors, subdued fields/disabled actions and play-symbol background false positives. All are categorized in [QA/Contrast and Style Review.md](QA/Contrast%20and%20Style%20Review.md); native caption sizes and source geometry are preserved. This is not full accessibility or pixel-perfect acceptance.

Current publication checks are summarized in `QA/Discover/acceptance.json`. Targeted shared-preview browser checks are in `QA/Discover/browser-acceptance.json`; the temporary server and test tab were closed.

The integrated proposal has separate evidence in **QA/Discover/**: saved-file checks for all 120 artboards in ten files, faithful-font checks for those files, and 120 strict-font raster proofs. Proposal behavior is not implemented or physically accepted. The current-app baseline reports do not imply acceptance of the proposal.

## Organization and coverage

- **App Screens:** 2,896 artboards, partitioned by layout, appearance and functional area; at most 49 app artboards in one part.
- **Discover Proposal:** 120 proposed Seerr artboards distributed across ten matching Discover files.
- **Guide & Coverage:** source/evidence boundaries, file scope, system-owned sheets, prototype limitations and the proposal guide where applicable.
- **Components:** the current-app foundation has 23 UI/control masters, 45 symbol masters, 14 text styles and 39 variables. Integrated Discover parts include an additional proposal resource group, style definitions and its proposal variables. Per-file totals are recorded in ../Gus/index.json.

There are 187 main-app state specifications and 39 Watch state specifications. Counts include layout/appearance adaptations and do not represent 2,896 distinct destinations.

| Layout | Artboards | Appearance |
|---|---:|---|
| iPhone 402 × 874 | 360 | Light and Dark |
| iPhone landscape 874 × 402 | 360 | Light and Dark |
| iPad portrait 834 × 1194 | 358 | Light and Dark |
| iPad landscape 1194 × 834 | 358 | Light and Dark |
| Mac 1105 × 765 | 358 | Light and Dark |
| Mac narrow 765 × 605 | 358 | Light and Dark |
| Apple TV 1920 × 1080 | 308 | Light and Dark source adaptations |
| Vision 1280 × 960 | 358 | Light and Dark source adaptations |
| Watch 208 × 248 | 39 | Native dark presentation |
| Watch Ultra 224 × 269 | 39 | Native dark presentation |

`coverage.csv` maps inventory artboards to state/source. `navigation.csv` records intended destinations and target availability. Platform-only destinations are filtered: Watch does not gain Discover, and TV does not gain downloads or collection editing.

## Latest source and visual corrections

- Improved the static light secondary-gray approximation for readability; added 35,195 color bindings and descriptive names for 78,274 generic layers. Source accent assets remain unchanged.
- Corrected Mac request metadata baselines and value widths in all four layout/appearance parts.

- iPhone setup: centered Back symbols, correctly sized Cancel controls, safe areas, rounded sheets, grouped fields, Seerr version, source wording and Email/Jellyfin Username variants.
- Mac Discover: corrected sidebar label routes and symbols, compact source-sized catalog/request typography, contained tabs, right-aligned metadata, missing-art alignment, Refresh and request decisions. Removed catalog search from the disconnected introduction in all four Mac layout/appearance variants; source attaches it only to connected content.
- TV: widened value columns so genre, duration, delivery, resolution and language values do not wrap mid-word. Recalculated imported row/separator geometry and retained editable auto-layout.
- Watch: Resume now uses source-sized poster thumbnails, titles, synthetic progress and Play On destinations. The connection/error forms now match the source VStack spacing and footer, with no group separators crossing labels. The blank form retains disabled Connect; a separate preview demo action supplies synthetic progression.
- Preview: Back restores scroll position; nested rails and clipping update navigation targets; background controls are suppressed in 462 menu/dialog scenes.

## Preview and navigation

Open **../Exports/Preview/Preview.html** in a browser with `preview-scenes/` beside it. Select **Current app** or **Discover proposal**. All 3,016 scenes load on demand; the proposal adds 58 static viewports. The editable-file link identifies the matching Split file and page. The current-app baseline has **25,806 potential synthetic navigation links**, Back history, layout/appearance selectors and **825 vertical/horizontal scroll regions**. Every recorded target exists in its layout/appearance; all scroll regions match their SVG masks.

Approved read-only localhost browser testing covered wheel/keyboard scrolling, end limits, nested horizontal rails, scrolled hotspots, Back scroll restoration, layout/appearance switching, Watch filtering, setup progression, menus, confirmation actions, Watch error recovery and revised TV scrolling. No browser console errors were observed in the latest exercised flows. The temporary server was stopped after testing. Every transition and physical touch gesture was not individually exercised. See `QA/browser-acceptance.json`.

Preview controls use synthetic states and do not authenticate, purchase, mutate real requests or contact servers. Menu choices without a represented state rely on the preview Back control. Native OpenPencil component behavior is separate from screen-to-screen navigation: the app-screen layers retain destination labels, while whole-app navigation and scrolling are implemented in the companion HTML. Whole-app native prototype acceptance is not claimed. Proposal actions without an artboard explain that boundary instead of displaying a different device or pretending to perform a real action.

## CLI use

The matching official CLI is installed in `/private/tmp/gus-openpencil-cli`. `Source/openpencil` is a local runner that loads the already-installed static SF Pro Text and SF Compact Text faces into that CLI process. It does not install or rewrite fonts. The default bare CLI could not resolve these family aliases here, so raster checks use this runner with a strict font policy. No online fonts are downloaded.

Examples from the repository root:

```sh
Design/References/Source/openpencil info 'Design/Gus/iPhone/Light/01 Connection and Library.fig' --json
Design/References/Source/openpencil fonts 'Design/Gus/iPhone/Light/01 Connection and Library.fig' --json
```

Providing a file uses headless mode. Commands targeting the running app still use its local connection and can encounter the desktop bug. Installation and command reference: [official CLI documentation](https://openpencil.dev/reference/cli). If the temporary installation is removed, the runner prints the pinned reinstall command. Re-run bulk checks with `python3 Design/References/Source/cli-qa.py`; it does not apply lint fixes or write input designs.

## Runtime evidence and limitations

Existing synthetic runtime references cover selected Home, iPhone setup, Mac setup/search/narrow management, iPad search/accessibility, TV first-use/setup and Vision setup views. References remain under `Documentation/Reviews/2026-10-18-discover/evidence/` and the previous handoff. No app build, simulator, fixture or service was started for this pass.

Most extra platform states do not have matching runtime screenshots. Artwork uses source missing-art placeholders and synthetic titles. Native glass/materials, status bars, focus, control chrome, Dynamic Type, immersive scale, AVKit and system animations remain editable approximations. No enabled Apple native component library was available in OpenPencil. SF Symbols are editable silhouette traces or documented composite approximations.

Requested font families remain SF Pro/SF Compact. Installed static faces are available without substitution, but optical metrics and rendered pixels can differ between CLI and editor. A recorded Home sample comparison differed by about 2.7% of pixels under its stated tolerance; it is not a runtime-app comparison or pixel-perfect claim. See `QA/cli-vs-live-render.json`.

Apple-owned permission, purchase, sharing, import, AutoFill/password-save and authentication sheets are documented at their entry points rather than invented. No StoreKit product or pricing was found in source; runtime prices and purchase/recovery details remain unspecified. Real credential handling, requests, native keyboard focus/avoidance, accessibility behavior and system-sheet presentation remain runtime responsibilities.

The deliverable is local OpenPencil work. No new Figma share link was created.
