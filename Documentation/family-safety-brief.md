# Family Safety & Age Assurance — Product Brief

Status: brief complete; the implementable scope is **shipped** (see "Shipped scope").
This is the acceptance artifact for the roadmap's *Family safety controls and age
assurance* item.

Gus's stance: **parent-friendly content controls built on Apple-provided safety APIs**,
never a custom age-verification or child-profile system. Gus stores no birthdates, no
exact ages, and no per-child identity data.

## Shipped scope

1. **Content-rating limit (all platforms).** Settings → Content Restrictions offers
   Off / All Ages / Parental Guidance / Teen / Mature. `ContentRatingGate` maps official
   rating strings onto comparable tiers and covers:
   - US movie (MPA) and US TV systems,
   - UK (BBFC), Germany (FSK), Australia (ACB) / New Zealand (OFLC), Canada,
   - country-prefixed forms Jellyfin emits (`DE-16`, `GB-12A`, `US-PG-13`),
   - bare minimum-age ratings (`6`, `16`, `16+`) by age bracket.
   Explicit "Unrated/Not Rated/NR" strings are treated as *missing* ratings and follow
   the separate **Hide Unrated Media** toggle (strict households opt in), never as
   adults-only.
2. **Enforcement at every layer.** The limit filters Home rails (resume/next-up/latest,
   including locally pinned Up Next items), library grids, search results, similar/
   special-features rails, Live TV recordings, and CarPlay lists — and, independently,
   **gates the item detail screen and playback presentation** so a restricted item
   reached by deep link, stale navigation, or a downloaded record shows a clear
   "Restricted Content" explanation instead of content. The explanation names the
   setting so a parent understands *why* the item is unavailable.
3. **Navigation containers stay visible** (libraries, folders, music containers,
   photos) so the app remains navigable under any limit.
4. **Age-aware defaults via Declared Age Range (iOS 26+ / macOS 26+).** Settings →
   Content Restrictions offers *Set from Age Range* where Apple's `DeclaredAgeRange`
   framework exists. It requests an age **range** (gates 13/16/18) through the system
   sheet; Gus receives at most "under 13 / 13–15 / 16–17 / 18+" and maps it to a
   suggested limit (All Ages / Teen / Mature / no change). Declining shares nothing and
   changes nothing. Gus persists only the resulting limit selection — the range itself
   is discarded after mapping.

## Jellyfin rating-field mapping

`MediaItem.officialRating` (Jellyfin `OfficialRating`) is the gate input. Jellyfin's
numeric `CustomRating`/parental-rating score is server-configured and inconsistent
across metadata providers, so Gus normalizes the *string* systems above instead.
Server-side enforcement remains the stronger control: Jellyfin user accounts support
`MaxParentalRating` and library-level access; the Settings footer points parents to
pair the in-app limit with Jellyfin user permissions and Screen Time app limits.

## Behavior for unrated media

Missing or explicitly-unrated items are admitted by default and hidden when **Hide
Unrated Media** is on. Rationale: self-hosted libraries are full of personal,
home-video, and niche content that will never carry a rating; blocking it by default
would make the feature unusable, while the strict toggle serves households that need it.

## Platform availability & entitlement/review requirements

| API | Availability | Entitlement | Status |
|---|---|---|---|
| App-level `ContentRatingGate` | All platforms (incl. watchOS browse) | none | shipped |
| DeclaredAgeRange (`AgeRangeService`) | iOS 26+/macOS 26+ (visionOS/tvOS/watchOS unavailable) | `com.apple.developer.declared-age-range` | code shipped; entitlement request pending (CarPlay-style: code self-disables without it) |
| ManagedSettings read of device media-rating restrictions | iOS/iPadOS | Family Controls (`com.apple.developer.family-controls`, distribution requires Apple approval) | **follow-up only** — per the roadmap, pursued only if Gus needs Screen-Time-style controls beyond media-rating filtering |
| PermissionKit / significant-change parental consent | iOS 26.4+ | TBD | evaluated; not needed while Gus collects nothing and ships no communication features |

App Review notes: the gate is a *parental convenience*, not an age-verification claim.
Gus must never describe it as preventing access (a device passcode/Screen Time lock on
Settings is the enforcement layer Apple provides).

## Privacy & data retention

- No birthdates, no exact ages, no age ranges at rest. The Declared Age Range response
  is consumed in-memory and only the chosen rating tier persists (`UserDefaults`).
- The rating limit and hide-unrated flag are device-local preferences; nothing syncs to
  the server or the developer.
- Privacy manifest/labels are unaffected (no new data types collected).

## App Store Connect age rating impact

Unchanged (expected 4+): the app itself ships no rated content. The questionnaire
answers and the parental-controls disclosure live in
`Documentation/AppStore/review-compliance-audit.md`.

## Test matrix

| Scenario | Expected |
|---|---|
| Child (declared <13) uses Set from Age Range | Limit becomes All Ages; restricted items disappear from rails/search; detail/playback of a restricted item shows the Restricted Content explanation |
| Teen (13–15) declared | Limit becomes Teen; PG-13/TV-14/12A/FSK-12 admitted; R/TV-MA/FSK-16 gated |
| 16–17 declared | Limit becomes Mature; NC-17/X-tier still gated |
| Adult (18+) declared | Limit unchanged |
| Declined sharing | No change; no error; nothing stored |
| OS/platform without DeclaredAgeRange | Button absent; manual picker only |
| Entitlement missing (pre-grant build) | Request fails gracefully; status message; manual picker unaffected |
| Unrated item, Hide Unrated off/on | Admitted / hidden+gated |
| International ratings (BBFC/FSK/ACB/prefixed/bare-age) | Mapped per `ContentRatingGateTests` |
| Deep link / downloaded record to restricted item | Detail and player both gate with explanation |
| Containers under strictest limit | Libraries/folders/albums/photos remain navigable |

## Explicit non-goals

Custom PIN locks, in-app child profiles, birthday pickers, and any developer-side age
inference. Apple's system controls (Screen Time, Ask to Buy, device passcode) plus
Jellyfin's server-side user permissions are the enforcement layers; Gus integrates with
them rather than re-implementing them.
