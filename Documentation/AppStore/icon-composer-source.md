# Editable Icon Composer source

Recreated on 2026-10-12 in Apple Icon Composer from the canonical Gus website SVG. The G and play triangle are separate editable vector layers; the original geometry and foreground colors are retained. The native automatic gradient uses brand teal #0B2E33, with system-generated glass, dark, and monochrome appearances. This is a reconstruction, not recovery of the missing original document.

Open `Resources/AppIcon.icon` directly in Icon Composer. Its package contains `icon.json` and the two SVG layers under `Assets/`. Default, dark, monochrome, and circular watchOS previews were inspected and captured in `icon-composer-evidence/`.

`project.yml` includes the native package for iOS/macOS and GusWatch, with an explicit `wrapper.icon` reference in the generated Xcode project. tvOS and visionOS retain their existing platform-specific asset catalogs. Existing opaque iOS/Watch PNGs remain as fallback artwork for older systems.

The preceding PNG-only commit f354c7a passed all 13 GitHub CI jobs. Cloud Build 8 compiled the new resource integration on all four platforms with zero issues. CI run 38242041231 completed with 12/13 jobs successful; the iPad native audio completion case failed without a native end notification. The full diagnostic is retained. The protected PR and new test-gated Cloud release must pass before internal TestFlight availability can be confirmed.

## Apple app icon guideline review — 2026-10-12

Reviewed the current [Apple app icon HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons), including its June 2026 Liquid Glass guidance, against the native package and saved previews.

- The recognizable G/play mark uses two simple SVG foreground layers, with rounded endpoints and no nonessential words, photos, interface screenshots, or Apple hardware imagery.
- Foreground edges are crisp; the centered artwork leaves space for rounded-square and circular system masks. The SVG canvases are square and do not bake in an outer mask.
- The full-bleed background is an opaque Icon Composer teal gradient, rather than transparent or black. Highlights, shadows, refraction, and translucency are configured through Icon Composer; the SVG artwork contains no baked shadows, bevels, or blur filters.
- Default, dark, and monochrome previews retain the same mark. System-generated clear/tinted variants are supported, but a complete on-device clear/tinted appearance review is still pending; saved previews alone do not establish that acceptance.
- iOS/iPadOS, macOS, and watchOS use the native package. tvOS and visionOS keep their separate platform image stacks, as Apple specifies; this review does not newly verify their parallax safe zones or motion behavior.

No design change was needed for the inspected native package. Remaining appearance and platform motion checks must stay distinct from successful compilation and TestFlight upload validation.
