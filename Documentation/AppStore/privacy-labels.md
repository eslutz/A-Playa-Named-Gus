# App Privacy Labels

A Playa Named Gus does not collect data for the developer and does not track users. The app
communicates with user-provided Jellyfin servers; the server operator's own privacy
practices are outside the scope of this document.

Apple's App Store Connect privacy flow requires these answers to be accurate and updated if
data practices change. The declarations below mirror `Resources/PrivacyInfo.xcprivacy`
exactly — update both together.

## Tracking

- **Tracking:** No.
- **Third-party advertising or data broker sharing:** No.
- **Analytics SDKs:** None.

## Data Collected by Developer

**Data linked to user:** None.
**Data not linked to user:** None.

Jellyfin usernames, server URLs, tokens, media metadata, playback progress, and downloaded
media remain on-device or are sent to the user-selected Jellyfin server. Nothing is routed
through an A Playa Named Gus developer backend.

## Privacy Manifest (PrivacyInfo.xcprivacy)

`Resources/PrivacyInfo.xcprivacy` is bundled with the app. Declarations:

| Field | Value |
|---|---|
| NSPrivacyTracking | false |
| NSPrivacyTrackingDomains | (empty) |
| NSPrivacyCollectedDataTypes | (empty) |

### Required-reason APIs declared

| Category | Reason | Call site |
|---|---|---|
| NSPrivacyAccessedAPICategoryDiskSpace | 85F4.1 | `OfflineDownloadStore.ensureDiskBudget` checks available volume capacity (`volumeAvailableCapacityForImportantUsage`, or `volumeAvailableCapacity` on watchOS) before starting a download |
| NSPrivacyAccessedAPICategoryUserDefaults | CA92.1 | `AppModel` (last-signed-in user ID), `DeviceIdentity` (stable device UUID), and `@AppStorage`/`@SceneStorage` preferences (sidebar selection, appearance, content limit, navigation order) — app-own keys only |

`Resources/PrivacyInfo.xcprivacy` is bundled into the main app target **and** the
`GusWatch` companion target, both of which exercise these required-reason APIs.

### Required-reason APIs not declared (not used)

File timestamp APIs, System boot time APIs, Active keyboard APIs — none are called in A
Playa Named Gus source code.

## Device Permissions / Usage Descriptions

| Key | Reason |
|---|---|
| NSLocalNetworkUsageDescription | User-initiated Jellyfin server discovery over local-network UDP broadcast. Manual URL entry remains primary. |
| UIBackgroundModes: audio | Media playback continuation, Now Playing, and system transport controls via AVKit. |

## Diagnostics

The Diagnostics & Reliability implementation does not change the answers above:

- MetricKit payloads are delivered on-device; `MetricKitCollector` normalizes them into
  aggregate summaries stored only in the app's Application Support directory. Nothing is
  transmitted to the developer.
- `DiagnosticsHub` lifecycle markers carry only numeric/boolean values by construction
  and stay in the unified log / in-memory buffer on the device.
- Crash and metrics data in Xcode Organizer / App Store Connect comes from Apple's own
  opt-in "Share With App Developers" mechanism, which Apple discloses to the user; the
  app itself still collects nothing.
- No new required-reason APIs were introduced; `PrivacyInfo.xcprivacy` content is
  unchanged (it is now also bundled into the watch target, which uses the same APIs).

## Remaining Submission Steps
- Add the privacy policy URL for iOS, iPadOS, macOS, and visionOS in App Store Connect.
- Add tvOS privacy policy text in the Apple TV Privacy Policy field.
- Complete App Privacy answers in App Store Connect, using this document as the source.
