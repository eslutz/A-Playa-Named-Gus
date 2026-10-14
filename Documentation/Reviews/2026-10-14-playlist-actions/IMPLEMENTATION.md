# Playlist and item-detail action redesign

Playlist management lives in More; Add Items remains above the content list. Editing exposes left native drag handles and trailing occurrence-only removal, with Done and disabled playback. Native playlist deletion requires confirmation and preserves media. Item details move watched and list-membership actions into More, add an independent restart, and adapt their secondary controls to narrow layouts. Play/Resume follows the same effective target and server/local position used during preparation. Restart is a presentation intent carried through ItemRef, including macOS; it adds no persisted schema or provider endpoint.

## Initial implementation validation (4471825)

- iPhone authenticated UI suite: **7/7 passed**, no skips or runtime warnings. Independent Jellyfin readbacks verify create/rename, ordering, occurrence removal, watched state, and cancellation/confirmed deletion. Ordered demo movies reach natural playlist completion.
- iPad: **2 detail/accessibility checks and 1 editing check passed**. Existing simulator data remains untouched; isolated profiles were used.
- Unit suites: macOS **444**, iOS **447**, tvOS **445**, visionOS **444** cases passed; no failures, skips, expected failures or runtime warnings.
- iPhone, iPad, macOS, tvOS, visionOS and Watch build lanes passed with zero diagnostics. Static release checks **8/8 passed**.
- Tests cover finished/untouched/missing-cursor and duplicate-occurrence selection, local zero versus server progress, scoped drops, macOS route-value round trips, and failed server/offline preparation preserving checkpoint and watched state.

Native List context menus intercepted handle long presses. Edit mode uses a native scrolling group, with a TV stack where GroupBox is unavailable. Normal browsing keeps its List. Accessible move actions, normal-row contextual moves and the tvOS handle menu remain available.

[Validation summary](evidence/local-validation.json) · [Editing capture](evidence/playlist-editing.png). User guidance was updated locally in the companion wiki and support site, preserving their unrelated edits.

## Review fixes and Apple Silicon policy

The fresh review identified five Important findings. Focused regressions reproduced cancellation during initial seeking overwriting progress; failed playlist restart overwriting a later cursor; non-TV series targeting a container; repeated macOS commands sharing the wrong window/request identity; and a stale watched menu reversing its displayed action. The single fix pass preserves checkpoints until preparation starts playback, keeps playlist restart intent transient through retry, uses the episode resolver on all platforms, separates stable native window values from fresh runtime playback commands, and calls the explicit watched setter captured by the menu label. The native window root uses a stable container around the replaceable player.

Focused macOS validation: **24 tests across 6 suites passed**. The late-seek cancellation covers local and server paths. The stale-menu UI regression independently reproduced Jellyfin Played=false before its source fix; its final UI rerun is pending. Native macOS window acceptance remains unverified: the local host was unresponsive, and repeated fixture launch/activation attempts did not reach playback. Experimental fixture workarounds and the disproven scene-launch change were removed. The maintained native test is retained for a healthy interactive host.

`Config/Shared.xcconfig` now defaults to arm64 and excludes Intel for Debug/Release, including after signing overrides. Physical Watch uses its SDK ARM variants. Validation and CI commands reject explicit Intel requests and unexpected Intel compile/link output; the wrapper stops only its own command process group. Architecture/warning regressions: **11/11 passed**, following RED failures. Screenshot builds also retain the strict warning policy. Final platform validation moves to the existing **13 GitHub-hosted checks**, confirmed to use remote GitHub Actions runners rather than this Mac.

## Remaining gates

The protected-main PR stays draft until final checks and remaining UI acceptance are established. No merged Cloud acceptance is claimed. Historical Cloud Build 18 succeeded but had Apple-generated destination warnings in raw logs; empty issue lists do not establish strict warning-free acceptance. Physical-device, keyboard/remote and VoiceOver acceptance remain separate.

Both other loaded local chats initially confirmed no process ownership; subsequent inventory showed no other active local chat. Task-owned demo/native app processes and OrbStack were stopped. Unused browser/Blender/XR helpers were stopped; shared Codex/Xcode bridges were preserved. Validation used one build at a time with two compiler jobs. The old 4 GB absolute-swap guard was replaced with a guard for more than 1 GB additional swap, less than 25% available memory, or 30 minutes. The first matrix stayed below 2.2 GB during its measured runs; swap later reached 6.4 GB. During review checks, swap decreased and available memory was 39–54%. Per the user's responsiveness request, further local GUI/build loops were stopped.

Rulings: old restored window values require no compatibility decoder because backwards compatibility is excluded. Historical list/cache migration remains outside this feature and is preserved. No provider endpoint, application database schema or migration was introduced.
