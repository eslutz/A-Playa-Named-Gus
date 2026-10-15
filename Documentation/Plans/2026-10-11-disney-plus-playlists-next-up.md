# Disney+, Playlists, and Unified Next Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking. This is a draft for review, not authorization to implement or connect a subscriber account.

**Goal:** Search and organize Jellyfin and Disney+ together, create ordered movie/episode playlists, and replace Home's separate Continue Watching and Next Up rails with one list named **Next Up**.

**Architecture:** Keep Jellyfin playback behind `MediaProviderSession`. Add a separate catalog/account boundary for streaming services, source-aware media references, and Gus-owned watchlists/playlists. Derive Next Up from source progress, series continuation, and explicit user intent; route playback to AVKit or an external service.

**Tech Stack:** Swift, SwiftUI, Observation, Foundation/URLSession/Codable, Security Keychain, AVKit, Swift Testing; optional CloudKit/CKSyncEngine. No additional third-party runtime dependency is proposed.

**Spec:** The [proposed design](#proposed-design) and [Next Up options](#next-up-options) below; API evidence is in [the Disney+ investigation](../Research/2026-10-11-disney-plus-api-investigation.md).

**Status:** Original proposal dated 2026-10-11; reconciled with the implemented baseline on 2026-10-13. Disney+ subscriber authentication, catalog/progress operations, and external episode handoff remain unvalidated proposals. The original task checkboxes below record proposed work, not current completion; use the implementation ledgers for delivered scope.

## Implemented baseline and remaining scope — October 13

| Scope | Current status and source of truth |
|---|---|
| Unified Jellyfin Next Up, Home and Top Shelf | Implemented; see [Next Up ledger](../Reviews/2026-10-12-next-up-playlists/IMPLEMENTATION.md). Cross-provider identity, ordering and Disney progress remain proposed. |
| Jellyfin playlists and collections | Implemented with native server ownership, account-scoped offline cache/journal, and supplemental Gus cursor/Next Up state; see [native-list ledger](../Reviews/2026-10-13-jellyfin-lists/IMPLEMENTATION.md). The verified server deduplicates repeated titles; legacy repeated-title imports are blocked with originals preserved. |
| Private CloudKit supplemental state | Implemented for Gus saved intent, cursors and activity. Signing/container provisioning is enabled and Cloud distribution succeeded; physical multi-device sync, account-change and conflict acceptance remain separate open gates. |
| Native TV presentation | Merged through [PR #22](https://github.com/eslutz/A-Playa-Named-Gus/pull/22); see [TV integration](../Reviews/2026-10-13-tvos-redesign/INTEGRATION.md) and [runtime evidence](../Reviews/2026-10-13-tvos-redesign/RUNTIME.md). |
| Disney+ and mixed-provider lists | Remaining proposal: authenticated access proof, profile isolation, catalog/reference contracts, external playback handoff, progress semantics, and a separately approved mixed-list authority. |
| Hosted validation | Build 17 on merged commit `a794a7f308c3c4281e6b98a5f2f908f3a684207b`: all four Cloud tests, archives and internal TestFlight actions succeeded, with zero issues across all 12 actions. This does not prove Disney access or physical sync/accessibility. See [pipeline acceptance](../AppStore/pipeline-policy.md#verified-merged-main-acceptance--2026-10-13). |

Tasks 1–5 remain Disney/cross-provider proposals. Tasks 6–10 overlap delivered Jellyfin functionality and must be scoped to the remaining mixed-provider work before execution; do not recreate the stores or replace native Jellyfin list authority from this draft. Task 11's Disney Halloween scenario is still unaccepted.

The original design and sequencing below are retained for provenance. Where they conflict with the current ledgers, current architecture and `CLAUDE.md` take precedence. Gus-owned ordered mixed-provider lists and repeated Disney entries are future design choices, not capabilities of the implemented native Jellyfin lists.

## Global constraints

- Read `CLAUDE.md`; use native Apple APIs and the existing provider/domain boundary.
- Require OS 27.0 on iOS/iPadOS, tvOS, macOS, visionOS and watchOS, as defined by `project.yml`.
- Use `@Observable @MainActor` stores and async/await. Keep platform divergence in `Sources/Platform/`.
- Store credentials only in Keychain. Exclude secrets from Codable models, logs, fixtures, URLs, CloudKit, Spotlight, and Top Shelf.
- Existing Jellyfin accounts, links, offline playback, audio playlists, and parental restrictions must keep working.
- Disney+ playback opens the external service. Automatic return/continuous external playlist playback is outside this plan.
- Regenerate the Xcode project after adding/changing source membership; localize new copy; run required multiplatform checks.
- Update relevant wiki/website claims only when behavior actually ships. Planning must not advertise proposed capabilities as available.

## Review focus

1. A late response after profile/account switching must not leak the previous user's progress or catalog restrictions. Tests: tasks 2, 4, 8.
2. Identical source IDs, alternate episode numbering, and ambiguous cross-provider matches must not merge unrelated items. Tests: tasks 3, 4, 8.
3. Missing/stale watch state or timestamps must remain unknown; a refresh or external link open must not invent a viewing event. Tests: tasks 3, 7, 8.
4. Repeated playlist entries, offline edits, and paused/interrupted playback must preserve order and cursor. Tests: tasks 6, 7, 10.
5. One unavailable provider must not erase another provider's results or prevent a saved playlist opening. Tests: tasks 5, 8, 9.

## Proposed design

### User-facing scope

- Settings gains **Streaming Services** with Disney+ connection, selected profile, connection state, refresh, and disconnect.
- Search offers All, Jellyfin, and Disney+ scopes. Disney+ appears as a browsable source in Libraries. Item details show source options and the correct Play/Open action.
- A user can find a show, inspect seasons, select individual Halloween episodes, and add them to a named **Playlist** in any order.
- Playlists support create/rename/delete, add/remove/reorder, duplicate entries, Play from Beginning, Continue Playlist, and Play from Here. Version one covers movies and episodes; show-level entries require selecting episodes first.
- Existing Add/Remove Up Next actions become **Add/Remove Next Up** for user-facing consistency. Their durable intent remains a saved watchlist entry, not a playback queue position.
- Home has one **Next Up** list, with progress, reason, source, and freshness where relevant. A playlist can be explicitly added to it as one card.
- App detail, playlist, and saved-list operations remain available from cached data during a provider outage. First-version ownership remains scoped to the current Gus/Jellyfin user; a Disney-only sign-in root is a separate product change.

### Domain and interfaces

Create shared catalog types under `Sources/Models/Catalog/` and contracts under `Sources/Providers/Catalog/`:

| Type | Required meaning |
|---|---|
| `CatalogSourceKind` | `.jellyfin`, `.disneyPlus`; separate from media-server backend identity |
| `CatalogContext` | Gus `AccountScope`, logical connection ID, selected provider profile, region, language, and restriction context; context revision invalidates in-flight work |
| `CatalogMediaRef` | Source, connection, profile, and provider item ID; equality includes all four |
| `CatalogTitle` | Stable Gus UUID, movie/episode/series/season kind, presentation metadata, optional external IDs/series relationship, and one or more source references |
| `SourceWatchState` | Source reference; watched state `unknown/unwatched/inProgress/completed`; optional fraction/position, observedAt, and optional authentic activity timestamp |
| `SourceOffer` | Source reference, artwork, availability `available/unavailable/unknown`, and action capability; no credentials |
| `PlaybackDestination` | `.jellyfin(CatalogMediaRef)` or `.external(CatalogMediaRef, URL)`; resolve fresh before acting |
| `SavedWatchlistEntry` | UUID, title ID, optional addedAt/legacy ordinal, optional preferred source, hidden intent, and optional pinnedAt |
| `VideoPlaylist` / `PlaylistEntry` | Playlist UUID/name/revision; entry UUID/title ID/order/preferred source; repeated titles have distinct entry UUIDs |
| `PlaylistCursor` | Playlist ID, entry ID, and state `ready/playing/awaitingConfirmation/finished`; independent of a title's watched state |
| `NextUpEntry` | Stable card ID, title or playlist target, reasons, selected source/watch state, ordering inputs, availability, and stale-state marker |

`CatalogSession` produces `search(_:cursor:)`, `seriesPage(_:)`, `episodes(in:cursor:)`, `watchStates(for:)`, `continueWatching(cursor:)`, `savedTitles(cursor:)`, and `destination(for:)`, all async/throwing and context-scoped. `CatalogPage` carries values plus an opaque continuation cursor; do not pretend every provider has Jellyfin-style offsets or totals.

Add a separate optional `SeriesContinuationSession.nextEpisode(after:)` capability only after validating what Disney's Up Next response means. Unknown watched state is not proof an episode is unwatched.

`JellyfinCatalogSession` adapts existing `MediaProviderSession` operations. `DisneyCatalogSession` uses the validated Disney transport/auth context. Neither forces Disney to implement downloads, Live TV, Jellyfin reporting, or in-app stream resolution.

`CatalogIdentityResolver` matches only verified external IDs with compatible type and episode identity. Request/map Jellyfin external IDs explicitly. Title text alone never causes an automatic merge; unmatched items retain source-specific identities. A future manual matching UI is not required for version one.

`CatalogActionRouter.resolve(_:preferredSource:purpose:)` returns a `PlaybackDestination`. Resume uses the source whose progress is displayed. Play from Beginning uses zero locally; an external provider may resume its own bookmark, so never promise that a link resets Disney's progress.

Declare `CatalogPage`, `CatalogSession`, and `SeriesContinuationSession` together in `CatalogSession.swift`; declare `PlaybackDestination` and `PlaybackPurpose` (`beginning/resume`) in `Sources/Models/Catalog/PlaybackDestination.swift`. Declare `SavedWatchlistEntry` in `Sources/Models/SavedWatchlistEntry.swift`, `PlaylistEntry` with VideoPlaylist, and `NextUpInput` with NextUpEntry. Task 4 owns these shared declarations except the playlist/Next Up models owned by tasks 6/8.

### Persistence and refresh

- Local-first, versioned Codable stores with atomic writes and recoverable decoding failures. Persist list edits before showing success; preserve a corrupt file for recovery rather than silently overwriting it with an empty list.
- Keep current `AccountScope.storageKey` and account boundaries intact. Development-era credential/storage migrations were removed under the OS 27 policy; do not restore them from this draft. New connection/profile/reference keys must be collision-safe.
- Reuse implemented saved intent and explicit native-list import/recovery. Any future mixed-provider import must preserve originals and genuine timestamps, remain idempotent, and honor native-list uniqueness; do not automatically migrate or recreate the historical `UpNextPersistence` design.
- Refresh on explicit refresh and foreground/return from an external player. Default minimum automatic refresh interval: five minutes per provider/profile; cache existing results and cancel stale tasks. This is a Gus proposal, not a documented Disney service limit; revise it from authenticated evidence if needed.
- Refresh failures retain cached values with stale/error state. Authentication failure disconnects only the affected streaming connection, not the Jellyfin session.
- Store observedAt separately from actual activityAt. A refresh must not make every item look recently watched. No repeated background polling while another app plays.
- Logical streaming connection IDs are durable Gus identities, separate from per-device authorization. If sync is selected, a newly linked device may reuse a logical connection only after the provider account/profile identity is verified; it never imports another device's credentials.
- Disconnect deletes tokens and imported personal state; retain Gus-owned list/playlist entries as unavailable references. Offer explicit removal of those entries separately.

## Next Up options

All options produce one list called **Next Up**, combine identical automatic title entries, retain source choices, and distinguish resumable media from queued media.

| Option | Ordering | Strength | Trade-off |
|---|---|---|---|
| **A. Resume first — recommended** | Explicit pins; unfinished media/active playlists; next episodes; saved watchlist/queued playlists | Predictable; works when provider activity timestamps are incomplete | Less interleaving of older resumable items and newer series |
| **B. Recent activity** | Explicit pins; remaining cards ordered by latest reliable viewing/list interaction across categories | Feels current and naturally blends Resume and Next Episode | Requires trustworthy dates; missing dates use stable fallback and cannot be labeled recently watched |
| **C. Manual queue** | User-controlled order; new automatic candidates appended; row actions resume or start as appropriate | Maximum control for planned viewing | Requires ongoing cleanup and conflict handling; Home order can diverge from natural series progression |

Do not implement three preference modes by default. Choose one before task 8; draft task contracts assume A. B changes only ranking and its fixtures. C also requires persistence/reordering of Home entries and is an additional deliverable beyond saved watchlist intent.

### Exact proposed rules for A

1. Apply provider restrictions and Gus rating gates before publication, matching, or system indexing. Unknown/unrated media follows the existing Gus policy.
2. Generate candidates from resumables, verified series continuation, saved Gus intent, imported provider watchlist titles, and explicitly queued playlists. Provider watchlist entries carry read-only provider provenance rather than becoming Gus pins. Discovery recommendations do not belong in this list.
3. Deduplicate automatic entries by canonical title. For automatically followed TV series, one unfinished episode suppresses the next-episode card for that series; choose the most recent reliable activity, then source preference and stable identity as tie-breakers.
4. Explicitly saved different episodes are exempt from the one-automatic-card-per-series rule. They remain independently actionable. Exact-episode duplicates still collapse into one card carrying both reasons. Playlist entries never collapse; their order is separate from Home ranking.
5. When multiple sources contain the same episode, preserve independent progress. Prefer the user's resumable source, otherwise the freshest reliable resumable source, otherwise Jellyfin then Disney+ as a stable tie-break. Never choose Jellyfin at zero progress while displaying Disney's progress.
6. Pins lead, newest pinnedAt first. Within resume and next-episode buckets, order by reliable activity descending; missing dates use stable first-seen order after dated items. Within saved-only cards, use authentic addedAt descending, then migrated legacy order or stable first-seen order when no date exists. Tie-break by stable card ID.
7. A playlist card shows its current entry and `n of total`; an explicit Play action makes it an active playlist in the resume bucket. For an external handoff this represents playlist intent, not proof the episode played. Adding a playlist without starting it places it in the saved bucket. Pins may intentionally move it ahead of resume items.
8. A confirmed completed movie leaves the automatic list; a confirmed completed episode advances that series when the next episode is verified. If a saved episode remains queued for rewatch, keep its explicit intent. Do not remove a playlist merely because its individual episodes were watched previously.
9. Explicit intent remains visible when unavailable, behind available unpinned cards within its bucket, with an explanation. Purely automatic unavailable candidates are excluded. A transient failure is stale/unknown, not confirmed unavailable.
10. **Hide** suppresses that displayed title/card across automatic/imported reasons and marks any local saved intent hidden. A different episode can appear after progression; unhide restores the card. **Remove Next Up** removes Gus saved intent, not provider progress; provider-only saved cards offer Hide instead of implying a Disney watchlist write. **Mark Watched** writes Jellyfin when supported; for Disney it is a clearly identified Gus-only override and never silently alters Disney's history.

Examples: an unfinished Disney episode appears before an unwatched Jellyfin next episode; the same episode's watchlist and resume reasons share one card; a Halloween playlist preserves S03E12 → S01E07 → S05E09 even if the provider's normal next episode differs.

## Original proposed delivery sequence and checkpoints

Four workstreams share the contracts above: **Disney access (1–3)**, **catalog integration (4–5)**, **playlists (6–7)**, and **Next Up (8–9)**. Each produces a separately testable deliverable. Tasks 10–11 cover optional sync and release acceptance.

```text
1 authenticated evidence + 4 shared contracts → 2 auth/session → 3 Disney catalog
4 → 6 playlist editor; 3 + 6 → 5 library/search
3 + 6 → 7 playback/handoff; 3 + 4 + 6 + 7 → 8 Next Up → 9 Home/system UI
6 → 10 optional cross-device sync; selected deliverables → 11 acceptance
```

Task 1 is the Disney go/no-go checkpoint. Shared models and Jellyfin-only features may proceed independently, but must not be reported as completion of the user's Disney-only Halloween scenario.

### Task 1 — Prove authenticated Disney+ reads and episode links

**Files:** Add sanitized evidence under `Documentation/Research/disney-plus-authenticated/`; update the existing investigation. Temporary probe code remains outside app targets.

**Consumes:** Prior endpoint evidence. **Produces:** A validated authentication strategy, response fixtures, capability matrix, identifier mapping, observed freshness, and platform link results.

- [ ] Establish the intended access route: Disney-granted access if obtained, otherwise a documented experimental internal-client route. Do not assume an affiliate signup grants API access or publish another client's embedded credentials as Gus credentials.
- [ ] With user-controlled sign-in, validate one adult profile and one restricted profile where available. Record password/OTP/pairing support, token renewal, expiry, logout, and profile isolation without saving secrets. Account access requires the user to sign in; it is not supplied by this plan.
- [ ] Read a search, a show's season pages, individual episode metadata, known unfinished/completed episode states, Continue Watching, saved titles, and candidate next-episode responses. Distinguish missing state from zero progress and recommendations from actual continuation.
- [ ] Capture redacted fixtures preserving structural IDs via consistent replacements. Exclude account names, emails, tokens, cookies, signed URLs, and passwords. Record exact JSON field semantics; do not design production decoding from guessed fields.
- [ ] Open an actual episode URL on iPhone/iPad, Apple TV, Mac, and Vision Pro where available. Record episode/detail destination, app/web fallback, profile selection, and behavior with missing app/expired subscription; unresolved platforms have unavailable capability.
- [ ] Exit only with reproducible authenticated reads and a verified episode destination on at least the initial supported platform. If authentication fails, report the concrete blocker and recovery path; don't substitute the prior HTTP 200 configuration probe for acceptance.

### Task 2 — Disney+ connection lifecycle

**Create:** `Sources/Providers/DisneyPlus/{DisneyTransport,DisneyAuthentication,DisneySessionContext}.swift`, `Sources/Models/StreamingConnection.swift`, `Sources/Stores/StreamingConnectionsStore.swift`, `Sources/Features/Settings/StreamingServicesView.swift`, `Sources/Platform/StreamingAuthenticationSupport.swift`.
**Modify:** `Sources/Services/KeychainStore.swift`, `Sources/App/GusApp.swift`, `Sources/Features/Settings/SettingsView.swift`, `Sources/Platform/RootNavigationState.swift`.
**Test:** `Tests/APlayaNamedGusTests/DisneyAuthenticationTests.swift`, `StreamingConnectionsStoreTests.swift`.

**Consumes:** Task 1's auth contract. **Produces:** Context-scoped transport/session and observable `disconnected/connecting/connected/expired/failed` connection states; cancellation and reauthentication.

- [ ] Write failing `renewalIsSingleFlight`, `lateResponseAfterProfileSwitchIsDiscarded`, `disconnectErasesCredential`, and `disney401DoesNotSignOutJellyfin` tests. Two concurrent expired-token reads cause one renewal; a pre-switch result never enters the new profile's store.
- [ ] Run the new suites and confirm those failures before implementation.
- [ ] Implement the verified auth flow, per-device Keychain persistence, shared renewal task, and context revisions using native frameworks. Passwords/OTPs are transient; retries are bounded and do not resubmit credential challenges indefinitely.
- [ ] Provide native connection/profile/reconnect UI with loading, error, cancel, retry, refresh, and disconnect. Gate platform flows by demonstrated capability; unsupported platforms can still show saved playlist entries and verified external links.
- [ ] Run suites and a real sign-in/renewal/disconnect check; commit only task-owned changes, strings, and regenerated project membership.

### Task 3 — Disney catalog, progress, and destinations

**Create:** `Sources/Providers/DisneyPlus/{DisneyCatalogSession,DisneyCatalogDTOs,DisneyCatalogMapper}.swift`, sanitized fixtures under `Tests/APlayaNamedGusTests/Fixtures/DisneyPlus/`.
**Test:** `Tests/APlayaNamedGusTests/{DisneyCatalogSessionTests,DisneyCatalogMapperTests}.swift`.

**Consumes:** Task 2 transport and task 4 catalog contracts. **Produces:** Disney `CatalogSession`; optional verified series-continuation capability.

- [ ] Write failing fixture tests `searchCursorPreservesProfileContext`, `seasonPaginationKeepsDisneyOrder`, `missingProgressRemainsUnknown`, `percentageOnlyProgressHasNoExactPosition`, and `deeplinkRequiresProviderIdentifier`.
- [ ] Assert a verified 50% response maps to fraction 0.5; exact remaining seconds can derive position with a valid duration; percentage-only data does not claim an exact seek position. An unknown state cannot select the next unwatched episode.
- [ ] Implement only proven response fields and endpoint templates. Batch/cache user-state requests for visible/saved titles; don't crawl every title just to build watch history. Bound pagination and retries; retain opaque cursors and per-source errors.
- [ ] Normalize valid positions/fractions; represent malformed/missing fields as unknown without failing unrelated items. Preserve provider episode order and multiple IDs rather than inferring sequence solely from title text or Jellyfin numbers.
- [ ] Run fixture suites, then compare live reads to Disney's displayed state for known episodes. Re-fetch after watching externally and measure observed update delay. Publish the capability matrix and focused commit.

### Task 4 — Shared identity, source offers, and durable saved intent

**Create:** `Sources/Models/Catalog/{CatalogMediaRef,CatalogTitle,SourceWatchState,SourceOffer,CatalogContext,PlaybackDestination}.swift`, `Sources/Models/SavedWatchlistEntry.swift`, `Sources/Providers/Catalog/{CatalogSession,JellyfinCatalogSession}.swift`, `Sources/Stores/{CatalogStore,SavedWatchlistStore}.swift`, `Sources/Services/{CatalogIdentityResolver,SavedMediaPersistence}.swift`.
**Modify:** `Sources/Providers/Jellyfin/JellyfinMediaItemMapper.swift`, `Sources/Stores/UpNextStore.swift` (migration/compatibility), and DTO requests in `JellyfinMediaProviderSession.swift` to request external IDs.
**Test:** `CatalogIdentityTests.swift`, `SavedWatchlistStoreTests.swift`, `UpNextStoreTests.swift`, `ProviderArchitectureTests.swift` under `Tests/APlayaNamedGusTests/`.

**Consumes:** Existing Jellyfin session/models. **Produces:** Shared contracts, Jellyfin adapter, stable identity resolution, and migrated saved watchlist.

- [ ] Write failing tests `sameRawIDAcrossSourcesIsDistinct`, `sameRawIDAcrossProfilesIsDistinct`, `verifiedEpisodeIDsMergeOffers`, `titleOnlyMatchStaysSeparate`, `legacyMigrationPreservesOrder`, `migrationIsIdempotent`, and `corruptFileIsNotOverwritten`.
- [ ] Run these suites to confirm failures. Use legacy JSON fixtures with two entries and no addedAt; expect the same order after two migrations.
- [ ] Implement the shared contracts and versioned persistence. Keep source references and progress independent; map existing `MediaItem` for Jellyfin rather than spreading SDK DTOs into features. Migration never alters existing Keychain accounts or `AccountScope.storageKey`.
- [ ] Store Gus intent separately from imported Disney watchlists. Import provider titles as source records, not automatically as new manually pinned entries. Keep unsupported/unknown IDs stable with source-specific references.
- [ ] Run identity/migration tests plus existing provider tests; review exact file diffs and commit the domain/migration deliverable.

### Task 5 — Unified search, Libraries, and item details

**Create:** `Sources/Stores/FederatedSearchStore.swift`, `Sources/Features/Streaming/{StreamingLibraryView,StreamingItemDetailView,StreamingSeasonView}.swift`, `Sources/SharedUI/{CatalogPosterCard,SourcePicker}.swift`.
**Modify:** `Sources/Stores/SearchStore.swift` through an adapter, `Sources/Features/Search/SearchResultsView.swift`, `Sources/Stores/NavigationPreferencesStore.swift`, `Sources/Platform/{RootNavigationState,RootContainer,NavigationDestinations}.swift`, `Sources/SharedUI/Navigation.swift`.
**Test:** `FederatedSearchTests.swift`, `CatalogNavigationTests.swift`, and authenticated UI coverage under the existing platform UI-test directories.

**Consumes:** CatalogStore, both CatalogSession adapters, and task 6's add-to-playlist action. **Produces:** Search/browse/detail flows with typed, source-aware navigation and action capabilities.

- [ ] Write failing tests `disneyFailurePreservesJellyfinResults`, `newQueryDiscardsOldPages`, `sourceFilteringDoesNotLoseSavedEntries`, and `externalEpisodeRoutesToStreamingDetail`.
- [ ] Keep each source's pagination/cancellation/error state separate; merge compatible offers while retaining all results when one source fails. Loading a later page must not reorder previously displayed matches gratuitously.
- [ ] Add streaming source sections, All/Jellyfin/Disney+ filters, episode selection, artwork, availability/restriction state, and source badges. Present browse-by-show when episode-title search is not supported.
- [ ] Add a separate catalog navigation reference; preserve legacy ItemRef/ContentLink decoding. Ensure `.playlist` music routing continues to use `AlbumDetailView`; Gus video playlists have their own destination.
- [ ] Run search/navigation suites and native UI checks on phone, tablet, TV, Mac, and Vision Pro; include focus/VoiceOver, Dynamic Type, rotation, and unavailable-source states. Commit with localized strings and project regeneration.

### Task 6 — Playlist editing and persistence

**Create:** `Sources/Models/{VideoPlaylist,PlaylistCursor}.swift`, `Sources/Stores/VideoPlaylistsStore.swift`, `Sources/Features/Playlists/{PlaylistsView,PlaylistDetailView,AddToPlaylistView}.swift`.
**Modify:** `Sources/Features/Item/ItemDetailView.swift`, `Sources/Stores/NavigationPreferencesStore.swift`, `Sources/Platform/{RootNavigationState,NavigationDestinations}.swift`. Task 5 wires the editor into its new streaming detail views.
**Test:** `Tests/APlayaNamedGusTests/VideoPlaylistsStoreTests.swift`.

**Consumes:** Canonical titles and saved-media persistence. **Produces:** Durable playlist CRUD, ordered entry IDs, and persisted cursor.

- [ ] Write failing tests `reorderSurvivesReload`, `duplicateTitlesHaveDistinctEntries`, `removingCurrentEntryMovesToNextSurvivor`, `unavailableEntryRemainsVisible`, and `playlistStateIsAccountScoped`.
- [ ] Verify a three-entry playlist stays C → A → B after relaunch; adding A twice gives distinct entry IDs. Removing the current entry selects the next surviving successor, otherwise the prior survivor; an empty playlist clears its cursor.
- [ ] Implement create/rename/delete/add/remove/reorder, order revision, native move controls, and error-aware atomic saves. Rename trims whitespace, rejects an empty name, and permits duplicate names because UUID is identity.
- [ ] Add Playlist navigation and item context actions. Confirm destructive playlist deletion with a native dialog; deleting a playlist never deletes provider media or watched history.
- [ ] Run persistence tests and keyboard/TV-focus/VoiceOver editing checks. Commit the complete editor and its migration-safe storage.

### Task 7 — Local video queue and external playlist handoff

**Create:** `Sources/Stores/{VideoQueue,VideoPlaylistPlaybackCoordinator}.swift`, `Sources/Services/CatalogActionRouter.swift`, `Sources/Platform/ExternalMediaLauncher.swift`.
**Modify:** `Sources/Stores/PlaybackStore.swift`, `Sources/Stores/PlaybackReporting.swift`, session player hosts under `Sources/Platform/RootContainer.swift`, and `PlaylistDetailView.swift`.
**Test:** `VideoQueueTests.swift`, `ExternalMediaLauncherTests.swift`, and `PlaybackStoreTests.swift` under `Tests/APlayaNamedGusTests/`.

**Consumes:** Playlist/cursor, source references, destination resolver. **Produces:** Explicit ordered local playback and resumable external handoff state.

- [ ] Write failing tests `explicitQueueOverridesSeriesNextUp`, `completedTitlesAreNotSkippedInRewatchPlaylist`, `failedLaunchDoesNotAdvanceCursor`, `successfulLaunchDoesNotMarkWatched`, and `userReturnDoesNotInferCompletion`.
- [ ] Assert local queue C → A → B advances to A at C's natural end, not C's normal next episode. A duplicate entry is played again. Playback errors and manual dismissal do not count as natural completion.
- [ ] Add an explicit queue mode to PlaybackStore while preserving existing standalone series autoplay. Playlist Play from Beginning and Play from Here start the selected local entry at zero; Continue Playlist resumes its selected entry/source; subsequent local entries always start at zero. An explicit Play Playlist action enables sequence advancement independently of the standalone series-autoplay preference.
- [ ] Persist cursor before external launch. Resolve an allowlisted provider URL fresh, then open it with native platform APIs. Failed app/web handoff retains the entry with retry; success enters awaitingConfirmation. Reopening Gus refreshes progress without advancing merely because focus returned.
- [ ] Offer **Mark Finished & Next**, **Skip**, and **Open Again** after external handoff. Mark Finished is a playlist-instance confirmation; it does not mutate Disney history or necessarily mark every duplicate entry complete. Skip changes the cursor without a watched claim. Before confirming Next, show its destination.
- [ ] Snapshot order for the active session: reorders/additions apply to the next session; removals are honored before starting the next entry. A removed currently playing entry can finish, but must not be restored by a later cursor write; reconcile to the next surviving snapshot entry. Add `deletedSnapshotEntryIsNotResurrected` regression coverage. Before starting any subsequent entry, recheck source availability and rating gates. An unavailable/restricted/failed entry stops at that position with Retry/Skip/Stop rather than silently skipping.
- [ ] Run queue tests and real mixed/Jellyfin-only playback. Verify cancel, network failure, local downloads, app termination, and server-reported progress. Commit the coordinator/player integration.

### Task 8 — Unified Next Up derivation

**Create:** `Sources/Models/NextUpEntry.swift`, `Sources/Stores/UnifiedNextUpStore.swift`, `Sources/Services/NextUpBuilder.swift`.
**Modify:** `HomeStore.swift` to expose source snapshots without coupling all sources into one throwing load; feed SavedWatchlistStore and playlist cursors into the builder.
**Test:** `Tests/APlayaNamedGusTests/NextUpBuilderTests.swift`, `UnifiedNextUpStoreTests.swift`.

**Consumes:** Per-source watch/continuation/imported-watchlist snapshots, saved intent, playlist cursor, chosen ordering policy. **Produces:** `NextUpBuilder.build(_ input: NextUpInput) -> [NextUpEntry]`, shared by Home and credential-free snapshots. NextUpInput includes contexts, candidate arrays, preferences/suppressions, and stable ordering data.

- [ ] Select A, B, or C before implementation. Add failing tests for every numbered rule in the selected policy; draft A requires `resumePrecedesContinuation`, `resumeSuppressesSameSeriesContinuation`, `explicitDifferentEpisodeSurvives`, `mergedOfferUsesDisplayedProgressSource`, `refreshDoesNotInventActivity`, and `hiddenEpisodeDoesNotHideItsSuccessor`.
- [ ] Fixture assertions: unfinished Disney A precedes Jellyfin next B; A's saved+resume inputs yield one A; A and another explicitly saved episode C from the same series both survive; a refresh with unchanged activity preserves order; unknown progress cannot advance a series.
- [ ] Implement pure filtering, identity merge, reasons, selected source, suppression, and stable ranking exactly as specified above. Keep pin/remove/hide/local-watched override intent separate from authoritative provider state; changed provider watched/position data or a newer genuine activity timestamp clears an obsolete local watched override. Merely re-fetching unchanged data does not.
- [ ] Load sources independently and publish valid partial results. Context revisions invalidate old results. A confirmed outage marks only that source stale; newly restricted items are removed before cached cards are published.
- [ ] Run builder/store suites and existing HomeStore tests; check a real mixed source list against provider state and commit the deterministic aggregation deliverable.

### Task 9 — Home, navigation, and system surfaces

**Create:** `Sources/Features/Home/NextUpListView.swift`.
**Modify:** `Sources/Features/Home/HomeView.swift`, `Sources/SharedUI/CinematicDetailHero.swift`, `Sources/Models/{ContentLink,TopShelfSnapshot}.swift`, `Sources/Platform/ContentLinkHandler.swift`, `Sources/TopShelf/TopShelfContentProvider.swift`, `Sources/Services/SpotlightIndexer.swift`, `Sources/App/GusAppIntents.swift`; update Watch browse where supported.
**Test:** `ContentLinkTests.swift`, `NextUpPresentationTests.swift`, `TopShelfSnapshotTests.swift`, and appropriate UI tests.

**Consumes:** UnifiedNextUpStore and CatalogActionRouter. **Produces:** One user-facing Next Up list and consistent source-aware links/actions.

- [ ] Write failing tests `legacyGusLinksStillResolve`, `sourceLinkRejectsWrongAccountContext`, `topShelfContainsNoCredentials`, `expiredDisneyConnectionPreservesJellyfinHome`, and `jellyfinOutagePreservesDisneyHome`.
- [ ] Replace the two Home rails with one responsive Next Up rail (first 20 derived cards) plus a Show All list with incremental source pagination. Both honor the selected availability ordering, including retained unavailable explicit intent. Home remains usable when any connected source or saved content is usable; Jellyfin network errors must not block Disney cards. Cards display episode title/series, progress or next-episode reason, source/action, and playlist count where relevant. Do not treat the entire saved watchlist as a player queue.
- [ ] Route external details/actions through typed catalog targets. Introduce a versioned source-aware Gus link format while continuing to decode legacy `gus://item/<id>` and `gus://play/<id>`.
- [ ] Use the same builder order for Top Shelf. Snapshots contain only nonsecret account-scoped references and safe cached artwork; omit signed artwork links. Sign-out clears snapshots/indexes. Watch can browse supported saved entries and control Jellyfin; external video launching is not offered where unsupported.
- [ ] Run presentation/link/snapshot tests, native platform UI checks, and physical TV links. Preserve existing audio Now Playing, downloaded playback, and adaptive navigation. Commit user-facing integration and corresponding wiki/website updates.

### Task 10 — Optional cross-device list synchronization

**Decision:** Recommended if users will assemble Halloween playlists on iPhone and use them on Apple TV. Without this phase, collections are explicitly on-device. Local-first editing is required either way.

**Options:** (1) CloudKit private database — recommended native approach; (2) versioned JSON import/export — simpler, manual; (3) Gus backend — larger operating/auth scope, deferred. Jellyfin playlists cannot represent Disney-only entries reliably and are not the mixed-list authority.

**Create if selected:** `Sources/Services/{SavedMediaSyncEngine,SavedMediaConflictResolver}.swift`, `Sources/Features/Settings/SavedMediaSyncView.swift`.
**Modify:** `VideoPlaylistsStore.swift`, `SavedWatchlistStore.swift`, relevant `Config/*.entitlements`, `project.yml`, and signing-capability documentation.
**Test:** `SavedMediaSyncTests.swift`, `SavedMediaConflictResolverTests.swift`.

- [ ] Write failing tests `offlineEditsSurviveSyncFailure`, `deleteTombstonePreventsResurrection`, `concurrentAddsKeepBothEntries`, `accountSwitchDoesNotMixLists`, `relinkReusesVerifiedLogicalConnection`, and `credentialsAreExcludedFromSyncRecords`.
- [ ] Sync only Gus-owned lists, entries, ordering intent, cursor, necessary nonsecret title/reference/display snapshots, and logical connection/profile identities. Provider personal progress/history is refreshed locally; tokens/cookies/passwords are never synced. Each device establishes its own authorization for the verified account/profile; shared entries never bind to an arbitrary active Disney profile.
- [ ] Use CloudKit private records with CKSyncEngine and a durable local outbox. Explicitly handle signed-out iCloud and provider reconnect requirements. Sync eligibility follows the same Gus account and selected provider profile; account changes never relabel another user's entries.
- [ ] Conflict rules: entry operations retain UUIDs; additions merge; deletion tombstones win over older edits; field/reorder operations use logical revision plus stable device-ID tie-break, not wall-clock time. Apply concurrent moves deterministically, preserving unmodified surviving entries. Cursor is a separate record and never reorders the playlist.
- [ ] Run conflict tests, then create/reorder offline on iPhone and verify arrival and order on physical Apple TV/Mac. Validate development and production container/signing settings before claiming distribution support; commit the sync deliverable.

### Task 11 — End-to-end acceptance and release evidence

**Files:** New report under `Documentation/Reviews/disney-plus-playlists-next-up/`; update `Documentation/ROADMAP.md`, relevant wiki/website pages, and App Store privacy/support documents only for verified shipped behavior.

- [ ] Enforce the current zero-warning/error policy for compilation, tests, archives and exports, including tool/dependency diagnostics. Inspect exact-commit raw logs and Cloud issue lists.
- [ ] Run focused task suites as implemented. Discover installed destinations; run builds on iOS/iPadOS, tvOS, macOS, visionOS, and watchOS, then required shared unit-test lanes and applicable authenticated UI flows.
- [ ] Run `xcodegen generate`, `python3 Scripts/check-cloud-project.py`, `swiftformat Sources Tests --lint`, `jq empty Resources/Localizable.xcstrings`, and `git diff --check`; use `python3 Scripts/validate-release.py --phase all` for the repository's sequential release matrix.
- [ ] Complete the user's scenario: add episodes from at least three different Disney+ animated shows to **Halloween**, reorder them, relaunch, and open the intended episodes. Verify playlist-instance completion/skip and Next Up behavior. If sync is selected, create on iPhone and use on Apple TV.
- [ ] Verify Next Up with unfinished Disney media, Jellyfin continuation, explicit favorite episodes, a playlist, duplicates, disconnected provider, restricted profile, stale state, missing timestamps, and completed episodes. Confirm the chosen option and displayed source/progress agree.
- [ ] Verify backward compatibility: existing sign-in/restoration, saved Up Next migration, standalone series autoplay, audio playlists, downloads, legacy links, parental gates, sign-out cleanup, and platform navigation/focus/accessibility.
- [ ] Report source/test/build, authenticated API, physical playback/link, cloud-sync, and distribution outcomes separately. All required selected-scope gates must pass before marking the feature complete; blocked Disney access remains a concrete open blocker.

## Verification commands during task execution

Use the actual installed destination ID, not an assumed simulator name:

```sh
xcodebuild -showdestinations -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus'
python3 Scripts/run-warning-free.py xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus iOS Unit Tests' \
  -destination 'platform=iOS Simulator,id=<installed-UUID>' \
  -only-testing:GusTests/<task-suite>
```

Replace both placeholders with discovered values and the exact suite named in the task.
Before implementation the added assertions must fail for the specified behavior; after
implementation the same suite must pass. At each commit, stage exact intended paths and
include required localized/project changes; do not stage unrelated release evidence.

## Remaining Disney/mixed-provider decisions

| Decision | Proposed choice | Consequence |
|---|---|---|
| Disney access route | Custom direct adapter, conditional on task 1 proof | Avoids Younify; owns authentication/schema maintenance |
| Next Up policy | A, Resume first | Deterministic ordering even with incomplete Disney timestamps |
| Cross-device playlists | CloudKit phase if iPhone-to-TV use is required | Adds iCloud/signing/conflict work; credentials remain per device |
| External completion | User confirmation and provider refresh | Honest progress and durable cursor without an automatic return claim |
| Version-one ownership | Existing Gus/Jellyfin account scope | Adds streaming to current Gus; independent Disney-only onboarding is deferred |

## Planning references

- [Disney API evidence](../Research/2026-10-11-disney-plus-api-investigation.md)
- [Current provider decision](../adr/0008-media-provider-boundary.md)
- [Apple CloudKit platform support](https://developer.apple.com/icloud/cloudkit/)
- [Apple CKSyncEngine guidance](https://developer.apple.com/videos/play/wwdc2023/10188/)

Plan review: scope/tasks trace each requested capability; authentication unknowns are
isolated in task 1 rather than represented as supported production contracts. The
remaining decisions apply to Disney/mixed-provider behavior; implemented Jellyfin Next Up, native-list ownership and supplemental CloudKit state are the current baseline.
