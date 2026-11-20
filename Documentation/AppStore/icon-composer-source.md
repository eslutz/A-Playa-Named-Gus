# Editable Icon Composer source

## Editable source

Open [AppIcon.icon](../../Resources/AppIcon.icon/) directly in Icon Composer.
The sibling website mark (`../Gus.website/src/assets/gus-mark.svg` from the app
checkout root) is the brand reference, not an input to the app asset generator.
Preserve the rounded connected G in the rear group and the smaller overlapping
mist play symbol in front. The [SVG layers](../../Resources/AppIcon.icon/Assets/)
contain the ice-to-teal G and mist play geometry; the
[material settings](../../Resources/AppIcon.icon/icon.json) control the opaque
deep-teal gradient, G/play translucency, neutral shadows, and play refraction.
Keep the SVGs editable and free of baked effects or outer masks.

## Platform assets

- [XcodeGen](../../project.yml) includes the native package for iOS/iPadOS,
  macOS, and GusWatch. The source asset catalogs retain
  [iOS and Mac raster artwork](../../Resources/Assets.xcassets/AppIcon.appiconset/)
  and [Watch raster artwork](../../Resources/Watch/Assets.xcassets/AppIcon.appiconset/).
  Keep default full-color iOS and Watch store PNGs opaque; the
  [CI alpha check](../../Scripts/check-app-icons.py) checks those defaults,
  not appearance variants or rendering.
- tvOS and visionOS use native three-layer background/G/play stacks. Their
  generator reads the SVGs, not Icon Composer's material settings. It uses a
  separate 95% arrow opacity for visual weight; do not treat that as equivalent
  to Icon Composer translucency or refraction.

## Regenerate and review

Run `swift Scripts/generate-platform-icons.swift` from the repository root after
changing shared icon geometry. It regenerates tvOS/visionOS stacks, static
tvOS Top Shelf fallbacks, and [review composites](#generated-platform-icon-viewer),
not the Icon Composer package or iOS/Mac/Watch PNGs.

Use the [Apple app icon guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons).
Review legibility at small sizes, system masks, default/dark/monochrome and
available clear/tinted variants. Composites and compilation do not establish
native appearance, lighting, focus, or parallax. Keep runtime/physical checks
distinct and within the [validation policy](pipeline-policy.md).

## Diagnose default PNG upload rejections

For icon-alpha rejection codes 90396 or 90717, inspect the exact signed artifact
and affected platform. Check the default iOS and embedded Watch PNG mappings
with `python3 Scripts/check-app-icons.py`. If the raster defaults need repair, use
`Scripts/flatten-app-icon-background.swift` and verify that it changes only
transparency as intended. Do not flatten Mac artwork or supported iOS appearance
variants to address a default icon rejection.

## Generated platform icon viewer

Open [the layer viewer](../Reviews/platform-icon-review/index.html) to compare the current generated assets,
change their displayed size, and toggle layers. The actual platform layers
are unmasked; the preview composites illustrate system-mask clearance.

visionOS uses three 1024 × 1024 PNGs with space for circular masking. tvOS
has 400 × 240, 800 × 480, and 1280 × 768 layer sizes. Review padding and
overlap in the viewer; the composite is not evidence of native lighting,
focus zoom, or parallax at runtime.
