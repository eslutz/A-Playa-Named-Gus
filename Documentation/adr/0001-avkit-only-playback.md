# ADR 0001: AVKit-only playback

## Status

Accepted

## Context

Gus needs video playback across iOS, iPadOS, tvOS, visionOS, and macOS while preserving the
project mandate to prefer Apple frameworks over custom or third-party runtime code.
Swiftfin uses VLCKit, but Gus is intentionally not copying that stack.

## Decision

Gus uses AVKit playback surfaces (`VideoPlayer` where SwiftUI provides it and
`AVPlayerViewController` on tvOS) with `StreamURLBuilder` asking Jellyfin for AVPlayer-
friendly HLS transcoding when direct playback is not suitable.

## Consequences

Playback behavior stays aligned with platform controls, focus, AirPlay, Picture in Picture,
and system media integrations. Format support depends on AVPlayer and Jellyfin server
transcoding rather than bundling a broader third-party decoder.
