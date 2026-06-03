# App Review Compliance Audit

Status: draft self-audit for M7 readiness.

## Privacy

Gus has no developer-operated analytics, tracking, advertising, or backend service. It
stores Jellyfin server/user records locally and stores session tokens in Keychain. A
privacy policy URL is required, and tvOS also needs privacy text in App Store Connect.

## ATS / Self-Hosted HTTP

`NSAllowsArbitraryLoads` is currently enabled because many self-hosted Jellyfin servers are
plain HTTP on a local network. The review note should explain that Gus is a user-provided
server client and cannot require all private Jellyfin deployments to have public HTTPS.

## Encryption / Export Compliance

`ITSAppUsesNonExemptEncryption` is false. Gus uses Apple networking/security APIs for
ordinary app transport and Keychain storage, and does not implement custom cryptography.

## Local Network

`NSLocalNetworkUsageDescription` is present. Local network access is user-initiated through
Find Local Servers; manual URL entry remains primary.

## Background Audio

`UIBackgroundModes` includes `audio`. This supports AVKit media playback, Now Playing, and
system transport controls. M4 still needs manual PiP/background verification notes.

## Locally Downloaded Media

Offline downloads are supported on iOS, iPadOS, macOS, and visionOS only. Downloaded media
comes from the user's own Jellyfin server through `Paths.getDownload(itemID:)`, is stored
under the app's Application Support container, is scoped by server ID and user ID, and is
marked excluded from backup. tvOS does not expose local downloads.

Gus downloads original files only when the source appears directly AVPlayer-playable.
Transcode-on-download, background download resumption, subtitle sidecars, and cross-user
sharing are out of scope for this cut.

## Media Content

Gus does not provide media. Users supply and authenticate to their own Jellyfin servers.
Metadata and playback availability depend on that server and the user's library.

## Public APIs

The implementation uses public Apple APIs: SwiftUI, AVKit, AVFoundation, MediaPlayer,
Security, Foundation, FileManager, URLSession/URLCache, RealityKit, and String Catalogs.
No private APIs are intentionally used.

## Open M7 Items

- Add or validate `PrivacyInfo.xcprivacy`.
- Complete App Privacy answers in App Store Connect.
- Complete signing/capabilities with a real team.
- Capture screenshots and run TestFlight on all shipped platforms.
