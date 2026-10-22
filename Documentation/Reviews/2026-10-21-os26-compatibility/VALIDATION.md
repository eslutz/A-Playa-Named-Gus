# OS 26 compatibility with OS 27 features

The minimum deployment target is 26.0 on iOS/iPadOS, tvOS, visionOS,
macOS, and watchOS, including the embedded Watch app and tvOS Top Shelf
extension. OS 27.x features remain enabled where available. This is a fixed
26.0 floor; future changes to the support window require a deliberate review.

## Implementation

- `project.yml` is authoritative; the generated project carries 26.0 in Debug
  and Release for every platform. The SDK/toolchain requirement remains Xcode
  27.1 or newer for the existing iOS Duo layout.
- Native asynchronous audio-session activation remains in use on iOS/tvOS/
  visionOS 27 and watchOS 26/27. OS 26 iOS/tvOS/visionOS use `setActive(true)`.
  Deactivation uses the asynchronous API on OS 27 and `setActive(false,
  options: .notifyOthersOnDeactivation)` on OS 26. Both paths use the existing
  detached serial operation queue, preserving activation/teardown order and
  avoiding synchronous audio-session work on MainActor.
- tvOS 27 retains the native tab sidebar account header. tvOS 26 presents the
  same native account menu in a top safe-area inset; profile editing, saved-user
  switching, reauthentication, and Manage Accounts remain available.
- visionOS 27 retains the sample-buffer receiver API for stereo rendering.
  visionOS 26 feeds the same tagged stereo buffers through the native renderer
  and synchronizer, checking readiness before enqueueing. Both paths flush on
  seek, item replacement, and invalidation.
- iOS 26.1 and later retain the conditional native tab accessory. iOS 26.0
  uses the existing Now Playing return bar because the `isEnabled` overload
  arrived in 26.1. Neither path branches the navigation subtree on player
  visibility or size class. The availability-guarded iOS 27.1 Duo arrangement
  is unchanged.
- README, project guidance, roadmap, wiki Getting Started, and website support
  source document the approved compatibility policy. Existing historical
  validation reports retain their original OS baselines.

## Validation

Xcode 27.1 (`27A9275`) passed all six Debug build lanes through
`Scripts/run-warning-free.py`, with zero warnings and zero errors:

| Lane | Destination | SDK |
|---|---|---|
| iPhone | generic iOS Simulator | 27.1 |
| iPad | installed iPad Pro 11-inch (M5), iOS 26.5 | 27.1 |
| Apple TV / Top Shelf | generic tvOS Simulator | 27.0 |
| Vision | generic visionOS Simulator | 27.0 |
| Mac | native arm64 | 27.0 |
| Watch | generic watchOS Simulator | 27.0 |

Build commands use the saved package pins. Simulator builds use explicit ad-hoc
signing to avoid local automatic-signing overrides. The native Mac build uses
`CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`, matching
`Scripts/validate-release.py`; it establishes compilation, not signed capability
acceptance. The existing local provisioning profile lacks the app's existing
Push Notifications/iCloud capabilities. No provisioning state was changed.
Built app plists, the Watch app, and Top Shelf all declare a 26.0 minimum.

The same tvOS app installed and launched on installed tvOS 26.5 and 27.0
simulators. This proves installation/launch only, not authenticated browsing,
account-menu focus, live Jellyfin playback, or Top Shelf presentation. Both simulators were
shut down after the check, restoring their initial power state.

Project consistency (`Scripts/check-cloud-project.py`), changed Swift source
formatting, whitespace checks, String Catalog JSON, warning-gate self-tests
(11 tests), and website `npm test` (3 tests) passed. Focused audio/TV playback
regressions passed on both tvOS 26.5 and 27.0: **6 tests in 4 suites per OS**
(including the replay test's two parameter cases), with zero build warnings.
The selected suites cover native audio completion/replay, local-only replay
following deletion, serialized audio-session operations, background video
preparation, and track-rebuild speed/pause state. Test commands use the
`Gus tvOS Unit Tests` scheme with these selectors:

```text
-only-testing:GusTVOSTests/PlaybackAudioSessionTests
-only-testing:GusTVOSTests/PlaybackIntegrationTests/AudioReplayTests
-only-testing:GusTVOSTests/TVPlaybackLifecycleTests
```

Both test simulators were shut down after execution. Machine-readable build,
test, and smoke results are in [results.json](results.json).

## Remaining release gates

- Exact OS 26.0 runtime execution: installed 26.x simulators are 26.5.
- Physical Apple TV on tvOS 26.6: signed installation, account menu and remote
  focus, direct/transcoded playback, audio handoff/teardown, and Top Shelf.
- Runtime acceptance on the other platforms and current OS 27.x devices,
  including the existing Duo behavior.
- Required GitHub CI, signed archives, Xcode Cloud, and TestFlight distribution.
  No deployment, upload, or distribution is performed by this change.
