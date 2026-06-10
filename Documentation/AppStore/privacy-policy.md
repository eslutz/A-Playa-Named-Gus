# Draft Privacy Policy

Last updated: 2026-06-10

A Playa Named Gus is a Jellyfin client. A Playa Named Gus connects to Jellyfin servers
that you provide, stores the server connection details you choose to save, and uses your
Jellyfin account token to keep you signed in on this device.

## Data A Playa Named Gus Stores On Device

- Jellyfin server names, URLs, and IDs.
- Stored Jellyfin user records without passwords.
- Session tokens in the Apple Keychain.
- App preferences and local navigation state.
- Optional downloaded media files and metadata for the active Jellyfin server/user on
  iOS, iPadOS, macOS, and visionOS.

Downloaded media is stored in the app's Application Support container, scoped by server and
user, and excluded from device backup. tvOS does not support persistent local downloads in
A Playa Named Gus.

## Data Sent To Jellyfin Servers

A Playa Named Gus sends requests to the Jellyfin server you choose, including sign-in
requests, library browse/search requests, stream requests, playback progress reports, and
optional foreground download requests. That server is controlled by you or by the server
operator you choose. A Playa Named Gus does not operate the Jellyfin server.

## Data A Playa Named Gus Does Not Collect

The developer of A Playa Named Gus does not receive analytics, crash logs, tracking
identifiers, advertising identifiers, Jellyfin credentials, Jellyfin tokens, library
metadata, playback history, downloaded media, or server URLs from the app.

## Diagnostics

A Playa Named Gus uses Apple's MetricKit to understand app health (such as crash counts,
hang time, launch time, memory, and energy use). These summaries contain no personal
information, no media titles, and no server addresses, and they stay on your device. If
you have chosen to share analytics with app developers in your Apple device settings,
Apple may make crash reports and aggregate metrics available to the developer through
Apple's own tools; that sharing is controlled by Apple and your device settings, not by
this app.

## Apple Watch

If you use the Apple Watch companion, A Playa Named Gus may transfer your active server
connection and Jellyfin session token from your iPhone to your paired Apple Watch over
Apple's encrypted device-to-device WatchConnectivity channel, so the watch is signed in
without re-entering your credentials. This transfer stays between your own devices; it is
not sent to the developer or any third party. The watch can also sign in on its own.

## Content Restrictions and Age Range

The content-rating limit you choose is stored on the device as an app preference. On
supported systems you may optionally use Apple's Declared Age Range to set a starting
limit: with your consent the system shares only an age *range* with the app, which uses it
once to suggest a limit and then discards it. A Playa Named Gus does not store your
birthdate, your exact age, or the shared age range.

## Local Network

If you choose Find Local Servers, A Playa Named Gus uses the local network to discover
Jellyfin servers. Manual server entry remains available.

## tvOS Privacy Text

A Playa Named Gus for Apple TV connects only to Jellyfin servers you provide. A Playa
Named Gus stores server and user records on the device and stores sign-in tokens in the
Keychain. A Playa Named Gus does not support offline downloads on tvOS and does not
collect analytics or tracking data for the developer.

## Contact

Support URL and privacy contact email are required before App Store submission.
