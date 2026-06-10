# Accessibility Readiness

Status: required before public release and App Review submission.

Public URL: `https://gus.ericslutz.dev/accessibility`

A Playa Named Gus should support Apple platform accessibility features with native SwiftUI,
UIKit/AppKit, tvOS, visionOS, AVKit, and system accessibility APIs wherever possible. The
goal is for major flows to remain usable across iPhone, iPad, Mac, Apple Vision Pro, and
Apple TV — plus the watchOS companion — with the accessibility features Apple exposes to
the app.

## Public Accessibility Page

`/accessibility` must explain:

- Gus is designed to support Apple platform accessibility features.
- Supported platforms include iPhone, iPad, Mac, Apple Vision Pro, and Apple TV.
- Gus supports or plans to support VoiceOver, Voice Control, Larger Text, Dark Interface,
  Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, Captions, and
  Audio Descriptions where available.
- Captions and audio descriptions are supported when available as tracks in the user’s
  Jellyfin media.
- Users can report accessibility issues through `https://gus.ericslutz.dev/support`.

The page should avoid claiming support that has not been verified on the relevant platform.
If a feature depends on AVKit, Jellyfin metadata, system settings, or platform availability,
state that dependency plainly.

## Feature Requirements

### VoiceOver

- Provide meaningful accessibility labels, hints, traits, and values.
- Ensure all interactive controls are reachable and understandable.
- Verify server selection, sign-in, home, library grids, item detail, search, settings,
  downloads, playback, media controls, and errors are navigable.
- Mark section headers and grouped metadata so rotor navigation remains useful.

### Voice Control

- Ensure buttons, controls, menus, search fields, playback controls, and navigation
  elements have clear accessible names.
- Avoid unlabeled icon-only controls; icon buttons must have labels even when visual text
  is not shown.
- Use stable visible or accessibility names for repeated actions such as Play, Resume,
  Download, Delete Download, Search, Sign Out, and server selection.

### Larger Text / Dynamic Type

- Support Dynamic Type where platform conventions allow.
- Validate key screens at large accessibility text sizes.
- Ensure text does not clip, overlap, obscure primary controls, or make connect, browse,
  search, settings, and playback flows unusable.

### Dark Interface

- Support system light and dark appearance, plus the in-app override (Settings →
  Appearance: System / Light / Dark, applied via `preferredColorScheme`).
- Use semantic colors and materials; avoid hardcoded colors that reduce readability.
- Verify the Winter Chill brand colors, posters/backdrops, overlays, badges, Liquid
  Glass surfaces, and playback surfaces in both appearances and under all three
  appearance-setting choices.

### Differentiate Without Color Alone

- Do not rely only on color to communicate selection, state, warnings, errors, focus,
  download availability, played/unplayed state, or playback mode.
- Pair color with text, labels, icons, shapes, badges, or traits.

### Sufficient Contrast

- Validate text, controls, focus states, buttons, icons, badges, and overlays in light and
  dark mode.
- Pay extra attention to artwork-heavy screens, translucent materials, media overlays, and
  selected/focused states on Apple TV and visionOS.

### Reduced Motion

- Respect system Reduce Motion settings.
- Reduce or replace animations, transitions, parallax, autoplay motion, and immersive
  effects that could cause discomfort.
- Verify Apple TV and visionOS experiences remain comfortable when motion is reduced.

### Captions

- Support available subtitle and caption tracks from Jellyfin media.
- Ensure caption selection is available during playback where AVKit and the platform
  expose it.
- Preserve user caption preferences where practical without overriding system behavior.

### Audio Descriptions

- Support available audio description or alternate audio tracks from Jellyfin media where
  provided.
- Ensure alternate audio track selection is available during playback where AVKit and the
  platform expose it.

## Platform Validation Matrix

| Platform | Required checks |
|---|---|
| iPhone and iPad | Touch targets, Dynamic Type, VoiceOver navigation, Voice Control names, dark mode, contrast, reduced motion, playback controls, captions, and alternate audio. |
| Mac | Keyboard navigation, focus behavior, menu commands, VoiceOver, scalable layouts, dark mode, contrast, captions, and alternate audio. |
| Apple TV | Focus Engine behavior, remote navigation, clear focus indicators, VoiceOver, sufficient contrast, captions, and audio track selection. |
| Apple Vision Pro | Gaze/gesture interaction, focus behavior, readable text, comfortable motion, VoiceOver where applicable, spatial UI accessibility, captions, and alternate audio. |
| Apple Watch | VoiceOver on the remote/resume/browse/audio/downloads/settings pages, Digital Crown navigation, labeled icon-only transport controls, Dynamic Type, and dark-interface legibility. |

## Release Checklist

- [ ] `https://gus.ericslutz.dev/accessibility` is live over HTTPS.
- [ ] The app website links to `/accessibility`.
- [ ] The support page links to `/accessibility`.
- [ ] App Store accessibility disclosures match verified implementation.
- [ ] VoiceOver is tested on iPhone and iPad.
- [ ] VoiceOver and keyboard navigation are tested on Mac.
- [ ] Focus Engine behavior is tested on Apple TV.
- [ ] Readable text and comfortable interaction are tested on Apple Vision Pro.
- [ ] VoiceOver and Digital Crown navigation are tested on the Apple Watch companion.
- [ ] Dynamic Type / Larger Text is tested on key screens.
- [ ] Dark mode is tested on key screens.
- [ ] Sufficient contrast is reviewed in light and dark mode.
- [ ] Reduced Motion is tested for navigation, playback surfaces, Apple TV, and visionOS.
- [ ] Caption selection is tested with media that exposes subtitle/caption tracks.
- [ ] Alternate audio / audio description track selection is tested with media that exposes
      suitable tracks.
- [ ] Accessibility issues found during release testing are filed, prioritized, and linked
      from the release checklist.
