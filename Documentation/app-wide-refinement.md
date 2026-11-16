# App-wide refinement implementation

Approved scope: all 22 Swiftfin comparison findings, source/version selection,
opt-in per-account same-series track preferences, native preview support and
page deduplication. Gus retains AVPlayer/AVKit and current OS 26 fallbacks.

## Shared contracts

- Account identity and a session generation bind asynchronous work to its owner.
  Expiry requests reauthentication without deleting current-format account data;
  forbidden operations remain distinct from expired credentials.
- Playback preparation, actual playing, progress and terminal outcomes are
  separate. One per-session reporter orders audio/video lifecycle boundaries.
  Native audio-session category or activation failures stop preparation and expose
  the existing failure/Retry state before media resolution or reporting begins.
  Resolution has a 30-second total budget; native preparation has 45 seconds.
  Safe reads have at most three attempts; allocating requests are never blindly
  retried. Reports and known-resource cleanup each have five seconds.
- iOS and iPadOS video retain a native Close button above AVKit during preparation,
  failure and ready playback, including sources without playback options. Close
  cancels preparation, stops playlist activity and tears down playback before dismissing;
  AVKit keeps its transport area. Other platforms retain their existing dismissal.
  tvOS explicitly fills the presentation viewport during preparation and native playback;
  the native UI regression checks its bounds before opening Playback Details.
- tvOS dismissal and navigation returns request the saved focus target immediately.
  One native fallback may reissue that request; a subsequent different choice wins.
  Playlist and collection tasks return to their More opener using the same action order.
- Foreground refresh retains usable content. Query generation rejects stale
  results. Full-content views and queues continue pages and deduplicate by scoped
  media identity; intentional preview limits remain explicit. Advertised totals
  survive omitted totals on later pages. Premature empty pages fail before advancing
  the retry offset or replacing retained content.
- Native actions communicate pending, accepted, confirmed, queued, uncertain and
  failed outcomes where applicable. Acceptance alone does not prove remote playback.
  Explicit remote start positions require observed position readback before confirmation.
  Partial writes report the fields that canonical readback proves were saved;
  uncertainty is reserved for unconfirmed outcomes. Uncertain collection writes require
  server review without introducing an offline edit journal. Leaving a screen cancels
  its reads without erasing the outcome of a transmitted write. Canceled profile saves
  after transmission require canonical readback before another save.
- Semantic artwork, accessibility identity and localized metadata are shared.
  OS 26 retains native AsyncImage transport. OS 27 uses a credential-lease-owned,
  memory-only native image session/cache that is canceled and cleared on retirement.
  Responsive controls and focusable information cards retain one content tree.
  Standard hero copy uses opaque backing at every width so artwork and text height
  cannot reduce its foreground/background contrast.
- Version changes ask whether to start over or resume at the saved timestamp.
  Track memory is opt-in per device/account, including a native Watch setting, and
  carries semantic preferences within a
  series. Persisted preferences contain no source-local indexes; missing or ambiguous
  named tracks fall back to defaults with a notice.
- Downloaded playback projects its recorded source rather than the item's primary
  version. Unknown source metadata remains unknown; converted files do not advertise
  the original source's unverified track catalog. Native transfer observations update
  only the current incomplete record under the same lock as finalization, so stale
  callbacks cannot overwrite completion or recreate deleted records. Completion
  ownership is captured before worker reads and invalidated by cancellation;
  completed records retain their conversion activity and current remote reference.
- Native previews use compatible I-frame HLS and tvOS chapter artwork. Jellyfin
  JPEG image playlists do not imply AVKit scrubber support; no custom scrubber.
- Retired readers/imports/CRUD are removed without a migration bridge. Current
  format data, current offline draft reconciliation and first verified iCloud
  identity ownership remain supported.

## Finding ledger

| Finding | Deliverable | Implementation | Verification |
|---|---|---|---|
| F01 | Identity-bound activation and recoverable expiry | AppModel, SessionLease, SessionAuthentication | SessionAuthenticationTests, AppModelSessionTests; physical account acceptance pending |
| F02 | Distinct forbidden/unauthorized outcomes | Typed Get status adapter; canonical auth probe for ambiguous delete policy | SessionAuthenticationTests, GusErrorTests |
| F03 | Ordered shared playback reports | Session-owned PlaybackReportQueue and immutable snapshots | PlaybackLifecyclePolicyTests; response-loss limits below |
| F04 | Truthful playback lifecycle and finalization | Shared native preparation; audio/video/Watch finalization, actual-playing observations and persistent iOS/iPadOS video dismissal | PlaybackLifecyclePolicyTests, TVPlaybackLifecycleTests, GusAuthenticatedUITests.testReadyVideoCloseReturnsToDetail; physical output pending |
| F05 | One resolution deadline/retry owner | PlaybackDeadline and StreamURLBuilder | PlaybackLifecyclePolicyTests, StreamURLBuilderTests |
| F06 | Watch credential and endpoint rotation | Central AppModel installation and lease invalidation | AppModelSessionTests; paired Watch acceptance pending |
| F07 | Truthful independent Live TV loading | Typed availability and independent channel/recording/timer phases | BrowseRefinementTests; configured tuner acceptance pending |
| F08 | Live resource ownership and seekability | Origin-owned allocation; Stop owns started-live release | PlaybackLifecyclePolicyTests; real tuner response-loss test pending |
| F09 | Remote action feedback | Shared ActionOutcome and capability/duplicate/explicit-position guards | RemoteSessionsTests, including explicitPositionConfirmation; physical target acceptance pending |
| F10 | Bounded invalidations and stale-response rejection | One remote refresh plus one follow-up, lease/generation/visibility checks | RemoteSessionsTests |
| F11 | Role-aware artwork and fallback adoption | MediaArtworkRequest, ordered URL candidates and lease-owned OS 27 native image transport; OS 26 native fallback | BrowseRefinementTests; exact-revision cache behavior and physical appearance remain validation gates |
| F12 | Complete shared accessible media identity | Shared Jellyfin and Seerr metadata projections | BrowseRefinementTests; physical VoiceOver acceptance pending |
| F13 | Resume-aligned initial series selection | Initial preferred season/episode, explicit-selection retention | BrowseRefinementTests, UIRemediationTests; remote focus acceptance pending |
| F14 | Latest-feed expansion on every main platform | Native Show All routes shared across main platforms | Source/caller coverage; device interaction matrix pending |
| F15 | Retained-content refresh | ForegroundLoadPhase plus domain-specific refresh/page errors; strict download metadata errors/retry | LibraryStoreTests, ItemDetailActionTests, SeerrCatalogStoreTests, BrowseRefinementTests, DownloadStoreIntegrationTests.unreadableMetadataLoading |
| F16 | Full-content continuation | Raw-offset paging, ordered queue continuation, full shuffle collection; incomplete advertised collections fail visibly | BrowseRefinementTests, including incompleteCollection; PlaybackLifecyclePolicyTests |
| F17 | Superseding first-page query changes | Immutable query identity and generation cancellation | LibraryStoreTests, BrowseRefinementTests |
| F18 | Reader construction/resource recovery | Readium errors preserve locator and expose retry | BookReaderLoadingTests; authenticated reader runtime acceptance pending |
| F19 | Every PR triggers required CI | Always-triggered workflow, fail-closed classifier, explicit documentation-only success | test-classify-changes.py; hosted required checks pending |
| F20 | Measured performance and justified retention/I/O fixes | Non-owning heavy-store lookup, owner/lease cancellation, visibility refresh, serial diagnostics and download workers | NavigationOwnershipTests, including replacementDetailOwnership and seriesLeaseCancellation; DiagnosticsTests, DownloadStoreIntegrationTests; comparable runtime measurements pending |
| F21 | Current platform visual/interaction/accessibility acceptance | Native controls retained; editable handoff reconciliation inventory in Design/README.md | Runtime/device matrix and saved editable handoff verification remain open |
| F22 | Catalog and native semantic formatting | Shared localized metadata and native duration/count formatting | Catalog validation and BrowseRefinementTests; RTL/largest-text runtime matrix pending |

The named tests are coverage pointers, not a claim that a particular revision has
passed. Exact revision, destinations, results and runtime artifacts belong in the
external validation manifest.

The action audit also covers ItemDetailActionTests, CollectionStoreTests,
UserProfileStoreTests, DownloadStoreIntegrationTests and SeerrCatalogStoreTests.
CollectionStoreTests.uncertainCreateRequiresReview checks that an ambiguous create
cannot be submitted again before fresh readback and explicit acceptance of the
server state. Download metadata read failures preserve files and same-account
snapshots; they never present an unreadable catalog as an empty download library.

| Accepted enhancement | Implementation and coverage |
|---|---|
| Source/version selection | PlaybackRequest across local/remote/Watch/CarPlay/deep-link/Handoff/SharePlay/Mac entry points; PlaybackActionTests, ContentLinkTests, RemoteSessionsTests |
| Semantic track continuation | Account opt-in, semantic-only persisted preferences and conservative same-series matching; Automatic/Off/Explicit intent; PlaybackLifecyclePolicyTests.semanticPreferencePersistence and customTrackRoleIdentity |
| Different-cut progress | Native choice before reusing time; exact-source checkpoints and download selection; DownloadedLibraryTests.sourceSpecificCheckpoints, DownloadStoreIntegrationTests.sourceQualifiedProgressTransfer, OfflineDownloadTests.selectedAudioTranscodeDownload |
| Native previews | Unmodified compatible I-frame HLS, deferred bounded tvOS chapter metadata; actual AVKit scrubber appearance remains a runtime gate |
| Page deduplication | Scoped media identity with raw server offsets; playlist occurrences preserve ordering and duplicates; BrowseRefinementTests |
| Retirement | SavedMediaStore replaces local-playlist CRUD/import; current-format record filtering, draft journal and CloudKit ownership retained; VideoPlaylistTests, MediaReferencePersistenceTests, ServerMediaListsStoreTests |

## Server cleanup boundary

Jellyfin 10.11.11's [PlaybackStopped path](https://github.com/jellyfin/jellyfin/blob/v10.11.11/Emby.Server.Implementations/Session/SessionManager.cs#L1090-L1093)
releases the authenticated session's live-stream mapping. Its [raw Close endpoint](https://github.com/jellyfin/jellyfin/blob/v10.11.11/Jellyfin.Api/Controllers/MediaInfoController.cs#L314-L319)
directly decrements a potentially shared consumer count. Gus therefore never
follows a transmitted live Stop with another raw Close, including a lost Stop
response. Unstarted allocations with known IDs get one bounded explicit close;
failed started-live Stop records cleanup as unconfirmed.

The [allocation path](https://github.com/jellyfin/jellyfin/blob/v10.11.11/Jellyfin.Api/Helpers/MediaInfoHelper.cs#L405-L407)
uses CancellationToken.None. A canceled client request cannot prove that an
allocation with an unknown ID was reclaimed. These reviewed server paths provide
no general fixed reclamation deadline for such an unreported allocation.
Client report order also cannot establish server application order after an
ambiguous timeout. Exactly-once tuner release requires server protocol support
and real tuner fault-injection evidence; Gus makes no such guarantee.

## Acceptance

Build all six platform destinations without warnings; execute shared unit suites
and affected authenticated UI/Watch regressions. Measure 30 cold/warm samples,
10 browse cycles, 30 player open/close cycles and a one-hour playback soak on
available representative hardware. Compare same-device p95 latency with a 10%
regression ceiling, retaining any stricter existing gate. Missing physical
hardware and explicitly deferred Duo checks remain separate open acceptance
items. Completed diagnostics flushes establish durability; abrupt termination
can lose events not yet flushed. Lost responses with unknown server resource IDs
require server cancellation/TTL validation, not a claim of client-side closure.

Keep raw logs, traces, screenshots and result bundles outside Git. Regenerate the
XcodeGen project after file changes. Update ADRs, the roadmap, editable design
handoffs, wiki and affected website claims with the delivered behavior. Protected
main changes require a PR and required checks. Local validation, physical device
acceptance, hosted CI, archives and distribution are separate gates.
