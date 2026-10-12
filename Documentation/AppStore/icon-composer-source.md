# Editable Icon Composer source

Recreated on 2026-10-12 in Apple Icon Composer from the canonical Gus website SVG. The G and play triangle are separate editable vector layers; the original geometry and foreground colors are retained. The native automatic gradient uses brand teal #0B2E33, with system-generated glass, dark, and monochrome appearances. This is a reconstruction, not recovery of the missing original document.

Open `Resources/AppIcon.icon` directly in Icon Composer. Its package contains `icon.json` and the two SVG layers under `Assets/`. Default, dark, monochrome, and circular watchOS previews were inspected and captured in `icon-composer-evidence/`.

`project.yml` includes the native package for iOS/macOS and GusWatch, with an explicit `wrapper.icon` reference in the generated Xcode project. tvOS and visionOS retain their existing platform-specific asset catalogs. Existing opaque iOS/Watch PNGs remain as fallback artwork for older systems.

The preceding PNG-only commit f354c7a passed all 13 GitHub CI jobs. Cloud Build 8 compiled the new resource integration on all four platforms with zero issues. CI run 38242041231 completed with 12/13 jobs successful; the iPad native audio completion case failed without a native end notification. The full diagnostic is retained. The protected PR and new test-gated Cloud release must pass before internal TestFlight availability can be confirmed.
