# ADR 0005: Offline downloads background and transcode scope

## Status

Accepted

## Context

A Playa Named Gus playback is intentionally AVKit-only. Network playback asks Jellyfin for
posted playback info with a device profile biased toward HLS transcoding so `AVPlayer`
receives a playable stream. The first offline download cut downloaded only original files
with `JellyfinClient.download(for:)` and hid the action for sources outside the app's
direct-play profile. That kept scope small, but it left common Jellyfin libraries with
MKV, HDR, or non-AAC audio unable to download at all.

Long-running foreground downloads were also fragile. Large files can outlive an active app
session, and users expect a native download to survive suspension and expose pause, resume,
and delete controls.

tvOS is also different from the other supported platforms. Its app storage is
system-purgeable and is not a reliable place for persistent local media without a separate
On-Demand Resources design.

## Decision

### October 2026 refinement

Downloads now preserve compatible video and audio independently. MKV sources with device-supported H.264 or HEVC and supported audio are remuxed to MP4; incompatible streams are encoded to H.264 or AAC while compatible streams are copied. Native HEVC support, bit depth/profile, HDR capability, source resolution, and up to eight audio channels inform the request. Offline subtitle sidecars remain outside the scope.

Jellyfin's progressive muxer emits `hev1` for copied HEVC, which Apple AVFoundation rejected in native decode validation. Native passthrough export retains that tag. A bounded ISO BMFF metadata correction therefore changes the HEVC sample entry to `hvc1` only after validating that its codec configuration contains VPS, SPS, and PPS parameter sets; encoded media bytes and file offsets remain unchanged. This narrow metadata operation is the exception to the system-framework preference, validated against a real Jellyfin remux and Apple native decoding.

Completed URLSession files are moved into app-owned temporary storage synchronously before the delegate callback returns. Final compatibility normalization and account-scoped persistence occur after that ownership handoff.

The stream-preserving policy supersedes the original forced H.264/stereo/8-bit parameters below.

A Playa Named Gus downloads are:

- Background-capable: transfers use a stable native background `URLSession` identifier
  (`dev.ericslutz.gus.downloads`) owned by `DownloadSessionCoordinator`.
- Originals when possible: AVPlayer-native sources still use `Paths.getDownload(itemID:)`.
- Transcoded when needed: incompatible sources call `Paths.getPostedPlaybackInfo` to pick a
  media source, then use `Paths.getVideoStreamByContainer(itemID:container:"mp4")` with
  independent stream-copy decisions, re-encoding incompatible streams for a progressive MP4 transfer.
- Non-tvOS: iOS, iPadOS, macOS, and visionOS support downloads; tvOS does not expose the
  action or Downloads view.
- Stateful: `OfflineDownloadRecord` stores status, progress, and resume data so paused and
  in-flight records survive app relaunch.
- Per server/user: records and files are stored under an Application Support folder scoped
  by server ID and user ID, excluded from device backup.

The October 2026 revision adds a minimal `UIApplicationDelegateAdaptor` on iOS/iPadOS
for Apple's background URLSession wake/completion callbacks. SwiftUI still owns every
screen. Launch events are enabled; the shared download store attaches before reconnecting.
The coordinator preserves completed files with recovery manifests and delivers events in
order. The system completion handler is called after file normalization and record
persistence. Completion resolves records independently of the displayed account.

This bridge is a native-first exception to the former no-AppDelegate convention: SwiftUI
has no equivalent background URLSession acknowledgement API. Transfers can continue
while the device is locked or Gus is suspended. Force-quitting is not supported as a way
to keep downloads running. Physical-device background acceptance remains required.

`DownloadActivity` keeps real byte counters separately from optional total size. Unknown
response lengths use indeterminate progress and display received bytes; speed and ETA
are based on measured transfer samples. Processing percentages are not inferred from
zero bytes or requested conversion. Jellyfin's current `TranscodingInfo` belongs to a
device session without a per-download request identifier, so concurrent downloads cannot
safely use that percentage. The UI states when a remaining-time estimate is unavailable.

The Downloaded section browses account-scoped saved metadata and verified local files.
It does not request server libraries or remote artwork. Playback starts from local files,
with local resume checkpoints synchronized later. Ordinary account switching retains
downloads; explicit sign-out/removal clears the affected account.

## Rationale

The implementation stays native-first: background `URLSessionDownloadTask`, `FileManager`,
`Codable`, and `URLResourceValues.isExcludedFromBackup` cover the downloader without adding
a dependency. Using Jellyfin's progressive MP4 endpoint avoids HLS playlist parsing or
segment reassembly while still producing an AVPlayer-compatible offline file.

The transcode path trades client simplicity for server work. Transcoded files can be larger
than originals in some cases, may take time before transfer progress begins, and do not
embed subtitle sidecars. Those limitations are acceptable for this cut because the feature
goal is reliable offline video playback, not archival fidelity.

## Consequences

- Downloads survive normal app suspension on platforms that support background URLSession
  downloads.
- Pause uses `cancel(byProducingResumeData:)`. Jellyfin or the OS may invalidate resume
  data; when resume data is missing or stale, A Playa Named Gus intentionally falls back to a full
  re-download and surfaces that to the user.
- Incompatible originals are downloaded as server-transcoded MP4 files rather than hidden
  behind a "not available" state.
- No subtitle sidecar downloads.
- No cross-user sharing of downloaded files.
- tvOS users stream only.
- A future revision is warranted if users need background transfer policy controls,
  subtitle sidecar downloads, bitrate/quality selection, or richer stale-resume recovery.
