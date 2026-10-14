# Playlist and item-detail action redesign

Playlist management lives in More; Add Items remains above the content list. Editing exposes left native drag handles and trailing occurrence-only removal, with Done and disabled playback. Native playlist deletion requires confirmation and preserves media. Item details move watched and list-membership actions into More, add an independent restart, and adapt their secondary controls to narrow layouts. Play/Resume follows the same effective target and server/local position used during preparation. Restart is a presentation intent carried through ItemRef, including macOS; it adds no persisted schema or provider endpoint.

## Local validation

- iPhone authenticated UI suite: **7/7 passed**, no skips or runtime warnings. Independent Jellyfin readbacks verify create/rename, ordering, occurrence removal, watched state, and cancellation/confirmed deletion. Ordered demo movies reach natural playlist completion.
- iPad: **2 detail/accessibility checks and 1 editing check passed**. Existing simulator data remains untouched; isolated profiles were used.
- Unit suites: macOS **444**, iOS **447**, tvOS **445**, visionOS **444** cases passed; no failures, skips, expected failures or runtime warnings.
- iPhone, iPad, macOS, tvOS, visionOS and Watch build lanes passed with zero diagnostics. Static release checks **8/8 passed**.
- Tests cover finished/untouched/missing-cursor and duplicate-occurrence selection, local zero versus server progress, scoped drops, macOS route-value round trips, and failed server/offline preparation preserving checkpoint and watched state.

Native List context menus intercepted handle long presses. Edit mode uses a native scrolling group, with a TV stack where GroupBox is unavailable. Normal browsing keeps its List. Accessible move actions, normal-row contextual moves and the tvOS handle menu remain available.

[Validation summary](evidence/local-validation.json) · [Editing capture](evidence/playlist-editing.png). User guidance was updated locally in the companion wiki and support site, preserving their unrelated edits.

## Remaining gates

Fresh final review, protected-main PR checks, and the merged Xcode Cloud run remain pending. Historical Cloud Build 18 succeeded but had Apple-generated destination warnings in raw logs; empty issue lists do not establish strict warning-free acceptance for this change. Physical-device, hardware keyboard/remote, VoiceOver and native macOS-window acceptance remain separate from the automated coverage above.

After the host restart, validation used one Xcode process/simulator at a time, two compiler jobs, and a 4 GB swap stop guard. Both loaded local chats confirmed no local processes to preserve. Unused browser/Blender/XR helpers and the demo runtime were stopped; shared Codex/Xcode bridges were retained. Peak measured swap during recovery remained below 2.2 GB.
