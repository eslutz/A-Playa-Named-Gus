# tvOS and visionOS icon review — 2026-10-12

Status: visually approved by the user on 2026-10-12, including the revised 95% arrow opacity.

Open `index.html` to compare both icons, change their displayed size, and toggle the actual exported layers. `visionOS-preview.png` and `tvOS-preview.png` are static composites. The square/rectangular native layers are unmasked; only review composites are clipped.

## Design

The approved connected G and enlarged, raised play arrow are read directly from `Resources/AppIcon.icon/Assets/`. Both platform stacks have an opaque full-bleed teal gradient in back, transparent G artwork in the middle, and the arrow in front. The arrow uses 95% source opacity for stronger visual weight with a subtle overlap, increased from the initial 80% after visual feedback. Icon Composer translucency/refraction are material settings, not transferable PNG parameters; these are platform-native adaptations, not exact replicas of its glass renderer. No shadows, bevels, highlights, or rounded outer masks are baked into the layers.

visionOS uses three 1024 × 1024 PNGs with room for circular masking. tvOS uses three layers at 400 × 240, 800 × 480, and 1280 × 768. The mark is centered by its geometry and has approximately 15% vertical clearance in tvOS. This is conservative design padding, not proof of every system parallax displacement. Existing static Top Shelf fallbacks at both resolutions also use the new identity.

## Reproduction and validation

Run `swift Scripts/generate-platform-icons.swift` from the repository root. If the default compiler cache is unavailable, add `-module-cache-path /tmp/gus-platform-icon-module-cache` before the script path.

Both isolated platform catalogs compiled successfully with Xcode 27 actool for appletvsimulator and xrsimulator. PNG references, sizes, and RGB background/RGBA foreground formats were checked. The sandbox emitted CoreSimulator service warnings, so this establishes asset compilation, not simulator launch or native lighting/motion acceptance. No application build, device install, or release was performed.

The review page is a composition preview of the exact assets. Native lighting, shadows, focus zoom, and parallax require review in Xcode or on device. The user approved these composition previews; native lighting and motion acceptance remain separate.

Reference: https://developer.apple.com/design/human-interface-guidelines/app-icons/
