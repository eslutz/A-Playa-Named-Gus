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

Diagnostics are Apple-native only: MetricKit summaries and app lifecycle markers are
normalized into aggregate, identifier-free records that stay on the device (see
`Documentation/AppStore/diagnostics-reliability.md`). No third-party analytics SDK is
present.

---

## ATS / Self-Hosted HTTP

ATS is scoped, not disabled: `Info.plist` sets `NSAllowsArbitraryLoads = false` with
`NSAllowsLocalNetworking = true`. Self-hosted Jellyfin servers on a private LAN (the
common plain-HTTP case) work without a wildcard exemption, loopback is exempt by
default, and **remote** servers must speak TLS. Connect tries `https://` first for
schemeless addresses and falls back to `http://`, which ATS then only permits for
local-network hosts. No App Review ATS justification is required for this configuration.

Access tokens ride in stream/WebSocket URL query strings (`api_key`) because
AVPlayer/HLS fetches cannot carry auth headers — the standard Jellyfin-client pattern.
Those URLs are treated as sensitive: they are never logged (OSLog statements log item
ids only).

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
RealityKit, MetricKit, OSLog/os.signpost, and String Catalogs. No private or
undocumented APIs are intentionally used. Runtime third-party dependencies are
`jellyfin-sdk-swift` and, on iOS/iPadOS/visionOS only, the BSD-licensed Readium toolkit
for in-app EPUB reading (local rendering over loopback; no analytics — ADR 0009).

---

## Accessibility

A Playa Named Gus uses native Apple UI and media frameworks so accessibility support can
flow through SwiftUI, AVKit, platform focus systems, Dynamic Type, semantic colors, and
system media controls. Before App Review submission, verify the public accessibility page,
App Store accessibility disclosures, and release checklist against
`Documentation/AppStore/accessibility.md`.

---

## Open Items (Account-Blocked — Not Review Blockers)

- Complete App Privacy answers in App Store Connect (source: `privacy-labels.md`).
- Add privacy policy URL for iOS, iPadOS, macOS, and visionOS.
- Add tvOS privacy policy text in the Apple TV Privacy Policy field.
- Publish and verify the public accessibility page and App Store accessibility disclosures.
- Configure Xcode Cloud signing/provisioning and validate Release archives there.
- Upload screenshots and submit to TestFlight before final submission.
