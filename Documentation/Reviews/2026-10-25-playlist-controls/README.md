# Playlist controls and native editing

The playlist detail screen now says **Resume at item N of M** when a saved playback position exists. Play/Resume, compact Restart, and compact Shuffle share one native control row and control size. Add Items remains only at the top of the entries; the separate Next Up action moves to More without changing audio-playlist behavior.

Shuffle creates a transient playback sequence containing every occurrence once, anchored to the chosen first occurrence. It does not reorder the saved playlist. The shuffled intent reaches each player presentation path, including the Mac window request; older encoded item references remain readable. Session order stays fixed, removed occurrences are skipped, and newly added occurrences wait for a new session.

Editing uses native `List` / `ForEach.onMove`, replacing the handle-only item-provider drag and generic drop target. The system lifts the entire row and shifts neighboring rows around its insertion space, without a copy badge. A synchronous draft order accompanies the native move, then the existing account-scoped persisted server edit resolves or restores the authoritative list. tvOS retains remote-friendly move commands. Native touch feedback belongs to the system interaction; its physical feel has not been verified on hardware.

## Validation

- iOS unit suite: 532 passed, no failures/skips/expected failures. Includes shuffle sequencing and backward-compatible navigation intent.
- Final iPhone / iOS 27 and iPad / iOS 26.5 UI flows: one passed on each device, no failures/skips. Both verify consistent secondary-button sizing, one Add Items action, native movement, visible and server-side order, removal after the persisted edit settles, and playlist deletion.
- macOS build and final iOS UI test-product build passed. All accepted logs passed the existing diagnostic gate with zero diagnostics.
- Shared project/scheme/pin verification, formatting and whitespace checks pass. Required GitHub CI remains the merge gate.

[Test summaries and log hashes](validation.json). The initial UI checks exposed outdated assumptions about native reorder labels and asynchronous handle availability; a parent accessibility identifier that overrode the trash button identifier was removed. Failed/incomplete runs are not included in the accepted counts. The 532-test local suite preceded the final UI-only adjustments; the accepted device flows cover the final controls/editor. Physical haptics, live libraries and exhaustive accessibility acceptance remain unverified.

## Captures

- [iPhone controls](captures/iphone-controls.png), [native editor](captures/iphone-editing.png), [whole-row lift](captures/iphone-row-lift.png).
- [iPad controls](captures/ipad-controls.png), [native editor](captures/ipad-editing.png).

The lift frame comes from a diagnostic recording before the accessibility lookup correction; the native movement and visual layout are unchanged in the final passing runs. All imagery uses the isolated rights-cleared demo library. Private server responses and test products remain outside Git.
