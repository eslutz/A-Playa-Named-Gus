# App Privacy Labels

Gus does not collect data for the developer and does not track users. The app communicates
with user-provided Jellyfin servers; the server operator's own privacy practices are outside
the scope of this document.

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
through a Gus developer backend.

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
| NSPrivacyAccessedAPICategoryDiskSpace | 85F4.1 | `OfflineDownloadStore.ensureDiskBudget` checks `volumeAvailableCapacityForImportantUsage` before starting a download |
| NSPrivacyAccessedAPICategoryUserDefaults | CA92.1 | `AppModel` (last-signed-in user ID), `DeviceIdentity` (stable device UUID), `@SceneStorage` (sidebar selection) — app-own keys only |

### Required-reason APIs not declared (not used)

File timestamp APIs, System boot time APIs, Active keyboard APIs — none are called in Gus
source code.

## Device Permissions / Usage Descriptions

| Key | Reason |
|---|---|
| NSLocalNetworkUsageDescription | User-initiated Jellyfin server discovery (Bonjour). Manual URL entry remains primary. |
| NSFaceIDUsageDescription | Protects Jellyfin sign-in surfaces on platforms that prompt for a usage description. |
| UIBackgroundModes: audio | Media playback continuation, Now Playing, and system transport controls via AVKit. |

## Remaining Submission Steps

- Confirm no Apple diagnostic/crash-reporting opt-in changes the developer-side privacy
  statement.
- Add the privacy policy URL for iOS, iPadOS, macOS, and visionOS in App Store Connect.
- Add tvOS privacy policy text in the Apple TV Privacy Policy field.
- Complete App Privacy answers in App Store Connect, using this document as the source.
