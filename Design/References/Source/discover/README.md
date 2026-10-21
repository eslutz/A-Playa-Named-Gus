# Discover design source

The proposal is integrated into the platform/appearance `Design/Gus/**/05 Discover.fig` files on a **Discover Proposal** page. `manifest.json` records all 120 artboards, their editable files and saved node IDs. Behavior is specified in `Design/DISCOVER.md`; review through the shared `Design/Exports/Preview/Preview.html` in Discover proposal mode.

`coverage-contract.json` declares 51 app-owned phone states in both appearances plus 18 selected adaptive artboards. Verification checks this independent inventory against the saved files.

To change the proposal, edit `build.mjs`. Rebuilding creates an intermediate source document under `/tmp/gus-discover-design`, then imports it into the existing Discover parts while preserving the current App Screens. The intermediate master is not a separate project deliverable.

From the repository root, run these sequentially:

```sh
node Design/References/Source/discover/build.mjs --no-png
node Design/References/Source/discover/integrate.mjs
node Design/References/Source/discover/verify.mjs
python3 Design/References/Source/full-preview.py
python3 Design/References/Source/discover/qa.py
```

Integration replaces only the generator-owned proposal page/resources. It compares SVG output before and after transfer for the current app and all proposed artboards, and validates component/style/variable references after saving. Edit generator-owned designs in the source before rebuilding; other pages are preserved.

The process uses the installed OpenPencil 0.16 SDK, local Apple fonts and the shared `Source/fonts.mjs` and `Source/openpencil` helpers. It does not build the Gus app, start simulators or contact a media server. Override temporary build storage with `GUS_DISCOVER_BUILD_DIR` if needed.

`qa.py` renders all 120 proposed artboards sequentially with strict fonts. Its optional `--reuse-unchanged` mode accepts earlier strict proofs only for screens whose exact saved SVG is confirmed unchanged by the latest integration report. This avoids repeating unrelated renders during a focused correction.
