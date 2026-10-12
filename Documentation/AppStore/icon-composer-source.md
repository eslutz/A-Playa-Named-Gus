# Editable Icon Composer source

Recreated on 2026-10-12 in Apple Icon Composer from the Gus website mark, then redesigned with a connected G silhouette and a smaller foreground play symbol. This is a reconstruction, not recovery of the missing original document.

Open `Resources/AppIcon.icon` directly in Icon Composer. Its package contains `icon.json` and two editable SVG assets. `Gus-G.svg` combines the curve and arm into one continuous rounded stroke; `Gus-Play.svg` overlaps the right shoulder in a separate foreground depth group. The detached arm asset has been removed. The G uses 30% translucency, the play uses 20%, both use neutral shadows at 25% opacity, and play refraction strength is 0.12. The deep teal background and icy blue palette remain.

The play symbol was enlarged a further 18% and moved 3 SVG units right while retaining its vertical center. Its translucency was reduced to 20% to strengthen its outline. Default iOS/macOS at 60pt @1x and circular watchOS at 30pt @2x were inspected at 100% zoom in Icon Composer. The user approved this revision on 2026-10-12. Earlier screenshots in `icon-composer-evidence/` predate this redesign; dark and monochrome appearances and on-device rendering require a fresh review.

`project.yml` includes the native package for iOS/macOS and GusWatch, with an explicit `wrapper.icon` reference in the generated Xcode project. tvOS and visionOS retain their existing platform-specific asset catalogs. Existing opaque iOS/Watch PNGs remain as fallback artwork for older systems.

The preceding PNG-only commit f354c7a passed all 13 GitHub CI jobs. Cloud Build 8 compiled the new resource integration on all four platforms with zero issues. CI run 38242041231 completed with 12/13 jobs successful; the iPad native audio completion case failed without a native end notification. The full diagnostic is retained. The protected PR and new test-gated Cloud release must pass before internal TestFlight availability can be confirmed.

## Apple app icon guideline review — 2026-10-12

The earlier source was reviewed against the [Apple app icon HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons), including its June 2026 Liquid Glass guidance, using the native package and saved previews.

- The recognizable G/play mark uses two simple SVG foreground layers, with rounded endpoints and no nonessential words, photos, interface screenshots, or Apple hardware imagery.
- Foreground edges are crisp; the centered artwork leaves space for rounded-square and circular system masks. The SVG canvases are square and do not bake in an outer mask.
- The full-bleed background is an opaque Icon Composer teal gradient, rather than transparent or black. Highlights, shadows, refraction, and translucency are configured through Icon Composer; the SVG artwork contains no baked shadows, bevels, or blur filters.
- Default, dark, and monochrome previews retain the same mark. System-generated clear/tinted variants are supported, but a complete on-device clear/tinted appearance review is still pending; saved previews alone do not establish that acceptance.
- iOS/iPadOS, macOS, and watchOS use the native package. tvOS and visionOS keep their separate platform image stacks, as Apple specifies; this review does not newly verify their parallax safe zones or motion behavior.

No design change was needed for the inspected native package. Remaining appearance and platform motion checks must stay distinct from successful compilation and TestFlight upload validation.
