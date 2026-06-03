# App Privacy Labels Draft

Default position: Gus itself does not collect data for the developer and does not track
users. The app communicates with user-provided Jellyfin servers, and the server operator's
own privacy practices are outside Gus.

Apple's App Store Connect privacy flow requires answers to be accurate and updated if data
practices change.

## Tracking

- Tracking: No.
- Third-party advertising or data broker sharing: No.
- Analytics SDKs: None.

## Data Linked To User

Proposed answer for Gus developer-side collection: none.

Rationale: Jellyfin usernames, server URLs, tokens, media metadata, playback progress, and
downloaded media remain on device or are sent to the user-selected Jellyfin server, not to
the Gus developer.

## Data Not Linked To User

Proposed answer for Gus developer-side collection: none.

## Device Permissions / Explanations

- Local Network: user-initiated Jellyfin discovery.
- Background audio: media playback continuation and system playback controls.
- Face ID / Optic ID string: protects Jellyfin sign-in security surfaces where the platform
  requests the usage description.

## Submission TODO

- Confirm no Apple diagnostic/crash reporting choice changes the developer-side privacy
  statement.
- Add the privacy policy URL for iOS, iPadOS, macOS, and visionOS.
- Add tvOS privacy policy text in the Apple TV Privacy Policy field.
- Add `PrivacyInfo.xcprivacy` if required-reason API declarations are needed for the final
  binary.
