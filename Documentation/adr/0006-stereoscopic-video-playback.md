# ADR 0006: Stereoscopic video playback

## Status

Accepted

## Context

Jellyfin exposes frame-packed 3D through `BaseItemDto.video3DFormat`, but Apple
spatial video (MV-HEVC) is usually surfaced as ordinary HEVC. Gus also biases normal
network playback toward HLS transcoding so `AVPlayer` receives a broadly playable stream.
That bias cannot be used for 3D: server-side transcoding flattens stereo into 2D.

Apple platforms do not provide a decoder for Blu-ray MVC. Non-visionOS platforms do not
have a stereo presentation surface for this app, so their correct behavior is 2D playback.

## Decision

Gus supports visionOS stereoscopic playback in two tiers:

- MV-HEVC spatial video uses the existing AVKit path. `Media3DDetector` detects it
  conservatively from HEVC multiview/spatial stream hints, and the visionOS player offers
  a manual Spatial viewing mode for files Jellyfin does not flag.
- Jellyfin SBS/TAB frame-packed formats use the Gus Cinema `ImmersiveSpace`. The same
  `AVPlayer` feeds a RealityKit `VideoMaterial` screen, and `Stereo3DScreenMetrics`
  records the left/right sampling regions and squeeze correction for each layout.
- MVC remains unsupported and falls back to 2D with a user-visible notice.

Every stereo-capable path requests direct play. `StreamURLBuilder` disables transcoding
for stereo resolution attempts and returns a typed fallback when direct play is not
available, allowing `PlaybackStore` to continue in 2D with a notice.

## Consequences

The implementation stays Apple-first: AVKit handles native spatial playback, RealityKit
hosts the immersive frame-packed screen, and no third-party decoder is added. The user can
choose Auto, 2D, or Spatial on visionOS to handle MV-HEVC metadata gaps and comfort.

Simulator verification confirms routing, buildability, and the immersive screen. True
stereo separation for MV-HEVC and frame-packed SBS/TAB still requires Vision Pro device
verification because the simulator renders monoscopically.
