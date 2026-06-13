# App Review Compliance Audit

Status: **self-audit complete — no open red flags against the current codebase.**
Remaining items are account-blocked operational steps, listed at the end.

This document walks the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
section by section for A Playa Named Gus, then audits the shipped configuration, and
ends with ready-to-paste drafts for the App Store Connect **Notes for Review** field and
the **age rating questionnaire**. Update it whenever a relevant capability, data
practice, or feature changes.

What the app is, in one reviewer-sized sentence: *a native SwiftUI client for the user's
own self-hosted [Jellyfin](https://jellyfin.org) media server — the developer operates no
backend, hosts no content, and collects no data.*

---

## 1. Safety

- **1.1 Objectionable content** — A Playa Named Gus ships no content. Everything shown
  comes from a media server the user installs, owns, and authenticates to. The app is a
  player/browser for the user's own files, equivalent in posture to the Files app or VLC.
- **1.2 User-generated content** — Not a UGC platform: there is no public sharing, no
  user-to-user interaction, no discovery of other people's content, and no developer-run
  service to moderate. SharePlay uses Apple's system Group Activities session for users
  who already have access to the same media item; Gus shares item identifiers and display
  metadata only, never server credentials or stream URLs.
- **1.3 Kids Category** — Not a Kids Category app and not marketed to children. The app
  still ships family safety features: an app-level content-rating limit
  (Settings → Content Restrictions) covering US and international rating systems, gating
  of restricted items at list, detail, and playback level, and privacy-preserving
  age-aware defaults via Apple's Declared Age Range API on OS 26+ (no birthdates are
  collected or stored — see `Documentation/family-safety-brief.md`).
- **1.4 Physical harm** — N/A (media playback only).
- **1.5 Developer information** — The support URL (`https://gus.ericslutz.dev/support`)
  and contact information ship with the App Store Connect record
  (`Documentation/AppStore/review-support-pages.md`).
- **1.6 Data security** — Credentials go only to the user's own server. Tokens are stored
  with the Security framework (data-protection Keychain on every platform, including
  macOS). ATS is scoped, not disabled (see Configuration audit). There is no developer
  backend to breach.

## 2. Performance

- **2.1 App completeness** — All shipped features are functional; there are no
  placeholder screens or "coming soon" UI. Reviewers can exercise every flow against the
  demo Jellyfin library (see Notes for Review draft below).
- **2.2 Beta testing** — Beta builds stay on TestFlight; the App Store build is final.
- **2.3 Accurate metadata** — Screenshots are captured from the rights-cleared,
  public-domain/CC0 demo library (`Documentation/AppStore/demo-server.md`), so store
  imagery never shows copyrighted third-party media. The description identifies the app
  as a third-party client that **requires a user-provided Jellyfin server** and is not
  affiliated with the Jellyfin project.
- **2.4 Hardware compatibility** — Native on iOS, iPadOS, tvOS, visionOS, and macOS,
  with a watchOS companion. Background work is limited to declared modes (audio) and
  system background `URLSession` transfers; there are no battery-draining background
  loops (verified by MetricKit baselines —
  `Documentation/AppStore/performance-baselines.md`).
- **2.5 Software requirements**
  - **2.5.1 Public APIs only** — SwiftUI, AVKit/AVFoundation, MediaPlayer, Security,
    Foundation/URLSession, RealityKit, MetricKit, OSLog, WatchConnectivity, and (OS 26+)
    DeclaredAgeRange. Runtime third-party dependencies: `jellyfin-sdk-swift` (MPL-2.0)
    and, on iOS/iPadOS only, the BSD-licensed Readium toolkit for EPUB rendering
    (ADR 0009). No private API use.
  - **2.5.2 Self-contained** — No code download or remote execution. The EPUB reader
    renders local book files over a loopback server; it executes no remote code.
  - **2.5.4 Background audio** — The `audio` background mode is used exactly for
    user-initiated media playback (music, audiobooks, video audio, PiP).
  - **2.5.6 WebKit** — Readium renders EPUB content in `WKWebView` (content display, not
    a general-purpose browser). There is no web browsing surface.
  - **2.5.13 / health & sensitive frameworks** — None used.

## 3. Business

- **3.1 Payments** — The app is free, with **no IAP, no subscriptions, no ads, and no
  monetization of any kind**. It unlocks nothing: Jellyfin is free open-source software
  the user runs on their own hardware. No payment can flow to the developer or through
  the app, so guidelines 3.1.1/3.1.3 do not engage.
- **3.2 Other business model issues** — The app does not require any paid third-party
  service: a Jellyfin server is free to operate. No artificial gating exists.

## 4. Design

- **4.1 Copycats** — Original name, original Gus brand mark icon, original
  code. The mature Swiftfin client is a *pattern* reference only (documented policy in
  `AGENTS.md`); no code is copied, and the stacks differ fundamentally (pure
  AVKit/SwiftUI vs VLCKit/UIKit).
- **4.2 Minimum functionality** — A full-featured native client (browse, search,
  playback with track selection and chapters, downloads, music, books with an in-app
  reader, photos, Live TV, SharePlay, CarPlay, watchOS remote/companion).
- **4.4 Extensions** — The tvOS Top Shelf extension serves static, safe entry points
  (`gus://` deep links) and fetches nothing.
- **4.8 Login services** — Sign in with Apple is **not required**: authentication is to
  the *user's own self-hosted server* with that server's local accounts. There is no
  third-party or social login service in the flow, and the developer receives no
  identity data, which is the situation 4.8 exempts.
- **Trademark note (4.1/5.2 overlap)** — "Jellyfin" appears only nominatively ("client
  for Jellyfin servers"). The app name, icon, and brand are independent. The store
  listing carries the standard disclaimer: *not affiliated with or endorsed by the
  Jellyfin project*. The app name is an original phrase; no third-party characters,
  artwork, or media appear in the app or its metadata.

## 5. Legal

- **5.1.1 Privacy — data collection and storage** — The developer collects **nothing**.
  `Resources/PrivacyInfo.xcprivacy` declares `NSPrivacyTracking = false`, an empty
  `NSPrivacyCollectedDataTypes`, and exactly the two required-reason APIs in use
  (Disk Space `85F4.1`, UserDefaults `CA92.1`) — call-site audit in
  `Documentation/AppStore/privacy-labels.md`. Server credentials, tokens, playback
  state, and downloads stay on-device or travel only to the user's chosen server.
  Diagnostics are Apple-native (MetricKit + on-device aggregate summaries, no
  identifiers, no third-party SDK — `Documentation/AppStore/diagnostics-reliability.md`).
- **5.1.2 Data use and sharing** — Nothing is shared with anyone, including the
  developer. No tracking, no ads, no fingerprinting; the required-reason declarations
  cover the only restricted APIs.
- **5.1.4 Kids** — The app collects no data from anyone, including children. The
  Declared Age Range integration receives only a *range* (never a birthdate), uses it
  once to suggest a content-restriction default, and stores only the resulting tier
  choice.
- **5.2 Intellectual property** — The developer distributes no media. Playback is
  limited to libraries on a server the user controls; the app cannot browse, obtain, or
  share content from any other source. Demo/screenshot media is public-domain/CC0.
  "Jellyfin" trademark use is nominative (see 4.x note).
- **5.3 Gaming / 5.4 VPN / 5.5 Mobile device management** — N/A.

---

## Configuration audit

### ATS / self-hosted HTTP

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

### Encryption / export compliance

`ITSAppUsesNonExemptEncryption = false`. Only Apple TLS (URLSession) and Keychain
storage are used; no custom cryptography is implemented.

### Local network

`NSLocalNetworkUsageDescription` is present. Local network access is user-initiated
(the Find Local Servers button triggers a UDP broadcast on port 7359 via the
`jellyfin-sdk-swift` discovery API). Manual URL entry remains primary. `NSBonjourServices`
is not declared because discovery uses UDP broadcast, not Bonjour/mDNS.

### Background audio

`UIBackgroundModes = [audio]` enables playback continuation, Now Playing/transport
integration, and PiP. Background downloads use `URLSessionConfiguration.background`,
which needs no background mode.

### Locally downloaded media

Offline downloads (iOS/iPadOS/macOS/visionOS; audio-only on watchOS; excluded on tvOS)
come exclusively from the authenticated user's server, respect the server's
`canDownload` permission, land in per-server/user Application Support folders, and are
excluded from iCloud backup. Nothing is shared outward. ADR 0005 records the design.

### Capabilities & entitlements

| Capability | Status |
|---|---|
| macOS App Sandbox + outbound network | Shipped (`Config/Gus.entitlements`) |
| tvOS User Management (runs as current user) | Shipped (`Config/Gus-tvOS.entitlements`) |
| SharePlay / Group Activities | Shipped (`com.apple.developer.group-session`) |
| Universal Links / Associated Domains | Shipped for `applinks:gus.ericslutz.dev` |
| Shared with You | Shipped via Universal Links, `SWHighlightCenter`, and `SWAttributionView` |
| tvOS App Group / Top Shelf snapshot | Shipped (`group.dev.ericslutz.gus`) |
| Background audio (`UIBackgroundModes`) | Shipped (Info.plist) |
| CarPlay audio | Code complete; entitlement awaits Apple grant — not wired into signing (`Config/Gus-CarPlay.entitlements`) |
| Declared Age Range (OS 26+) | Code complete and entitlement-wired for iOS/iPadOS/macOS; device verification remains (see `Documentation/AppStore/signing-capabilities.md`) |
| Family Controls / ManagedSettings | **Not used** — documented as entitlement-gated follow-up in `Documentation/family-safety-brief.md` |

---

## Draft: Notes for Review (App Store Connect)

> A Playa Named Gus is a native client for Jellyfin, a free open-source media server
> that users install on their own hardware. The app ships no content and operates no
> backend; it connects only to a server address the user supplies.
>
> **To review:** a demo Jellyfin server with a rights-cleared (public-domain/CC0)
> library is available at `https://demo.gus.ericslutz.dev` — sign in with user `gus`,
> password `playa-demo`. Connect screen → enter the address → Sign In. This account
> exercises browsing, search, detail, video/music/book playback, downloads, and photos.
> (Hosted instance pending; until live, reviewers can run `Scripts/demo-server.sh` from
> the repository against any Docker host.)
>
> **Local network permission** appears only if you tap "Find Local Servers" on the
> Connect screen (UDP broadcast discovery of Jellyfin servers on the LAN). Manual
> address entry never triggers it.
>
> **Content restrictions:** Settings → Content Restrictions limits browsable media by
> rating; the app additionally supports Apple's Declared Age Range on OS 26+ for
> privacy-preserving defaults. The app is not a Kids Category app.
>
> No purchases, subscriptions, ads, analytics, or data collection of any kind.

## Draft: age rating questionnaire

App-supplied content is the user's own library, so the questionnaire is answered for
*the app itself*:

| Question | Answer |
|---|---|
| Cartoon/fantasy/realistic violence | None |
| Profanity or crude humor | None |
| Mature/suggestive themes | None |
| Horror/fear themes | None |
| Medical/treatment information | None |
| Alcohol, tobacco, drug use | None |
| Simulated gambling | None |
| Sexual content or nudity | None |
| Unrestricted web access | **No** (no browser; EPUB rendering is local-only) |
| Gambling/contests | No |
| User-generated content | No (private client for the user's own server) |

Expected rating: **4+**. The listing description notes that the app displays the user's
own server library and includes parental content-restriction controls.

---

## Open items (account-blocked — not review blockers)

- Complete App Privacy answers in App Store Connect (source: `privacy-labels.md`).
- Add the privacy policy URL (all platforms) and the tvOS privacy policy text field.
- Publish and verify the public support/privacy/accessibility/age pages at
  `gus.ericslutz.dev`, then replace the placeholder demo-server host in the review notes
  with the live one.
- Configure Xcode Cloud signing/provisioning and validate Release archives.
- Upload screenshots and submit to TestFlight before final submission.
- Request the CarPlay audio entitlement.

### Operational blockers requiring external action

The following items cannot be resolved by code changes. Each needs a specific out-of-repo
action before first submission.

**BUILD-2 — Provision demo server at `demo.gus.ericslutz.dev`**
Action required: deploy a Jellyfin Docker instance (using `Scripts/demo-server.sh` as the
template) at a stable public host and point the subdomain at it. The draft "Notes for
Review" above references this URL for App Review access. Until it is live, reviewers must
run the demo server locally from the repository. Update the Notes for Review draft in this
file once the hosted instance is confirmed.

**BUILD-3 — Publish website pages at `gus.ericslutz.dev`**
Action required: the support, privacy policy, accessibility, and age-suitability pages
referenced throughout this audit (`review-support-pages.md`) live in the sibling
`../Gus.website` repo and must be deployed before submission. App Store Connect requires
a reachable support URL and a reachable privacy policy URL; App Review will visit both.
Confirm each page loads over HTTPS and matches current app behavior before submitting.
Changes to the app that affect privacy disclosures, supported features, or accessibility
claims must be reflected in the website as part of the same unit of work (per the wiki
and website sync policy in `CLAUDE.md`).

**BUILD-4 — Create Xcode Cloud workflow in App Store Connect**
Action required: sign in to App Store Connect → Xcode Cloud, connect the repository, and
configure a workflow for the `dev.ericslutz.gus` bundle ID. The workflow must build the
main app target plus the `GusTopShelf` tvOS extension and the `GusWatch` watchOS target,
manage provisioning profiles for all three, and produce signed archives for iOS/iPadOS,
tvOS, visionOS, and macOS. Until this exists, no TestFlight build or App Store submission
is possible. See `Documentation/AppStore/ci-strategy.md` and the CI Signing Ownership
section of `signing-capabilities.md` for the intended Xcode Cloud scope.
