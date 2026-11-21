# Gus design rules and patterns

Sketch is the editable design workspace. Use the private **Gus** folder for the
canonical working documents and the files here as tracked design snapshots.
Keep this README as the canonical repo guide for design sources, rules, and
patterns. Check the actual canonical document before claiming its latest content
or coverage. Archived Figma and older Sketch work is reference only; don't
reimport legacy screen layouts or regenerate the archives.

## Editable sources

Keep one `Gus-<device>.sketch` document per device with Light and Dark in the
same file. Reusable components for both appearances belong in
`Gus-Shared-Library.sketch`. Use existing Screens, States, and Components pages
where present; reuse frame/component IDs and design system symbols.

| Tracked snapshot | What to consult |
| --- | --- |
| [Gus-iPhone.sketch](Gus-iPhone.sketch) | iPhone screens, states, components, and detail/search studies. |
| [Gus-iPadOS.sketch](Gus-iPadOS.sketch) | iPad screens, states, and compact search; keep matched Light/Dark layouts adjacent. |
| [Gus-tvOS.sketch](Gus-tvOS.sketch) | TV screens, states, and components, including connection/profile and theme editor references. |
| [Gus-macOS.sketch](Gus-macOS.sketch) | Detail/search and editable artwork studies for wide and narrow windows. |
| [Gus-visionOS.sketch](Gus-visionOS.sketch) | Editable reference studies; [coverage and limitations](visionos-coverage.json) describe the saved snapshot, not live or runtime acceptance. |
| [Gus-Shared-Library.sketch](Gus-Shared-Library.sketch) | Linked sources, paired appearances, and shared colors/styles. |

Find a study in the canonical Sketch document by document, page, and frame
name. Verify the current frame or component ID before editing; do not invent
IDs or assume the tracked snapshot matches the live document.

## Native design and appearance

- Follow the [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
  and [Apple Design Resources](https://developer.apple.com/design/resources/).
  Use linked official Apple components and native system controls; never describe
  flat or blur mockups as verified native Liquid Glass fidelity.
- Keep Light/Dark layout and nested geometry consistent. Preserve existing text,
  visibility, and override paths. Review Dark text, surface, accent and vibrancy
  independently. Editable paired sources such as `References / iPad / Dark`
  and `References / Shared / Dark` don't automatically follow macOS appearance.
- Use Sketch MCP for editable mutations. To refresh tracked snapshots, copy the
  saved canonical files byte for byte. Preserve the shared library document
  identity so existing device documents keep their live component links.

## Detail, search, and navigation

- In movie details, extend backdrop artwork behind navigation controls and fade
  into the summary. In book and album details, keep the whole cover visible.
  Align primary and secondary actions on a shared leading edge; use consistent
  gaps. Keep Genres, Studios, and Cast & Crew above About and Recommendations.
- Match search to each platform: compact iPhone/iPad use a Search tab; wide iPad
  and Mac use a sidebar; Apple TV and Vision Pro follow native tab layouts.
  Show history row actions and a confirmation for clearing history. Related
  results identify their subject and distinguish Back to Detail from Close Results.
  Verify paging, focus restoration, and account isolation separately in the app.
- On iPad, keep ordinary details in the selected section's navigation stack.
  Reader, Photos, and Now Playing use the window-level session presentation.
  Preserve context when resizing. See [iPad capabilities](../Documentation/ipad-capabilities.md)
  for behavior and platform boundaries.

## Stable browsing, search, and Settings handoff

The editable Sketch updates for [issue #78](https://github.com/eslutz/A-Playa-Named-Gus/issues/78) are pending. The following frame names were checked against the tracked snapshots. Open the corresponding documents in the private Gus folder and confirm the current frames before editing.

| Study | Changes for the paired Light and Dark frames |
| --- | --- |
| Home and library grids | Start with iPhone **Home / Ready** and iPad **Home / Ready** in portrait and landscape. Show a warm return with the previous cards visible. For a cold return, keep the same headings, card aspect ratios and caption space using blank artwork and text bars. Include a partially loaded Home with just one shelf still waiting. Show separate series cards under For You and keep episode numbers on Next Up. |
| Library search | Use the existing compact search and wide sidebar results layouts. Show the submitted “something scary with robots” query with **Scary tone** and **Robots** in Applied Filters. Pair a result supported by both concepts with an empty state offering **Horror**, **Robot stories**, and **Search by Keyword**. |
| Settings | Use iPhone **Settings / Account and Playback**, the **Middle content / Light** and **Middle / Dark** states, and iPad **Settings / Playback Appearance / Landscape**. The **Library Intelligence** link has a leading `sparkles` symbol and a native disclosure indicator. Its destination uses standard form spacing and shows the available controls with their footers. The **Natural Language Search** footer reads “Search in your own words with help from Apple’s models.” |
| iCloud Sync | When available, place **Sync For You to Apple TV** (**Show Synced For You** on Apple TV) first. Place **Sync Gus Resume and Next Up** below it, with its explanation and sync status underneath. Show the native separator between the two settings. Group each setting’s help and status in its own row. |
| Playback | Update the existing **Streaming quality menu** states. Place each info button immediately after the setting name, with the picker or switch at the trailing edge. On iPhone and iPad, match the native picker indicator used by **Appearance** and **Theme**. Capture the compact selected value, the open menu with full quality descriptions, and the larger-text layout. On Apple TV retain the individually focusable help rows. |

Use the user-supplied Home, search and Settings screenshots as before-state references. For fresh candidate captures, use the behaviors exercised by `testPlaybackHelpExplainsEachSettingWithoutChangingIt`, `testCloudForYouInvitationAndLibraryIntelligenceSettings`, and `testForYouAppleTVSyncConsentRequiresAnExplicitAction`. Use the blank placeholder reference for card geometry and native platform fills for each appearance.

## State patterns and validation

Use representative states with paired appearances, not an exhaustive set of
picker values. Check the relevant scenarios when designing or revising a flow:

| Scenario | Native surface and state to check |
| --- | --- |
| Version choice | Eligible multiversion choices; Start Over, Resume at Timestamp, Cancel; single-source default. |
| Playback choices | Native menu without AVKit overlap; Automatic, Off, explicit/unavailable tracks, Watch and eligible CarPlay choices. |
| Video dismissal | Native Close above AVKit in preparation, failure and ready states; portrait and landscape safe areas. |
| Foreground recovery | Initial failure, retained-content refresh failure, page retry and accepted/uncertain/confirmed cancellation. |
| Unconfirmed edits | Collection server-state review; partial or canceled transmitted profile save; reload with preserved draft. |
| Download recovery | Unreadable metadata retry, pause/resume storage failure, recorded version identity and converted-file track limits. |
| Audio collection | Ordered continuation, complete Shuffle progress/cancel/retry, disabled unavailable transport. |
| Browsing context | Resume-aligned seasons/episodes, latest-feed expansion, Back/resize/focus restoration. |
| Artwork and semantics | Role-specific missing/stale artwork, stable bounds, full episode identity and status, larger text and RTL. |
| Reader recovery | Navigator construction failure, resource retry or continue reading, last valid locator retained. |
| Native previews | Compatible HLS scrubber preview, tvOS chapters with deferred/missing art, unsupported JPEG trickplay. |

Capture matching states from the candidate build. Record source/build, OS,
device/window, appearance, and fixture provenance. Check VoiceOver, focus,
Crown/keyboard/gaze interaction, contrast, and comfort on the appropriate
platform; visual studies, simulator screenshots, and physical acceptance are
distinct. Keep captures and recovery artifacts outside Git. See the
[behavior and regression guide](../Documentation/behavior-and-regression-guide.md) for current
behavior and [review comparisons](../Documentation/Reviews/README.md) for the
local comparison workflow.

## tvOS design validation

The Sketch document represents glass, focus transitions, and keyboards
statically. Compare fresh design renders to settled app states and verify native
focus, loading, errors, empty content, and dismissal separately. Refresh exports
and inspect symbol and image links before treating a missing layer as a defect.
Top Shelf artwork is not evidence of live dynamic cards. Use
[isolated TV validation](../Documentation/tvos-capabilities.md#isolated-validation)
for the test fixture and keep captures and manifests outside the checkout.

For targeted supplementary-screen and toolbar regressions, use
`testTVRemediationSupplementaryScreens` and `testTVToolbarViewModes` in the
TV authenticated UI suite. Verify picker focus and populated options rather
than treating a static layout or simulator render as interaction acceptance.
