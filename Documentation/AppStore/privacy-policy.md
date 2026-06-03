# Draft Privacy Policy

Last updated: 2026-06-03

Gus is a Jellyfin client. Gus connects to Jellyfin servers that you provide, stores the
server connection details you choose to save, and uses your Jellyfin account token to keep
you signed in on this device.

## Data Gus Stores On Device

- Jellyfin server names, URLs, and IDs.
- Stored Jellyfin user records without passwords.
- Session tokens in the Apple Keychain.
- App preferences and local navigation state.
- Optional downloaded media files and metadata for the active Jellyfin server/user on
  iOS, iPadOS, macOS, and visionOS.

Downloaded media is stored in the app's Application Support container, scoped by server and
user, and excluded from device backup. tvOS does not support persistent local downloads in
Gus.

## Data Sent To Jellyfin Servers

Gus sends requests to the Jellyfin server you choose, including sign-in requests, library
browse/search requests, stream requests, playback progress reports, and optional foreground
download requests. That server is controlled by you or by the server operator you choose.
Gus does not operate the Jellyfin server.

## Data Gus Does Not Collect

The developer of Gus does not receive analytics, crash logs, tracking identifiers,
advertising identifiers, Jellyfin credentials, Jellyfin tokens, library metadata, playback
history, downloaded media, or server URLs from the app.

## Local Network

If you choose Find Local Servers, Gus uses the local network to discover Jellyfin servers.
Manual server entry remains available.

## tvOS Privacy Text

Gus for Apple TV connects only to Jellyfin servers you provide. Gus stores server and user
records on the device and stores sign-in tokens in the Keychain. Gus does not support
offline downloads on tvOS and does not collect analytics or tracking data for the
developer.

## Contact

Support URL and privacy contact email are required before App Store submission.
