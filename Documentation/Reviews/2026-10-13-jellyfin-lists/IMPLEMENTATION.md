# Jellyfin-backed playlists and collections

User authorization: replace Gus-owned playlist contents with native Jellyfin playlists and collections, retain Gus resume cursors, Next Up, and offline support, and update PR #21 on the existing feature branch. Unrelated local pipeline/research and companion documentation changes are preserved.

## Implementation contract

- Jellyfin owns playlist/collection identity, membership, names, ordering and permissions. Server entry IDs identify native playlist members; the verified Jellyfin 10.11.11 server deduplicates repeated title IDs.
- Gus keeps local account-scoped snapshots and durable pending edits for offline use; pending edits never overwrite a whole server list from stale data.
- Gus-specific cursors, Next Up intent and genuine activity remain supplemental state; optional private CloudKit synchronization does not create a second native-list authority.
- Older Gus-only playlists remain intact for explicit import. Migration preserves cursor by occurrence and must not blindly retry an ambiguous create/add response.
- Native Apple UI and AVKit remain. Existing video queues continue in explicit order; collections are browsable groups. Audio entries remain visible and use existing audio playback where supported.
- Public/sharing ACL remains governed by Jellyfin; this task exposes list management according to current-user edit permission, without a new public-sharing product.

## Work ledger

- Native provider/domain implementation: implemented; permission, all-page membership and GUID normalization covered by URLProtocol fixtures. Real Jellyfin 10.11.11 probes verify native playlist/BoxSet creation, rename, membership and compact-ID move/remove.
- Account-scoped cache/outbox/migration and supplemental cursor projection: implemented; replay canonicalizes provisional list/entry IDs, removal ancestry persists through unrelated edits/relaunch, and offline create retains known media metadata. Sign-out invalidation blocks further queued/multi-stage requests while saving acknowledged in-flight outcomes to the original account.
- UI/Home/player/navigation integration: implemented, including native list forms, permissions, cached-entry error states, explicit migration/recovery and unresolved resume handling.
- Companion docs and all 51 new localized English keys complete. Wiki commits `6a4276c`/`ba85ebf` and website commits `c3cb7f7`/`2d9e226` are local only; website build/tests (3/3), catalogue and privacy validation passed. Native demo UI acceptance, platform compilation, static checks and scoped review passed; final unit verification and required PR CI are recorded below.
- Physical signed iCloud acceptance remains the separately documented provisioning gate.

## Decisions and review fixes

- Ruling: Jellyfin is the authority for list membership and ordering. Its verified 10.11.11 API permits unique title membership and assigns the media GUID as PlaylistItemId. Repeated native titles are rejected explicitly; legacy Gus records remain intact and imports with repeats are blocked rather than silently collapsed. Cost: old Gus repeated-title queues cannot transfer unchanged. [Versioned playlist manager](https://github.com/jellyfin/jellyfin/blob/v10.11.11/Emby.Server.Implementations/Playlists/PlaylistManager.cs), [versioned controller](https://github.com/jellyfin/jellyfin/blob/v10.11.11/Jellyfin.Api/Controllers/PlaylistsController.cs).
- Ruling: list contents synchronize through the Jellyfin account; optional private CloudKit carries only Gus cursors, saved Next Up intent and genuine activity. Existing legacy CloudKit records are retained for explicit migration. Cost: cursors require signed CloudKit acceptance for cross-device behavior; downloads stay device-local.
- Ruling: native collections are browsable BoxSet groups, not automatic queues. Existing audio playlists remain visible and open the existing audio player. Video queue controls require an all-video list. Cost: mixed lists play entries individually.
- Fresh review found and fixed dependent replay using provisional IDs, removal ancestry lost after acknowledgment/unrelated fetch, and missing full media snapshots in offline create. A second review confirmed all three addressed and identified sign-out invalidation; that follow-up is implemented with three lifecycle regressions.
- Mac integration passed 383 Swift Testing cases in 61 suites (10.290s) including the uniqueness and sign-out guards. The three native duplicate regressions failed five assertions before implementation (14 tests executed); the first attempt with individual Swift Testing selectors executed no cases and is excluded. The real offline playback case and platform matrix results are recorded below.

## Native server evidence

Task-owned Docker demo Jellyfin 10.11.11 was used with rights-cleared movie fixtures. [Entry behavior](evidence/server-occurrences.json) confirms unique title IDs, N-format entry addressing, rename preservation, ordering and removal. [Permissions](evidence/server-permissions.json) confirms readable noneditable shares (all four edit operations403) and allowed/denied BoxSet operations. Temporary probe users and lists were removed. Tokens remained runtime-only.

## UI and final review verification

- Native iPhone UI acceptance: 3/3 passed, zero failures/skips. Ordered two-title playback reached natural completion (224.831s); collection create/add/remove/delete passed with independent BoxSet readback (112.585s); playlist create/rename/relaunch/delete passed with independent native list readback (89.426s). [Ordered members](evidence/native-playlist.png), [collection member](evidence/native-collection.png), [natural completion](evidence/native-completion.png).
- Final whole-branch review confirmed mixed-media context playback bypassed the all-video restriction and supplemental queue/cursor write failures were not visible. A separate cross-device regression showed provisional cursor IDs needed durable canonicalization before CloudKit replication.
- All three behavioral regressions failed as expected before fixes: 27 tests/two suites, eight assertions across canonical cursor (3), mixed queue (3), and failed initial cursor save (2). The same run passed a real generated H.264 AVPlayer offline test from a restarted native cache, preserving one-second cursor position with zero provider requests.
- Keyless static release checks passed after granting compiler-cache access; the sandbox-only attempt's Swift cache permission failure is excluded. No live release/signing operation occurred.

The final fix wave persists proven native cursor aliases into the supplemental store without stamping activity; requires all-video membership in both the context action and playback coordinator; returns durable cursor-write success and stops initial preparation when saving fails; and exposes an independent dismissible saved-state error banner in list/detail/player. Scoped re-review confirmed every finding addressed with no new actionable regression.

## Final source matrix

- macOS: final source, including alias scope and GUID re-add retirement, passed 391 Swift Testing cases in 61 suites (9.411s), with zero failures. Coverage includes delayed-default migration, overlapping lists, replay, sign-out and real offline video playback.
- iPhone and iPad each passed 390 Swift Testing cases in 62 suites before the final migration-field amendment. tvOS test compilation passed after the final amendment, including Swift 6 and the new test fixtures. VisionOS test compilation and watchOS build passed. All-video native UI rerun passed after the mixed/save/migration fixes (145.019s); Final iPhone source passed 394 Swift Testing cases in 62 suites (17.590s), including all alias and migration amendments; zero failures. Compatible tvOS/visionOS 27 runtimes are absent locally; actual runtime test execution is delegated to required PR CI.

A final migration concurrency check found that copying the draft's old field revisions let a delayed newer canonical default reset queued intent. A new 24-test store run failed four assertions before the amendment. Migration now stamps copied values with its current revision while preserving the activity date and retaining the guard for meaningful existing canonical state. This is an amendment to the same final fix wave; The final Mac result above includes this correction; the earlier iPhone/iPad matrix predates it.

The final migration amendment passed fresh scoped re-review with no new actionable findings. No production schema, signing capability, release deployment, or physical two-device acceptance is inferred from the deterministic CloudKit-record merge tests.

A native-identity overlap audit then found a P1: Jellyfin 10.11.11 uses the same media GUID in different lists, while replacement aliases were account-global. Replacing A with B in one playlist could redirect another list's cursor, playback or remove/move target. A regression with overlapping A/B membership is added before the final alias-scope amendment. Aliases must use the canonical list ID as part of their key; old unscoped intermediate-cache aliases must remain untrusted and unknown cursor positions preserved.

The account-global alias regressions executed 26 store cases and failed nine assertions before correction (six overlap cursor/playback/removal, three uncertain interim-cache assertions). All alias reads/writes now use canonical list ID + entry ID. Old unscoped aliases remain preserved, with unknown cursors retained and ambiguous missing mutations requiring review. The full Mac suite passed 390 cases/61 suites after that correction. Scoped review then identified native GUID re-addition within the same list: a replaced GUID must regain its own identity when it becomes a confirmed member again. A replace → offline re-add → reconnect → select/remove regression is added before retiring such stale native aliases.

The re-added-GUID regression executed 27 store cases and failed five assertions before correction. Confirmed `entriesLoaded` membership now retires only qualified source aliases before provisional matching, in both detail fetch and full-list refresh. Fresh scoped review approved the correction with no concrete blockers. Final Mac verification passed as recorded above.

Final static release checks passed all seven lanes: SwiftFormat, release-script formatting, nine bootstrap regressions, shared project and 16 dependency pins, keyless ASC self-test, whitespace and YAML. No signed capability or production schema operation occurred. Required CI must be observed on the pushed commit; prior PR CI success is not evidence for this native-list amendment.

Final iPhone verification passed 394 cases/62 suites (17.590s). The task-owned native demo container was stopped after UI/server evidence was captured. Unrelated simulator and local work remain preserved. See [local matrix](evidence/local-validation.json) and [static checks](evidence/static-checks.json).
