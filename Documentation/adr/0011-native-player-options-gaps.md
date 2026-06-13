# ADR 0011: Native player options gaps

## Status

Accepted

## Context

Gus presents itself as a native Apple app and should use Apple player chrome instead
of app-owned playback overlays. The custom video-player options button has been
removed from the non-tvOS video surface. SharePlay remains implemented through
Group Activities and `AVPlaybackCoordinator`, but Gus no longer exposes a custom
in-player menu for Jellyfin-specific actions. SharePlay launch is now intentionally
outside player chrome: eligible item detail screens present Apple's native
`GroupActivitySharingController` where Apple exposes that system sheet.

Current Apple SDK shape:

- `AVPlayerViewController.transportBarCustomMenuItems` exists for tvOS only. The
  SDK marks it unavailable on iOS, watchOS, and visionOS, and there is no matching
  `AVPlayerView` hook on macOS.
- `AVPlaybackCoordinator.coordinateWithSession(_:)` coordinates an active player
  with a Group Activities session, but it does not add a SharePlay start/leave
  action to AVKit player chrome.
- `GroupActivitySharingController` is a native SharePlay picker surface, not a
  documented AVKit player-options item. It is available through UIKit on
  iOS/iPadOS/visionOS and through AppKit on macOS; tvOS can join and coordinate
  Group Activities sessions but does not expose the sharing controller.

## Decision

The video player should stay on system chrome. Do not reintroduce a floating
custom options button for Jellyfin playback controls. Until Apple exposes native
hooks that fit these controls, Gus should prefer:

- pre-playback Settings for defaults such as streaming quality,
- the native SharePlay sharing controller from item detail, outside the player,
- native AVKit controls where they already exist,
- tvOS `transportBarCustomMenuItems` where Apple provides that native transport
  extension point, and
- documented follow-up issues for platform gaps.

## Gaps Left By Removing The Custom Button

| Gap | Current behavior | Waiting on Apple |
| --- | --- | --- |
| Audio stream selection | tvOS can still use AVKit's native transport menu hook. iOS, iPadOS, macOS, and visionOS have no custom player button for Jellyfin audio stream changes. | A cross-platform AVKit player-options API, or provider-backed media-selection callbacks that let an app map a selected option to Jellyfin stream-index rebuilds. |
| Subtitle selection | tvOS can still expose native transport menu items. Other platforms rely on manifest/default subtitle behavior and have no in-player custom subtitle picker. | A system player UI hook for provider-backed subtitle choices, including server-side transcode/rebuild selection when HLS alternates are not enough. |
| Streaming quality / transcode profile | The Settings streaming-quality default applies before playback and is sufficient for the native-first app scope. Issue #7 was closed as not planned. | No active tracking; revisit only if Apple adds a native quality-options surface that clearly fits provider-backed stream rebuilds. |
| Chapters and next-up actions | Store plumbing remains, but non-tvOS system chrome has no app-supplied chapter or "play next" command from the removed menu. Auto-play can still advance when enabled. | Cross-platform player-chrome hooks for provider-supplied chapters and next-item actions without a custom overlay. |
| SharePlay start/leave | Eligible item detail screens can start SharePlay through the native `GroupActivitySharingController` on iOS/iPadOS/visionOS/macOS. Incoming SharePlay sessions still route to the item and the active player still coordinates through `AVPlaybackCoordinator`. Leaving/ending remains in Apple's system SharePlay controls. | Issue #8 tracks the item-detail native launch surface and any remaining platform follow-up. No custom in-player SharePlay menu should be restored. |
| visionOS 3D viewing override | Automatic 3D/spatial detection, spatial badge, fallback notices, and Cinema rendering remain and are sufficient. Issue #10 was closed as not planned. | No active tracking; add a native override only if Apple provides a system-presented viewing-mode surface that fits Gus. |
| macOS video AirPlay picker | `AVPlayer.allowsExternalPlayback` remains enabled, AVKit/system video behavior is the native default, and audio playback still has its route picker. Issue #11 was closed as not planned. | No active tracking; do not restore a custom video overlay solely for routing. |

## Reintroduction Rule

Any replacement for these controls should be system-presented. A future change can
map Jellyfin options back into the player only when Apple provides a documented
native surface for that platform, or when a platform already has one such as tvOS.

## Tracking Issues

- [#6](https://github.com/eslutz/A-Playa-Named-Gus/issues/6) - Map Jellyfin audio and subtitle selection to native player options
- [#8](https://github.com/eslutz/A-Playa-Named-Gus/issues/8) - Expose SharePlay start and leave from native player or system controls
- [#9](https://github.com/eslutz/A-Playa-Named-Gus/issues/9) - Map chapters and next-up actions to native player controls

Closed as not needed:

- [#7](https://github.com/eslutz/A-Playa-Named-Gus/issues/7) - Streaming quality remains a Settings-level default
- [#10](https://github.com/eslutz/A-Playa-Named-Gus/issues/10) - Automatic visionOS 3D handling is sufficient
- [#11](https://github.com/eslutz/A-Playa-Named-Gus/issues/11) - macOS video routing relies on native AVKit/system behavior
