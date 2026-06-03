# ADR 0005: Offline downloads background and transcode scope

## Status

Accepted

## Context

Gus playback is intentionally AVKit-only. Network playback asks Jellyfin for posted
playback info with a device profile biased toward HLS transcoding so `AVPlayer` receives a
playable stream. The first offline download cut downloaded only original files with
`JellyfinClient.download(for:)` and hid the action for sources outside Gus's direct-play
profile. That kept scope small, but it left common Jellyfin libraries with MKV, HDR, or
non-AAC audio unable to download at all.

Long-running foreground downloads were also fragile. Large files can outlive an active app
session, and users expect a native download to survive suspension and expose pause, resume,
and delete controls.

tvOS is also different from the other supported platforms. Its app storage is
system-purgeable and is not a reliable place for persistent local media without a separate
On-Demand Resources design.

## Decision

Gus downloads are:

- Background-capable: transfers use a stable native background `URLSession` identifier
  (`dev.ericslutz.gus.downloads`) owned by `DownloadSessionCoordinator`.
- Originals when possible: AVPlayer-native sources still use `Paths.getDownload(itemID:)`.
- Transcoded when needed: incompatible sources call `Paths.getPostedPlaybackInfo` to pick a
  media source, then use `Paths.getVideoStreamByContainer(itemID:container:"mp4")` with
  H.264, AAC stereo, and 8-bit output parameters for a progressive MP4 transfer.
- Non-tvOS: iOS, iPadOS, macOS, and visionOS support downloads; tvOS does not expose the
  action or Downloads view.
- Stateful: `OfflineDownloadRecord` stores status, progress, and resume data so paused and
  in-flight records survive app relaunch.
- Per server/user: records and files are stored under an Application Support folder scoped
  by server ID and user ID, excluded from device backup.

To preserve the project's pure SwiftUI lifecycle (no AppDelegate), the app does **not**
implement `application(_:handleEventsForBackgroundURLSession:completionHandler:)` — that
callback has no SwiftUI-lifecycle equivalent and would require a `UIApplicationDelegate`.
It is only an optimization for servicing background relaunches, not a correctness
requirement: transfers complete in the system URLSession daemon while the app is suspended
or terminated, and `DownloadSessionCoordinator.reconnectActiveTasks()` (called when
`OfflineDownloadStore` is constructed at launch) recreates the background session with the
stable identifier so the system replays completion events. `sessionSendsLaunchEvents` is
set to `false` accordingly, so the system does not relaunch the app for events it cannot
acknowledge. The trade-off — completed-while-terminated downloads reconcile on the next
app launch rather than during a background relaunch — is negligible for a media client and
keeps the architecture genuinely AppDelegate-free.

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
  data; when resume data is missing or stale, Gus intentionally falls back to a full
  re-download and surfaces that to the user.
- Incompatible originals are downloaded as server-transcoded MP4 files rather than hidden
  behind a "not available" state.
- No subtitle sidecar downloads.
- No cross-user sharing of downloaded files.
- tvOS users stream only.
- A future revision is warranted if users need background transfer policy controls,
  subtitle sidecar downloads, bitrate/quality selection, or richer stale-resume recovery.
