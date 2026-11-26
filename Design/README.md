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
  Show history row actions and a confirmation for clearing history. A genre, studio
  or credit opens titled results in the current stack. Use native Back at each
  level and **Clear Results** on the text search. More uses native disclosure and
  Back. Profile and server discovery use modal actions and system dismissal.
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

## Build 55 spacing and grouping handoff

Use the same viewport, appearance, text size and fixture on each side of a
comparison. Start with the numbered build 55 iPhone screenshots. Update the
paired Light and Dark frames after checking their IDs in the private Sketch
documents. The names below are from the tracked snapshots. The editable
changes and candidate comparison captures are pending.

For app-owned iPhone layouts, group captions 4 pt apart, related elements
8 pt apart, cards and section headings 12 pt from their content, and distinct
sections 24 pt apart. Apply this to browsing, details, editors, onboarding
and app-owned player controls. Keep native form rows, toolbar controls and
AVKit controls at their system sizes. Preserve 44 pt iPhone touch targets and
let text wrap. Use the wider component metrics for TV focus and spatial input.

| Reference in Sketch | What to compare in both appearances |
| --- | --- |
| Shared Library, **Gus / Library / Episode card / Light**, **Gus / Cast card / Light**, **Gus / Cast & Crew / Dark** | Compare one-, two- and three-line episode titles, omitted summaries and long credited names. Start each summary directly under its title. Align cast photos, names and roles. Show the closed season picker, its open checked menu and the accessible layout. |
| iPhone, **Home / Ready** and **Search / Results** | Put square audiobook and tall poster artwork on the same bottom edge. Check spacing and caption alignment on library, Discover and collection/playlist rows. Include an optional progress overlay on the series artwork. |
| iPhone, **Recent Searches**, **Clear Search History** and **Downloads / Browse** | Compare the native search field with the keyboard open and closed, populated and empty filters, recent-query actions and the Downloads overflow menu. Rotate each state and compare the selected destination and content position. |
| iPhone, **Settings / Account and Playback** | Group the avatar and edit badge as a single control. Show both new password fields, the signed-in user's Quick Connect entry and the bounded App Events preview leading to event/report details. Check the theme on real controls in both appearances and Increase Contrast. |
| iPadOS, macOS, tvOS and visionOS device documents | Compare equivalent shelves, detail sections and search at the device's normal reading distance. Check Dynamic Type, narrow windows, focus movement and wide layouts in the running app. For watchOS, verify the compact layout directly in the companion. |

## State patterns and validation

Use representative states with paired appearances, not an exhaustive set of
picker values. Check the relevant scenarios when designing or revising a flow:

| Scenario | Native surface and state to check |
| --- | --- |
| Version choice | Eligible multiversion choices; Start Over, Resume at Timestamp, Cancel; single-source default. |
| Playback choices | Native menu without AVKit overlap; Automatic, Off, explicit/unavailable tracks, Watch and eligible CarPlay choices. |
| Video dismissal | Fullscreen AVKit with system close visible alongside transport and hidden with it. App-owned close remains reachable during preparation and failure. Check portrait, landscape and Picture in Picture return. |
| Live TV Guide | Channels remains the default. Compare the narrow schedule list and wide timeline with pinned channel and time labels, a current airing, a gap, an upcoming airing and a confirmed recording. |
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

## Live TV and fullscreen video handoff

- Start with iPhone **Review / GUS-070 / Live TV** and the iPad **Live TV / Empty** studies. Add paired Light and Dark Guide states for the schedule list, wide timeline, airing details, and recording confirmation. Show a view-only account and an acknowledged request awaiting confirmation.
- Start with iPhone **Video / Native player / Controls visible**. Compare current channel and on-demand playback with controls shown and hidden, plus preparation and failure with a reachable exit. Use candidate AVKit captures for system chrome and retain the origin screen in dismissal captures.
- Check canonical file and frame IDs before editing the live Sketch documents. The tracked reference snapshots remain the starting points for this handoff.

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
