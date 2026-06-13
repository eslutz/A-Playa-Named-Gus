# App Store Metadata Draft

## Category

Primary: Entertainment

Secondary: Utilities or Lifestyle, to be decided after competitive review.

## Short Description

An Apple-first Jellyfin client for streaming your personal media — movies, shows, music,
books, and photos — on iPhone, iPad, Apple TV, Apple Vision Pro, Mac, and Apple Watch.

## Longer Description Draft

A Playa Named Gus is a native Jellyfin client built for Apple platforms. Connect to your
Jellyfin server, browse your libraries, search, and view rich metadata, then play movies
and shows through AVKit with audio/subtitle track selection, chapters, Picture in Picture,
Now Playing integration, AirPlay routing, and a visionOS Cinema mode for spatial and 3D
video.

Beyond video, Gus plays your music and audiobooks with a full queue, shuffle/repeat, and
playback speed; reads EPUB books in an in-app reader on iPhone and iPad (or hands off to
Apple Books elsewhere); browses photo libraries with slideshows; and surfaces Live TV
channels, recordings, and scheduled recordings when your server has a tuner. SharePlay
uses Apple's native Group Activities stack for watch parties on Apple devices.

On iPhone, iPad, Mac, and Apple Vision Pro, Gus saves content from your own Jellyfin
server for offline playback — AVPlayer-native originals directly, and other formats
through your server's transcoder. Apple TV streams only.

The Apple Watch companion is a remote for your other Jellyfin players (play/pause, seek,
volume), with quick resume, lightweight browsing, and on-watch audio.

Gus respects the family: a content-rating limit (Settings → Content Restrictions) hides
and gates media above the chosen rating across US and international rating systems, and
follows the system appearance with an in-app Light/Dark override. You choose which
sections appear in the main navigation and in what order.

A Playa Named Gus is not affiliated with Jellyfin. A Jellyfin server is required.

## Keywords Draft

Jellyfin, media server, movies, TV, music, audiobooks, books, photos, streaming, home
server, offline, Live TV, Vision Pro, watch remote

## Age Rating

Answer the App Store Connect questionnaire **for the app itself**, which ships no content
of its own — it displays the user's own server library, the same posture as a file or
media-player utility. On that basis every content question is "None / No" and the expected
rating is **4+**. The full questionnaire answers and rationale (including the
parental-controls disclosure and the absence of in-app web browsing) are in
`Documentation/AppStore/review-compliance-audit.md`. Confirm the final selection during
App Store Connect setup; the listing description should note that the app shows the user's
own library and includes content-restriction controls.

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
media (see the Notes for Review draft in
`Documentation/AppStore/review-compliance-audit.md`). Reference the Age Suitability page
(`https://gus.ericslutz.dev/age-suitability`) for the age-rating scope explanation;
content per `Documentation/AppStore/review-support-pages.md`.
