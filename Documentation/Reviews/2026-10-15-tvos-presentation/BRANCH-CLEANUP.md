# Branch consolidation

Requested scope: preserve needed work on protected `main`, then remove all other local and remote branches before the tvOS presentation repair.

Branches were compared by ancestry and final tree equivalence against merged PRs, including #18, #19, #21, #22, #23 and #24. Uncommitted collection work matched the merged implementation; its two unique Build 18 evidence files were preserved in PR #26 alongside the documentation branch's research and release records.

Removed after verification:

- `codex/build16-warning-fixes`
- `codex/build16-warning-free`
- `codex/native-collections-context-menus`
- `codex/os27-remove-compatibility`
- `codex/playlist-item-actions`
- `codex/pr-cloud-release-gates` (also removed remotely)
- `codex/shared-with-you-capabilities`
- `codex/shareplay-native-launch`
- `codex/tvos-warning-free-integration`
- `feature/tvos-cinematic-native`
- `feature/unified-next-up-playlists`
- `fix/stale-media-references`
- `codex/cloud-arm-enforcement` after PR #25 merged as `98d363a4c0a1a993a4b0d24ef8847f4401c78c8d`; the associated worktree was detached and its untracked contents retained.

Final state: only `main` exists locally and on origin. Local main matches origin at `ab233d55bd8d904d1a5ba2d581d9997660f3cffe`.

The remaining work landed through protected pull requests:

- [PR #25](https://github.com/eslutz/A-Playa-Named-Gus/pull/25): Cloud architecture enforcement, merged as `98d363a`. Its required workflow setting was confirmed in the signed-in App Store Connect UI.
- [PR #27](https://github.com/eslutz/A-Playa-Named-Gus/pull/27): concurrent playback remux fix, merged as `497ad09` after all 13 checks passed. The merge tree matched published head `24a7165`; `fix/hevc-hev1-remux` was then removed locally and its deleted remote ref pruned.
- [PR #26](https://github.com/eslutz/A-Playa-Named-Gus/pull/26): preserved records and seek-readiness test correction, merged as `ab233d5` after all 13 checks passed on final head `fbb1e5a`. The merge tree matched that head. `codex/documentation-records` was deleted locally and its deleted remote ref pruned. [Exact merge/check evidence](evidence/preservation-merge.json).

The existing seek-cancellation test failed on iPhone and visionOS because its 1,000-yield loop could finish before asynchronous offline media preparation. The correction uses a bounded ten-second readiness wait; cancellation, progress, watched-state and reporting assertions are unchanged. The affected suite passed five repetitions each on iPhone and visionOS (35 result cases per platform), with zero failures, skips or build diagnostics. The complete final hosted matrix subsequently passed.

PR #26 also corrects the historical Build 17 record: successful Cloud action states and empty issue lists do not establish warning-free raw logs. Strict warning-free acceptance remains unresolved without recorded raw-log inspection. Its review conversation was resolved after the correction was pushed.

A full Git bundle, final incremental integration bundle, working-tree patch, untracked archive and named Git stash preserve the pre-cleanup state and integration commits. File artifacts are under `/tmp/gus-branch-cleanup-20261015/`. Both bundles were verified. Stale remote-tracking refs and one already-missing worktree registration were pruned. The retained worktree is detached at final main; all 5,494 untracked files were preserved by hash.

The final main pull preserved all 27 modified/untracked files byte-for-byte. All 367 tracked build inputs in the final working tree match the independently validated combined candidate. The tvOS presentation repair and its report are a separate follow-up change; they are absent from the merged preservation PRs. Branch inventory above records the completed cleanup before the follow-up PR branch.
