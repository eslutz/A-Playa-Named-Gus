# App Store Metadata Draft

## Category

Primary: Entertainment

Secondary: Utilities or Lifestyle, to be decided after competitive review.

## Short Description

An Apple-first Jellyfin client for streaming your personal media library on iPhone, iPad,
Apple TV, Apple Vision Pro, and Mac.

## Longer Description Draft

A Playa Named Gus is a native Jellyfin client built for Apple platforms. Connect to your
Jellyfin server, browse your libraries, search, view rich metadata, and play movies and
shows through AVKit with system playback controls, Now Playing integration, AirPlay
routing, and a visionOS Cinema mode.

On iPhone, iPad, Mac, and Apple Vision Pro, A Playa Named Gus can save
AVPlayer-compatible originals from your own Jellyfin server for foreground offline
playback. Apple TV streams only.

A Playa Named Gus is not affiliated with Jellyfin. A Jellyfin server is required.

## Keywords Draft

Jellyfin, media server, movies, TV, streaming, home server, offline, AVKit, Vision Pro

## Age Rating Recommendation

Likely 12+ or 17+, depending on App Store Connect questionnaire interpretation, because
A Playa Named Gus can browse and play user-supplied media whose rating/content is outside
the app's control. Confirm during App Store Connect setup.

## Required URLs

- Marketing URL: `https://gus.ericslutz.dev/`
- Support URL: `https://gus.ericslutz.dev/support`
- Privacy Policy URL: `https://gus.ericslutz.dev/privacy`
- Accessibility URL: `https://gus.ericslutz.dev/accessibility`
- Age Suitability / reviewer context: `https://gus.ericslutz.dev/age-suitability`

All five pages must be live over HTTPS before public release and App Review submission.
See `Documentation/AppStore/review-support-pages.md`.

## Review Notes Draft

A Playa Named Gus requires a user-provided Jellyfin server. If Apple review needs test
access, provide a temporary demo Jellyfin server URL plus credentials with known sample
media. Reference the Age Suitability page (`https://gus.ericslutz.dev/age-suitability`)
for the age-rating scope explanation; content per `Documentation/AppStore/review-support-pages.md`.
