# Hosted Review and Support Pages

Status: required before public release and App Review submission.

Base host: `https://gus.ericslutz.dev`

These pages provide the public URLs needed for App Store Connect, reviewer context, and
user support. They should be published over HTTPS before the App Store Connect record is
submitted for review.

## Required Routes

| Route | App Store role | Required content |
|---|---|---|
| `/` | Marketing URL | App overview, feature highlights, screenshots, download/TestFlight information, and roadmap/changelog links. |
| `/support` | Support URL | Contact information, FAQ, troubleshooting guidance, bug reporting instructions, and links to privacy policy plus other relevant resources. |
| `/privacy` | Privacy Policy URL | A hosted privacy policy suitable for App Store submission, based on `Documentation/AppStore/privacy-policy.md`. |
| `/accessibility` | Accessibility disclosure / public FAQ | Supported Apple accessibility features, platform scope, captions/audio-description dependency notes, and support reporting path. |
| `/age-suitability` | App Review context / public FAQ | A plain-language age suitability explanation for parents and reviewers. |

## Age Suitability Page

`/age-suitability` must clearly state:

- A Playa Named Gus is a Jellyfin client and does not host, curate, or distribute media.
- Users connect to their own Jellyfin server and access their own content.
- Gus does not provide unrestricted web access, chat, messaging, advertising, gambling,
  contests, loot boxes, or other monetized chance mechanics.
- Age appropriateness depends on the content available on the user's Jellyfin server.
- Parents and guardians should manage access through Jellyfin user permissions, Jellyfin
  library restrictions, and Apple Screen Time.

This page should avoid implying that Gus can determine the maturity of every user's media
library. It should describe Gus as the client surface and Jellyfin/server settings as the
source of content access control for the current 1.0 scope.

## Support Page

`/support` must include:

- A real support contact method, with the inbox confirmed before submission.
- A FAQ covering server requirements, sign-in, Quick Connect, local network discovery,
  playback compatibility, downloads, Apple TV limitations, and visionOS Cinema basics.
- Troubleshooting guidance for connection failures, HTTP/HTTPS self-hosted servers, local
  network permission prompts, playback failures, missing libraries, and downloads.
- Bug reporting instructions that route reproducible issues to the chosen support channel
  or GitHub issue tracker.
- Links to `/privacy`, `/accessibility`, `/age-suitability`, the project roadmap,
  changelog/release notes, and any TestFlight feedback instructions.

## Privacy Policy Page

`/privacy` must be adapted from `Documentation/AppStore/privacy-policy.md` and kept aligned
with `Documentation/AppStore/privacy-labels.md` and `Resources/PrivacyInfo.xcprivacy`,
including any diagnostic disclosure changes from the Diagnostics & Reliability initiative.

## Accessibility Page

`/accessibility` must be adapted from `Documentation/AppStore/accessibility.md`. Required
statements are specified in that document’s "Public Accessibility Page" section.

## Marketing Page

`/` must include:

- A concise app overview that explains Gus is an Apple-first Jellyfin client.
- Feature highlights for connecting to a Jellyfin server, browsing libraries, playback,
  Now Playing/AirPlay, downloads where supported, Apple TV streaming, and visionOS Cinema.
- App Store-ready screenshots or placeholders until final screenshots are approved.
- Download or TestFlight information appropriate to the current release phase.
- Links to support, privacy policy, accessibility, age suitability, roadmap, and
  changelog/release notes.

## Acceptance Checklist

- [ ] `https://gus.ericslutz.dev/` is live over HTTPS.
- [ ] `https://gus.ericslutz.dev/support` is live over HTTPS.
- [ ] `https://gus.ericslutz.dev/privacy` is live over HTTPS.
- [ ] `https://gus.ericslutz.dev/accessibility` is live over HTTPS.
- [ ] `https://gus.ericslutz.dev/age-suitability` is live over HTTPS.
- [ ] App Store Connect Support URL points to `/support`.
- [ ] App Store Connect Privacy Policy URL points to `/privacy`.
- [ ] App Store Connect Marketing URL points to `/`.
- [ ] Website and support pages link to `/accessibility`.
- [ ] App Review notes reference `/age-suitability` when explaining age-rating scope.
- [ ] Page text matches the current App Privacy answers, privacy manifest, accessibility
      disclosures, age-rating questionnaire answers, demo-media plan, and review compliance
      audit.
