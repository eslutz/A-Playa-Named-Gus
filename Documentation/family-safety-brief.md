# Family Safety & Age Assurance — Product Brief

This guide describes implemented controls and their verification scope. Declared
Age Range still needs real-device acceptance of the system sheet and tier mapping.

Gus's stance: **parent-friendly content controls built on Apple-provided safety APIs**,
never a custom age-verification or child-profile system. Gus stores no birthdates, no
exact ages, and no per-child identity data.

## Implemented scope

1. **Content-rating limit (all platforms).** Settings → Content Restrictions offers
   Off / All Ages / Parental Guidance / Teen / Mature. `ContentRatingGate` maps official
   rating strings onto comparable tiers and covers:
   - US movie (MPA) and US TV systems,
   - UK (BBFC), Germany (FSK), Australia (ACB) / New Zealand (OFLC), Canada,
   - country-prefixed forms Jellyfin emits (`DE-16`, `GB-12A`, `US-PG-13`),
   - bare minimum-age ratings (`6`, `16`, `16+`) by age bracket.
   The manual Hide Unrated Media preference applies when a rating limit is active.
   Sharing a minor range always hides missing, unknown and explicitly unrated media.
2. **Enforcement at every layer.** The limit filters Home rails (resume/next-up/latest,
   including locally pinned Up Next items), library grids, search results, similar/
   special-features rails, Live TV recordings, and CarPlay lists — and, independently,
   **gates the item detail screen and playback presentation** so a restricted item
   reached by deep link, stale navigation, or a downloaded record shows a clear
   "Restricted Content" explanation instead of content. The explanation names the
   setting so a parent understands *why* the item is unavailable.
3. **Navigation containers** such as libraries, folders, playlists and albums remain
   visible under a rating ceiling. Unrated photos follow the shared minor ceiling.
4. **Declared Age Range on iPhone, iPad and Mac.** After Jellyfin sign-in, Gus checks
   Apple's regional requirement. Where sharing is optional it offers Check Age Range
   or Not Now once per server account on this device, including after upgrading.
   Settings → Content Restrictions → Check Age Range remains available. When Apple
   requires the range, Gus requests it before showing media. A failed or declined
   required request offers retry. A device with a previously resolved policy can
   continue offline using its last known requirement and limit. CarPlay and Siri also
   check the requirement when they restore a session before a Gus window opens.
   When sharing is required, open Gus to complete Apple's prompt. CarPlay refreshes
   its library when the device policy changes.

Gus requests thresholds 13, 16 and 18. Apple can return regional thresholds. Gus
uses the lower bound conservatively and stores a separate device-wide rating ceiling.
The effective limit is the stricter of the manual preference and this ceiling.
Only a fresh shared range can relax the ceiling. Settings permits stricter limits.
A fresh adult range clears the ceiling and preserves the household's manual choices.
Switching Jellyfin accounts, declining a request or losing connectivity preserves a
previous ceiling. To change the declaration, use Apple's Age Range for Apps settings,
then check again in Gus. [Apple's Declared Age Range guidance](https://developer.apple.com/documentation/declaredagerange/requesting-people-share-their-age-range-with-your-app)

## Jellyfin rating-field mapping

`MediaItem.officialRating` (Jellyfin `OfficialRating`) is the gate input. Jellyfin's
numeric `CustomRating`/parental-rating score is server-configured and inconsistent
across metadata providers, so Gus normalizes the *string* systems above instead.
Server-side enforcement remains the stronger control: Jellyfin user accounts support
`MaxParentalRating` and library-level access; the Settings footer points parents to
pair the in-app limit with Jellyfin user permissions and Screen Time app limits.

Gus enforces the device ceiling in browsing, Seerr, detail links and online and
offline playback. A rating certificate with an explicit minimum such as GB-18
requires the corresponding minimum age in addition to the broad tier. Set Jellyfin
parental permissions for restrictions that must follow the account into other apps,
devices or a fresh installation.

## Platform availability & entitlement/review requirements

| API | Availability | Entitlement | Status |
|---|---|---|---|
| App-level `ContentRatingGate` | All platforms (incl. watchOS browse) | none | implemented |
| DeclaredAgeRange (`AgeRangeService`) | iOS 26+/macOS 26+ (visionOS/tvOS/watchOS unavailable) | `com.apple.developer.declared-age-range` | implemented; entitlement wired; real-device system-sheet verification remains |
| ManagedSettings read of device media-rating restrictions | iOS/iPadOS | Family Controls (`com.apple.developer.family-controls`, distribution requires Apple approval) | **follow-up only** — per the roadmap, pursued only if Gus needs Screen-Time-style controls beyond media-rating filtering |
| PermissionKit / significant-change parental consent | iOS 26.4+ | TBD | evaluated; not needed while Gus collects nothing and ships no communication features |

## Privacy and data retention

Gus processes the range in memory. On device it retains the derived ceiling, manual
preferences, the regional requirement status and whether each account has seen the
optional offer. Age bounds, declaration source and birthdate are never persisted.
Gus does not send the result to Jellyfin, Seerr, iCloud or the developer.

## App Store Connect age rating impact

Do not infer a store age rating from the presence of parental controls. Verify
the current rating and disclosures in App Store Connect. Draft questionnaire
answers and the parental-controls disclosure live in
`Documentation/AppStore/review-and-disclosures.md`.

## Test matrix

| Scenario | Expected |
|---|---|
| Under 13 | All Ages ceiling, unrated hidden |
| 13–15 | Teen ceiling admits PG-13, TV-14 and FSK-12. R and GB-15 are hidden |
| 16–17 | Mature ceiling admits TV-MA and FSK-16. GB-18, NC-17 and unrated are hidden |
| Adult shared after a minor | Removes the device ceiling and restores the household's manual choices |
| Optional Not Now or decline | Records the offer for that account. Existing ceiling still applies |
| Required request fails or is declined | Media access remains gated. Retry and sign-out are available |
| First eligibility lookup unavailable | Retry eligibility before browsing. Existing resolved policy remains available on subsequent offline launches |
| Switch Jellyfin accounts | Device ceiling persists. A new account gets its own optional offer |
| OS without Declared Age Range | Manual picker available in Settings on platforms with Settings |
| Unrated cover member, search result, deep link or download | Hidden or blocked under a minor ceiling |
| Try a more permissive manual limit | Picker exposes only choices at or below the device ceiling |

## Explicit non-goals

Custom PIN locks, in-app child profiles, birthday pickers, and any developer-side age
inference. Apple's system controls (Screen Time, Ask to Buy, device passcode) plus
Jellyfin's server-side user permissions are the enforcement layers; Gus integrates with
them rather than re-implementing them.
