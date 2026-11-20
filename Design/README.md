# Editable Sketch designs

Keep one document per device directly in this folder: `Gus-<device>.sketch`.
Light and Dark appearances belong inside that document. Reusable components for
both appearances live in `Gus-Shared-Library.sketch`.

- `Gus-iPhone.sketch`: current iPhone Screens, States, and Components, including
  both appearances. The older separate appearance files are archived locally.
- `Gus-tvOS.sketch`: editable TV Screens, States and Components, including the
  connection/profile revisions and native-reference theme/hex editor studies.
  Canonical private cloud version: [vwZAA3](https://www.sketch.com/s/2711b90a-32b4-4f8d-a0ca-725c75e9e207/v/vwZAA3).
  TV artwork slots remain placeholders. Simulator comparisons and interaction
  coverage are reviewed separately from these design studies.
- `Gus-iPadOS.sketch`: 95 Screens and 62 States in each appearance. Light/Dark
  partners are adjacent in a compact canvas grid; their internal layouts match.
- `Gus-macOS.sketch` is a local detail and search reference. The eight frames
  on Screens show a backdrop movie and a full book cover in 1040- and 500-point windows,
  each in Light and Dark. The controls link to the Apple macOS 27 UI Kit and
  the movie artwork links to the Gus shared library. The book cover has an
  editable local source on the Artwork page. Native Mac visual acceptance is pending.
- `Gus-Shared-Library.sketch`: existing Light/Dark components plus editable paired
  Dark sources and their color/style dependencies. iPad Dark instances link to
  this library rather than flattened images.

- `Gus-visionOS.sketch`: representative editable snapshot with 32 Screens, 10
  States and six local product symbols, plus linked Apple visionOS controls.
  Includes one Settings Light/Dark pair and a large-text form; other appearance
  pairs remain incomplete. [Coverage and limitations](visionos-coverage.json)
  maps the saved frames. Backdrop glass is approximate. The captured app baseline
  has no verified source commit, and parity with current main remains unverified.
  Cinema, Live TV, expanded playback, resizing and physical-device acceptance
  need separate validation.

`appearance-coverage.json` maps the original iPad Screens and States by persistent
layer ID. Components holds their reusable sources.

## Detail and global search

Each device document contains a **Detail and Global Search** page with eight
editable studies in Light and Dark. Movie Detail places the backdrop behind the
navigation controls. Book and Album Detail retain the whole cover. The primary
action and each secondary row share a leading edge. Detail Sections places
Genres, Studios, and Cast & Crew above About and the final Recommended section.

Recent Searches shows typed searches and related genre, studio, and person
entries. The app retains the latest 20 entries per account. Remove from History
shows an individual row's menu. Clear Search History shows the confirmation.
Related Results displays the selected name and type with separate Back to Detail
and Close Results actions. iPhone uses a Search tab, wide iPad and Mac use a
sidebar, and Apple TV and Vision Pro use their platform tab layouts. The iPad
**Compact Global Search** page pairs Recent Searches and Related Results in
500-point Light and Dark windows with a Search tab.

[Detail and search frame IDs](detail-search-coverage.json) identifies these
local design references. The named Sketch exports are visual studies. Use
runtime captures to check paging, focus restoration, and account isolation.

## Appearance maintenance

The library retains its original linked Apple resources. The paired Dark sources
preserve the existing controls' nested geometry, text, visibility, and override
paths. They use Dark text/surface/accent values and Dark vibrancy blending.
`References / iPad / Dark` and `References / Shared / Dark` contain editable
supporting sources; existing Dark variants remain available for compatibility.
When updating a source control, update and review its paired Dark source too;
these local appearance derivatives do not automatically switch with macOS's
appearance setting.

Refresh tracked snapshots by copying the canonical saved files byte for byte.
Sketch's copy-save operation can assign a new document identity; retain the
shared library's identity so the device documents keep their component links.

The delivered files were opened and saved by Sketch, checked for symbol/image
references and appearance coverage, and reviewed using representative native PNG
exports. Design completion does not establish runtime or physical-device
acceptance. Review images and recovery checkpoints stay outside Git.

## Refinement handoff reconciliation

The tracked iPhone, iPad, Apple TV and Vision Pro files include updated artwork and action layouts. The scenarios below also cover earlier refinements that still need reconciliation with the private Sketch workspace. Sketch MCP is required for editable mutations;
archive inspection, source review and simulator images do not establish saved-design
fidelity.

Use the existing Screens, States and Components pages and paired appearances. Map
these representative scenarios to persistent frame/component IDs after inspecting
the canonical document; do not invent frame IDs or duplicate every picker value.

| Scenario | Native surface and state to reconcile |
|---|---|
| Detail version choice | Eligible multiversion menu; Start Over / Resume at Timestamp / Cancel; single-source default |
| Playback choices | Native player menu without AVKit overlap; Automatic / Off / explicit or unavailable track; Watch and eligible CarPlay choices |
| Video dismissal | iOS/iPadOS native Close above AVKit in preparation, failure and ready states, with or without Playback Options; portrait and landscape safe areas |
| Foreground recovery | Initial failure, retained-content refresh failure, page retry, recording cancellation accepted/uncertain/confirmed |
| Unconfirmed edits | Collection server-state review; partial profile save and canceled transmitted save requiring reload; preserved draft |
| Download recovery | Unreadable metadata retry; storage failure during pause/resume; recorded version identity and converted-file track limits |
| Audio collection | Ordered queue continuation; complete Shuffle collection progress/cancel/retry; disabled unavailable transport |
| Browsing context | Resume-aligned season/episode; latest-feed expansion; Back/resize/focus restoration |
| Artwork and semantics | Role-specific missing/stale artwork, unchanged bounds, full episode identity/status, larger text and RTL |
| Responsive details | Retain focus through resizing. Keep the upper artwork clear, fade into the summary, and use a fixed gap between secondary actions. |
| Reader recovery | Navigator construction failure; resource retry/keep reading; retained last valid locator |
| Native previews | Compatible HLS scrubber preview; tvOS chapter navigation with deferred or missing artwork; unsupported JPEG trickplay |

Capture matching current-build states before proposing visual changes. Record build,
OS, device/window, appearance and fixture provenance alongside native frame exports.
Physical focus, VoiceOver/Crown/keyboard/gaze interaction, contrast and comfort remain
separate acceptance checks. The implementation ledger is in
[app-wide refinement](../Documentation/app-wide-refinement.md).
