# Vision Pro capabilities

Gus uses native visionOS navigation and AVKit playback on Apple Vision Pro,
including expanded and immersive experiences where available. Gus Cinema is
the existing RealityKit playback space, not a catalog of selectable environments.

## Current playback paths

| Source | Current source behavior |
| --- | --- |
| Recognized MV-HEVC spatial video | Native AVKit spatial playback when the server can direct-play the selected source. This is separate from Gus Cinema's frame-packed renderer. |
| Side-by-side or top-and-bottom (SBS/TAB) | Gus Cinema splits the packed frame into tagged left/right eye buffers and presents them through RealityKit. This path needs a compatible directly playable source. |
| Blu-ray MVC, no usable 3D signal, or unsupported/non-direct source | Normal 2D delivery where playable, with an unsupported/fallback notice where applicable. Other platforms use 2D. |

Jellyfin metadata may omit a usable MV-HEVC hint. Do not infer spatial support
from HEVC alone or promise a manual override the app does not provide. See
[ADR 0006](adr/0006-stereoscopic-video-playback.md) and the
[engineering guide](engineering-guide.md#playback).

## Planned: complete 3D video playback

Qualify recognized MV-HEVC, full and half SBS/TAB, missing metadata, unsupported
MVC and non-direct fallback with representative, rights-cleared media. Local
simulator checks can prove routing, controls and error handling, not stereo
separation. Separately authorized Vision Pro validation still needs left/right
separation, audio/video sync, accessibility, comfort, transition stability,
position retention, and safe return to 2D.

## Planned: custom immersive environments

Prototype one contained user-selectable environment alongside the default.
Preserve the shared playback session and keep the window/default experience
available on exit, interruption, cancellation, or failure. Keep native AVKit
transport and verify selection and safe return without restart or lost
position. Validate accessibility, motion comfort, and performance on Vision Pro.

[Apple's immersive media sample](https://developer.apple.com/documentation/visionos/building-an-immersive-media-viewing-experience)
is a reference for RealityKit and system player docking, not evidence that
docking works with Gus's frame-packed renderer. Verify the AVKit and frame-packed
paths separately before promising both in a custom environment.
