# Behavior and regression guide

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
- Saved-media data, offline draft reconciliation and first verified iCloud
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
| F07 | Truthful independent Live TV loading | Current-account permission plus explicit server membership; independent channel/recording/timer phases | BrowseRefinementTests, JellyfinLiveTVProviderTests (real HTTP JSON, cancellation and combined read budget); qualify M3U and hardware-tuner compatibility separately |
| F08 | Live resource ownership and seekability | Origin-owned allocation; Stop owns started-live release | PlaybackLifecyclePolicyTests; verify started-live Stop and lost replies independently; hardware and unknown-ID limits below |
| F09 | Remote action feedback | Shared ActionOutcome and capability/duplicate/explicit-position guards | RemoteSessionsTests, including explicitPositionConfirmation; physical target acceptance pending |
| F10 | Bounded invalidations and stale-response rejection | One remote refresh plus one follow-up, lease/generation/visibility checks | RemoteSessionsTests |
| F11 | Role-aware artwork and fallback adoption | MediaArtworkRequest, ordered URL candidates and lease-owned OS 27 native image transport; OS 26 native fallback | BrowseRefinementTests; test native reuse and cancellation by lease |
| F12 | Complete shared accessible media identity | Shared Jellyfin and Seerr metadata projections | BrowseRefinementTests; physical VoiceOver acceptance pending |
| F13 | Resume-aligned initial series selection | Initial preferred season/episode, explicit-selection retention | BrowseRefinementTests, UIRemediationTests; exercise native focus in the target fixture |
| F14 | Latest-feed expansion on every main platform | Native Show All routes shared across main platforms | Source/caller coverage; exercise representative Show All interactions |
| F15 | Retained-content refresh | ForegroundLoadPhase plus domain-specific refresh/page errors; strict download metadata errors/retry | LibraryStoreTests, ItemDetailActionTests, SeerrCatalogStoreTests, BrowseRefinementTests, DownloadStoreIntegrationTests.unreadableMetadataLoading |
| F16 | Full-content continuation | Raw-offset paging, ordered queue continuation, full shuffle collection; incomplete advertised collections fail visibly | BrowseRefinementTests, including incompleteCollection; PlaybackLifecyclePolicyTests |
| F17 | Superseding first-page query changes | Immutable query identity and generation cancellation | LibraryStoreTests, BrowseRefinementTests |
| F18 | Reader construction/resource recovery | Public container read observation, inline recovery, bounded chapter selection and generation-scoped Retry | BookReaderLoadingTests; verify missing-resource recovery and semantic-locator restoration |
| F19 | Every PR triggers required CI | Always-triggered workflow, fail-closed classifier, explicit documentation-only success | test-classify-changes.py; all four hosted checks required for each candidate |
| F20 | Measured performance and justified retention/I/O fixes | Non-owning heavy-store lookup, owner/lease cancellation, visibility refresh, serial diagnostics and download workers | NavigationOwnershipTests, including replacementDetailOwnership and seriesLeaseCancellation; DiagnosticsTests, DownloadStoreIntegrationTests; qualify same-simulator Release p95 as applicable |
| F21 | Current platform visual/interaction/accessibility acceptance | Native controls retained; platform interaction checks | Separate visual, interaction, and assistive acceptance |
| F22 | Catalog and native semantic formatting | Shared localized metadata and native duration/count formatting | Catalog validation and BrowseRefinementTests; exercise RTL and largest text |

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
| Native previews | Unmodified compatible I-frame HLS, deferred bounded tvOS chapter metadata; verify native preview and Select per platform; no synthesized JPEG scrubber |
| Page deduplication | Scoped media identity with raw server offsets; playlist occurrences preserve ordering and duplicates; BrowseRefinementTests |
| Saved-media persistence | Account-scoped records, offline draft reconciliation and CloudKit ownership; VideoPlaylistTests, MediaReferencePersistenceTests, ServerMediaListsStoreTests |

## Library intelligence and Discover

Natural Language Search defaults to on for both fields on a compatible device. Use the provisioned-route simulator fixture to verify that Settings → Library Intelligence shows Natural Language Search, Allow Private Cloud Compute, and Show For You in that order. Exercise an interpreted search, a one-query Search by Keyword, and a predictive completion in each field. Switch Natural Language Search off during a submission, check the draft and literal results in each field, and verify the preference across windows and relaunches. Confirm that typing uses no model requests and that Discover only opens titles or people returned by the active Seerr server. Cover restricted profiles, account and server switches during a request, missing metadata, stale results and a failed provider request.

Run `SearchStoreTests`, `SeerrCatalogStoreTests`, `GusLibraryIntelligenceTests` and `IntelligenceEvaluationTests` on local simulators. Cover keyword searches on OS 26, OS 27 and Apple TV. To evaluate the system model on an eligible OS 27 simulator, set the test action environment variable `GUS_EVALUATE_SYSTEM_MODEL=1`, then run the library search, Discover search and ranking evaluations separately. Record the simulated device, runtime, locale, prompt and expected fixture ID. The simulator may report that a model is available while its token generator cannot perform inference. In that case record the error or skip and mark model quality unverified. Evaluate movies, shows, episodes, books, audiobooks, albums, songs and Seerr person lookups. Include multilingual prompts, unsupported constraints and absent titles. Aim for the expected result in the first five for at least 80% of labeled positive prompts. A restricted, cross-account or invented result fails qualification regardless of recall. Measure cold and warm suggestion latency separately.

Verify the For You invitation in one active window per eligible account on each simulator installation. Exercise fresh and upgraded installs, prior explicit choices, deferred eligibility, first-run dismissal, opt-in, account removal, opt-out during ranking, cold start without taste history, and opening a recommended item. Check the Settings path in the invitation and each recommendation reason against the library metadata. Use a provisioned-route fixture on an OS 27 simulator to exercise cloud-only eligibility, first-use consent, denial and revocation, quota exhaustion and loss of connectivity. Verify that approval resumes the pending action once and that declining uses the current query as keywords or leaves For You off. Record live Private Cloud Compute as unverified when the simulator cannot perform an entitled service request. [Signing requirements](AppStore/signing-capabilities.md) · [Issue 50](https://github.com/eslutz/A-Playa-Named-Gus/issues/50)

For iPhone-to-Apple TV For You sync, check that **Set Up Apple TV Sync** appears on the iPhone shelf after picks load. Tapping it or turning on **Sync For You to Apple TV** in Library Intelligence opens the same consent sheet. Verify that dismissal leaves sharing off, approval requires the current iCloud account, and the iPhone publishes picks only after both For You and sharing are enabled. On Apple TV verify the ordered IDs against the signed-in Jellyfin library and apply local content restrictions before displaying results. Exercise separate Apple TV profiles, a different iCloud account, a different Jellyfin server/user, stale snapshots, missing or denied media, foreground refresh, TV opt-out, and producer opt-out or empty picks. Switch the iPhone’s iCloud account and relaunch to verify that prior consent and any pending opt-out apply only to the original iCloud account. Inspect the synced payload for ranked item IDs and freshness only. Verify that reading the shelf issues no model requests and Apple TV search stays keyword-based. Use fixtures for automated coverage. A signed cross-device run is required to confirm that both apps can reach the production private CloudKit container.

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

Use [local validation](local-validation.md) and [pipeline policy](AppStore/pipeline-policy.md)
for scope. Run affected unit and authenticated local cases before claiming coverage.
Use native Apple Silicon for macOS and simulators for the other platforms. For full refinement performance qualification, compare
same-simulator Release p95 (10% regression ceiling or stricter applicable gate),
using 30 cold/warm samples, 10 browse cycles, 30 player open/close cycles and
a one-hour playback soak. Record exact revision, host and inputs outside Git.
This matrix is not required for every change.

Record physical-device and Sketch acceptance separately from local tests.
A completed diagnostics flush establishes durability; termination can lose
unflushed events. A lost response with an unknown server resource ID still needs
server cancellation or TTL validation before claiming cleanup.
