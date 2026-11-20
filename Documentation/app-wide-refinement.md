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
  Video hosts attach their native surface when the player becomes available,
  retain that surface through readiness, and keep preparation controls above it.
  Native transport remains unavailable until preparation succeeds. Rendering is
  observed independently from the player's advancing clock.
  tvOS explicitly fills the presentation viewport during preparation and native playback;
  the native UI regression checks its bounds before opening Playback Details.
- tvOS dismissal and navigation returns use native focus scopes and an immutable
  request for the saved target. A non-nil request moves the target's native
  FocusState once, or acknowledges an already focused binding without a write;
  default preferences govern initial focus. Native fallback does
  not reissue the request, and the target's SwiftUI focus binding acknowledges
  it without another focus write or task scheduling. Native remote interaction
  separately verifies where focus actually lands.
  Pushed destinations own their scope explicitly, including direct Show All and
  Discover detail routes; the navigation root's custom namespace does not reach
  every pushed page.
  Playlist and collection tasks return to More; version choices return to Version
  in the visible detail's context, including series headers that play an episode.
  Horizontal TV rails use their full scroll viewport as the native focus section,
  keeping short rows reachable from trailing header controls without changing card layout.
  The themed TV app root removes theme tint while retaining native TabView row styles.
  Page content and the independent native-hosted queue use the system's untinted
  bordered focus treatment. Hero foreground and theme tint must not override
  focused labels or platters.
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
  Adaptive stacks measure the parent's available width with explicit frame bounds,
  allowing horizontal content to return to vertical when its pane narrows.
  Secondary detail buttons and native menu triggers share the same label sizing,
  minimum control bounds and system button treatment across main platforms.
  A lower-edge fade keeps detail titles and controls readable. Artwork extends behind
  the native top controls. Secondary controls align with the primary action’s leading edge.
- visionOS root navigation respects the native eight-tab limit. Search always has a tab. Up to seven content
  sections appear directly, or six in resolved order alongside More when needed. Overflow preserves section selection and navigation histories.
  If More becomes unnecessary while selected,
  the root returns to the first direct section without resetting those histories.
- Version changes ask whether to start over or resume at the saved timestamp.
  A retained start choice expires after matching actual playback checkpoints it;
  canceled preparation preserves it. Detail, Watch and CarPlay derive the next
  request from the selected source's checkpoint and duration. Active players keep
  their original request identity. Account retirement and progress deletion
  invalidate pending choices without changing the saved checkpoint format.
  Watch remote requests expose accepted versus confirmed readback; confirmation
  can consume the matching command choice without claiming local playback.
  Watch item actions use one item-driven native sheet whose immutable request,
  destination and start-choice identity are captured together at the tap.
  Track memory is opt-in per device/account, including a native Watch setting, and
  carries semantic preferences within a
  series. Persisted preferences contain no source-local indexes; missing or ambiguous
  named tracks fall back to defaults with a notice.
  Online and downloaded episodes share the effective-track policy; explicit choices
  override memory without changing Automatic intent. Original downloads advertise
  embedded tracks only, so missing external sidecars use defaults with feedback.
- Downloaded playback projects its recorded source rather than the item's primary
  version. Unknown source metadata remains unknown; converted files do not advertise
  the original source's unverified track catalog. Native transfer observations update
  only the current incomplete record under the same lock as finalization, so stale
  callbacks cannot overwrite completion or recreate deleted records. Completion
  ownership is captured before worker reads and invalidated by cancellation;
  completed records retain their conversion activity and current remote reference.
- Compatible I-frame HLS remains intact for AVKit's platform-provided previews;
  tvOS chapter artwork uses separate native navigation metadata. Actual scrubber
  thumbnail appearance requires platform-specific runtime verification. Jellyfin
  JPEG image playlists do not imply AVKit scrubber support; no custom scrubber.
- EPUB container reads report missing or unreadable content through Readium's public
  extension points. A coalesced inline notice keeps reading available; Retry opens a
  new native navigator from the saved locator. Chapter selection checks its target
  before leaving the current page and has one 30-second readiness deadline.
  Close and account retirement reject late callbacks. Canceling a task does not
  prove immediate release of a suspended Readium operation.
- Retired readers/imports/CRUD are removed without a migration bridge. Current
  format data, current offline draft reconciliation and first verified iCloud
  identity ownership remain supported.
  Obsolete hero no-ops, unused presentation adapters and the superseded tab-count
  policy are removed along with their callers and obsolete assertions.

## Finding ledger

| Finding | Deliverable | Implementation | Verification |
|---|---|---|---|
| F01 | Identity-bound activation and recoverable expiry | AppModel, SessionLease, SessionAuthentication | SessionAuthenticationTests, AppModelSessionTests; physical account acceptance pending |
| F02 | Distinct forbidden/unauthorized outcomes | Typed Get status adapter; canonical auth probe for ambiguous delete policy | SessionAuthenticationTests, GusErrorTests |
| F03 | Ordered shared playback reports | Session-owned PlaybackReportQueue and immutable snapshots | PlaybackLifecyclePolicyTests; response-loss limits below |
| F04 | Truthful playback lifecycle and finalization | Shared native preparation; audio/video/Watch finalization, actual-playing observations and persistent iOS/iPadOS video dismissal | PlaybackLifecyclePolicyTests, TVPlaybackLifecycleTests, GusAuthenticatedUITests.testReadyVideoCloseReturnsToDetail; physical output pending |
| F05 | One resolution deadline/retry owner | PlaybackDeadline and StreamURLBuilder | PlaybackLifecyclePolicyTests, StreamURLBuilderTests |
| F06 | Watch credential and endpoint rotation | Central AppModel installation and lease invalidation | AppModelSessionTests; paired Watch acceptance pending |
| F07 | Truthful independent Live TV loading | Current-account permission plus explicit server membership; independent channel/recording/timer phases | BrowseRefinementTests, JellyfinLiveTVProviderTests (real HTTP JSON, cancellation and combined read budget); scoped local M3U/native evidence recorded in the external revision manifest; hardware-tuner compatibility separate |
| F08 | Live resource ownership and seekability | Origin-owned allocation; Stop owns started-live release | PlaybackLifecyclePolicyTests; local M3U Stop/lost-reply evidence recorded externally; hardware and unknown-ID limits below |
| F09 | Remote action feedback | Shared ActionOutcome and capability/duplicate/explicit-position guards | RemoteSessionsTests, including explicitPositionConfirmation; physical target acceptance pending |
| F10 | Bounded invalidations and stale-response rejection | One remote refresh plus one follow-up, lease/generation/visibility checks | RemoteSessionsTests |
| F11 | Role-aware artwork and fallback adoption | MediaArtworkRequest, ordered URL candidates and lease-owned OS 27 native image transport; OS 26 native fallback | BrowseRefinementTests; scoped native per-lease reuse/cancellation evidence recorded externally |
| F12 | Complete shared accessible media identity | Shared Jellyfin and Seerr metadata projections | BrowseRefinementTests; physical VoiceOver acceptance pending |
| F13 | Resume-aligned initial series selection | Initial preferred season/episode, explicit-selection retention | BrowseRefinementTests, UIRemediationTests; scoped TV focus observations recorded externally |
| F14 | Latest-feed expansion on every main platform | Native Show All routes shared across main platforms | Source/caller coverage; representative interaction evidence and applicability limits recorded in the external revision manifest |
| F15 | Retained-content refresh | ForegroundLoadPhase plus domain-specific refresh/page errors; strict download metadata errors/retry | LibraryStoreTests, ItemDetailActionTests, SeerrCatalogStoreTests, BrowseRefinementTests, DownloadStoreIntegrationTests.unreadableMetadataLoading |
| F16 | Full-content continuation | Raw-offset paging, ordered queue continuation, full shuffle collection; incomplete advertised collections fail visibly | BrowseRefinementTests, including incompleteCollection; PlaybackLifecyclePolicyTests |
| F17 | Superseding first-page query changes | Immutable query identity and generation cancellation | LibraryStoreTests, BrowseRefinementTests |
| F18 | Reader construction/resource recovery | Public container read observation, inline recovery, bounded chapter selection and generation-scoped Retry | BookReaderLoadingTests; scoped native missing-resource/Retry and semantic-locator restoration evidence recorded externally |
| F19 | Every PR triggers required CI | Always-triggered workflow, fail-closed classifier, explicit documentation-only success | test-classify-changes.py; all five hosted checks required for each candidate |
| F20 | Measured performance and justified retention/I/O fixes | Non-owning heavy-store lookup, owner/lease cancellation, visibility refresh, serial diagnostics and download workers | NavigationOwnershipTests, including replacementDetailOwnership and seriesLeaseCancellation; DiagnosticsTests, DownloadStoreIntegrationTests; local same-simulator Release p95 gate accepted, with exact revision, one-pair scope and host-condition limits recorded externally |
| F21 | Current platform visual/interaction/accessibility acceptance | Native controls retained; platform interaction checks | Platform-scoped evidence recorded externally; owner deferred Sketch reconciliation outside this release scope |
| F22 | Catalog and native semantic formatting | Shared localized metadata and native duration/count formatting | Catalog validation and BrowseRefinementTests; targeted RTL/largest-text observations recorded externally |

The named tests are coverage pointers, not a claim that a particular revision has
passed. Exact revision, destinations, results and runtime artifacts belong in the
external validation manifest.

The action audit also covers ItemDetailActionTests, CollectionStoreTests,
UserProfileStoreTests, DownloadStoreIntegrationTests and SeerrCatalogStoreTests.
CollectionStoreTests.uncertainCreateRequiresReview checks that an ambiguous create
cannot be submitted again before fresh readback and explicit acceptance of the
server state. Download metadata read failures preserve files and same-account
snapshots; they never present an unreadable catalog as an empty download library.
Storage usage and active/paused counts show Unavailable while metadata is unreadable,
rather than treating retained or missing records as a current inventory.

| Accepted enhancement | Implementation and coverage |
|---|---|
| Source/version selection | PlaybackRequest across local/remote/Watch/CarPlay/deep-link/Handoff/SharePlay/Mac entry points; PlaybackActionTests, ContentLinkTests, RemoteSessionsTests |
| Semantic track continuation | Account opt-in, semantic-only persisted preferences and conservative same-series matching; Automatic/Off/Explicit intent; PlaybackLifecyclePolicyTests.semanticPreferencePersistence and customTrackRoleIdentity |
| Different-cut progress | Native choice before reusing time; exact-source checkpoints and download selection; DownloadedLibraryTests.sourceSpecificCheckpoints, DownloadStoreIntegrationTests.sourceQualifiedProgressTransfer, OfflineDownloadTests.selectedAudioTranscodeDownload |
| Native previews | Unmodified compatible I-frame HLS, deferred bounded tvOS chapter metadata; platform-scoped native preview/Select observations recorded externally; no synthesized JPEG scrubber |
| Page deduplication | Scoped media identity with raw server offsets; playlist occurrences preserve ordering and duplicates; BrowseRefinementTests |
| Retirement | SavedMediaStore replaces local-playlist CRUD/import; current-format record filtering, draft journal and CloudKit ownership retained; VideoPlaylistTests, MediaReferencePersistenceTests, ServerMediaListsStoreTests |

## Server cleanup boundary

Video playback prefers native MP4 direct delivery and fMP4 HLS. A secondary
H.264 TS HLS profile supports Live TV compatibility mode:
[Jellyfin 10.11.11 filters those profiles to TS containers](https://github.com/jellyfin/jellyfin/blob/v10.11.11/MediaBrowser.Model/Dlna/StreamBuilder.cs#L852-L855).
This advertises segmented HLS without disabling compatible file direct streaming
or retrying allocating PlaybackInfo requests.

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

Build all six platform destinations without warnings. For this refinement run,
the user's simulator-only constraint limits runtime validation to simulators:
shared unit suites, affected authenticated UI/Watch regressions, 30 cold/warm
samples, 10 browse cycles, 30 player open/close cycles and a one-hour playback
soak. Compare same-simulator p95 latency with a 10% regression ceiling, retaining
any stricter existing gate. Physical acceptance, including the previously
deferred Duo checks, is excluded from this run and remains unverified. Local native
macOS runtime testing is also held under that constraint. The user approved an
exception for the required hosted macOS CI unit job; that exception does not
authorize physical-device or local native macOS runtime tests. Completed
diagnostics flushes establish durability; abrupt termination
can lose events not yet flushed. Lost responses with unknown server resource IDs
require server cancellation/TTL validation, not a claim of client-side closure.

Sketch-specific comparison and handoff work is deferred by the owner and is not
a gate for the Swiftfin-pattern release. Existing platform interaction evidence
retains its original scope; deferral does not establish visual acceptance.

Keep raw logs, traces, screenshots and result bundles outside Git. Regenerate the
XcodeGen project after file changes. Update ADRs, the roadmap,
wiki and affected website claims with the delivered behavior. Protected
main changes require a PR and required checks. Local validation, physical device
acceptance, hosted CI, archives and distribution are separate gates.
