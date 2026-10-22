# Contrast and style review — October 20, 2026

Design-only corrections are complete for the reviewed discrepancies. App source remains unchanged at `d715c05`. Current work is in **Split/** and the regenerated preview; the preserved master/review snapshots are older.

## Corrections

- Replaced 9,496 repeated paint occurrences of light secondary-gray approximations `#77777C` / `#78787D` with `#6C6C70`, providing at least 4.6:1 against white and `#F2F2F7`. Source uses adaptive `.secondary`; this literal is a documented static design approximation, not a measured native color or an app change.
- Added 35,195 matching color-variable bindings and renamed 78,274 generic layers. Theme bindings were selected only for unique matches; ambiguous black/white matches remain unchanged. Existing shared typography remains intact.
- Repaired 32 Mac request metadata rows across regular/narrow and light/dark parts. Source `.subheadline` rows retain 11pt text / 14pt line height; 180pt value space prevents wrapping. Saved-file readback confirms a single 14pt manager-value line at y=0. Browser comparison with `mac-narrow-window.png` confirms aligned labels and values; native chrome and optical metrics remain approximate.
- Re-rendered 82 first-artboard proofs and 31 additional sampled artboards with strict installed-font resolution. Reviewed all 14 primary contact sheets and selected detail/setup/Watch renders. No new overlapping or missing content was seen in those samples. This does not establish individual visual acceptance of all 2,896 artboards.

## Remaining contrast flags

Raw contrast flags fell from **6,868 to 675**, including repeated adaptations. They remain reported:

| Category | Count | Disposition |
|---|---:|---|
| Source accent `#4F7C82` on grouped `#F2F2F7` | 371 | 4.14:1 for small text. Exact asset color retained; remains a source/design accessibility limitation. |
| Semantic red approximation `#FF3B30` on white/grouped | 196 | 3.54:1 / 3.17:1 for small text. Retained to represent source `.red`; remains a limitation without OS/material-specific runtime evidence. |
| Subdued empty fields and disabled controls | 92 | Preserved distinction from enabled actions. Includes placeholders; this is not a blanket exemption for placeholder contrast. Native Increase Contrast remains unverified. |
| Play-symbol background false positives | 16 | Checker walks ancestor fills and misses the contrasting sibling circle. Rendered triangles contrast with their circles. |

`contrast-detail.json` records color pairs and example paths. There are **112 generic minimum-12pt warnings** involving native Mac captions/subheadlines; source sizes are retained. The typography lint rule checks font-variable bindings and ignores `textStyleId`; 14 shared text styles per file were independently verified. Generic grid, integer geometry, nesting and auto-layout preferences do not establish source equivalence. Remaining ambiguous bindings and names are informational. No clean-lint, WCAG-certification or pixel-perfect claim is made.

## Verification and limits

All 82 files pass count, strict-font export and unchanged-input checks. All 2,896 unique artboards retain finite geometry and valid component/style references. Browser checks confirm corrected gray paints, Settings scrolling and Back restoration, appearance switching, Watch recovery/end clamping, narrow Mac metadata and confirmation-only actions. No console warnings/errors were observed in exercised flows. All 25,806 recorded targets and 825 scroll-mask mappings resolve.

Native OpenPencil whole-app prototype reactions remain unsupported by the installed tooling; the HTML companion implements navigation and scrolling. Every transition and physical gesture was not individually exercised. System sheets, pricing, materials, Dynamic Type and other runtime-only boundaries retain the limitations in the main README.
