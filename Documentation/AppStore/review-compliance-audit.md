# App Review Compliance Audit

Status: self-audit complete; no open red flags against the current codebase.

This document is a self-audit against the
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
Update it whenever a relevant capability, data practice, or feature changes.

---

## Privacy

A Playa Named Gus has no developer-operated analytics, tracking, advertising, or backend
service.
`Resources/PrivacyInfo.xcprivacy` declares the two required-reason APIs actually used
(Disk Space / `85F4.1` and UserDefaults / `CA92.1`) with `NSPrivacyTracking = false`
and empty `NSPrivacyCollectedDataTypes`. See `Documentation/AppStore/privacy-labels.md`
for the full declaration table and the call-site audit that backs it.

Jellyfin server credentials and tokens are stored in the Keychain via Apple's
Security framework (`SecItem*`). No credentials are transmitted to a developer backend.

---

## ATS / Self-Hosted HTTP

`NSAllowsArbitraryLoads = true` is set in `Info.plist`. Justification for App Review:
A Playa Named Gus is a client for user-provided Jellyfin media servers. Many self-hosted
Jellyfin deployments run plain HTTP on a private LAN and cannot be required to obtain a
public TLS certificate. A Playa Named Gus cannot know at build time which servers users
will connect to. This is the standard justification for third-party-server client apps per the
[ATS exception guidelines](https://developer.apple.com/documentation/security/preventing-insecure-network-connections).

---

## Encryption / Export Compliance

`ITSAppUsesNonExemptEncryption = false` in `Info.plist`. A Playa Named Gus uses Apple
networking and Security framework APIs for ordinary transport (TLS via URLSession) and
Keychain token storage. No custom cryptographic algorithms are implemented.

---

## Local Network

`NSLocalNetworkUsageDescription` is present in `Info.plist`. Local network access is
user-initiated (the Find Local Servers button triggers a UDP broadcast on port 7359
via the `jellyfin-sdk-swift` discovery API). Manual server URL entry remains the
primary connection method; discovery is an optional convenience.

`NSBonjourServices` is not declared because discovery uses UDP broadcast sockets
(swift-nio), not Bonjour/mDNS.

---

## Background Audio

`UIBackgroundModes` includes `audio` in `Info.plist`. This enables:
- AVKit media playback continuation when the app is backgrounded.
- `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` Now Playing metadata and transport
  controls on lock screen and Control Center.
- Picture in Picture on iOS/iPadOS and macOS (using AVKit surfaces).

Background downloads use `URLSessionConfiguration.background` which does not require
a `UIBackgroundModes` entry. The `audio` mode is the only one declared.

---

## Locally Downloaded Media

Offline downloads are available on iOS, iPadOS, macOS, and visionOS. tvOS is excluded.

Downloaded media originates from the authenticated user's own Jellyfin server via
`Paths.getDownload(itemID:)` (original file) or `Paths.getVideoStreamByContainer`
(progressive MP4 transcode for AVPlayer-incompatible sources). Files are stored in
the app's Application Support container, scoped by server ID and user ID, and marked
excluded from iCloud backup via `URLResourceValues.isExcludedFromBackup`.

No downloaded content is shared with other users, other apps, or the developer.
Download eligibility respects the Jellyfin server's own `canDownload` permission flag.
ADR 0005 records the full design rationale.

---

## Media Content

A Playa Named Gus does not provide, host, or curate media. Users supply and authenticate to
their own Jellyfin servers. Content availability depends on that server and the user's
library. A Playa Named Gus does not generate, modify, or re-distribute media files.

---

## Public APIs Only

The implementation uses public Apple frameworks exclusively: SwiftUI, AVKit,
AVFoundation, MediaPlayer, Security, Foundation, FileManager, URLSession/URLCache,
RealityKit, and String Catalogs. No private or undocumented APIs are intentionally
used. The only runtime third-party dependency is `jellyfin-sdk-swift`.

---

## Open Items (Account-Blocked — Not Review Blockers)

- Complete App Privacy answers in App Store Connect (source: `privacy-labels.md`).
- Add privacy policy URL for iOS, iPadOS, macOS, and visionOS.
- Add tvOS privacy policy text in the Apple TV Privacy Policy field.
- Set real Team ID, switch to automatic signing, and validate Release archives.
- Upload screenshots and submit to TestFlight before final submission.
