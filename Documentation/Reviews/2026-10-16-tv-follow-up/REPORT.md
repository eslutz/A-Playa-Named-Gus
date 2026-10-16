# October 16 TV and download-control follow-up

Source candidate responding to the owner's ten TV findings and subsequent iOS download-button report. Native SwiftUI/AVKit styling and account-scoped Jellyfin behavior remain the basis of the interface.

| Finding | Change |
| --- | --- |
| Action symbols | Shared plus for Add to Next Up and list-with-plus for Add to Playlist. |
| Next Up sizing and progress | Progress is an artwork overlay, leaving equal caption geometry. Poster, episode, backdrop, and Watch resume artwork use bottom overlays. |
| Inset rail clipping | TV viewports extend horizontally; horizontal scroll views allow focus expansion and content to reach the screen edge. |
| Floating account | Account/avatar menu lives in the native collapsing sidebar header. Profile loads authenticated user/image data and saves username and preferred audio/subtitle languages to Jellyfin. Existing account switching remains scoped. |
| Floating filter | Library filters sit beside the scrolling library heading. |
| Watched badges | Written Watched status replaces the unexplained poster checkmark; accessibility values report progress/watched state. |
| Unexplained detail icons | TV common actions have visible captions, consistent symbols, and room for focus expansion. More retains Start from Beginning. |
| Cast clipping | Inset, wrapping captions and focus-safe rail padding. |
| Crowded About | Full-width synopsis and two wide information cards; narrower windows stack them. |
| Duplicate player controls | AVKit owns native track menus. Unmapped/server-only choices use a distinct Server Tracks menu. |
| Playback Info | Renamed Playback Details; readable delivery explanation, negotiated-source codec/resolution/range, and selected tracks. Remote-focusable groups allow scrolling without pretending the rows are buttons. |
| Download shape | All hero download states use the same minimum label height as the neighboring actions on iPhone/iPad, Mac, and Vision Pro. |

## Evidence

- iOS: 455 Swift tests plus three performance tests pass. tvOS: 453 Swift tests plus three performance tests pass, including authenticated profile network regressions.
- Remote UI tests pass for detail actions/About, sidebar/profile save, and opening Playback Details against the isolated local Jellyfin demo.
- All six platform ARM builds and static repository checks pass without warnings; see [validation results](evidence/validation.json).
- iPhone and iPad download geometry assertions pass for both the action and disabled status. iPhone Next Up alignment/context actions and full synopsis regressions pass. iPad portrait/landscape detail smoke tests and synopsis dismissal pass. The dismissal regression waits for the sheet transition; the download regression reveals its row through the enabled Favorite control rather than querying a disabled status for a tap point.
- Vision Pro detail smoke tests pass. Its XCTest geometry check returned a zero-sized download frame, and manual screenshots were blank. The test screen recording visually confirms matching controls; geometry assertions are limited to iOS/macOS. Mac builds and hosted unit tests pass, but local visual validation is incomplete: the unsigned runner did not bootstrap, configured signing lacked iCloud/push capabilities, and the sandboxed local-test host exposed no app window to XCTest. A separate native-app inspection timed out. No Mac visual pass is claimed.
- The owner confirmed the earlier playback repair works on their TV. Physical acceptance of this new UI, VoiceOver, HDR/audio output, and signed Cloud distribution remain separate gates.
- The profile editor retrieves the existing avatar; it does not upload a replacement photo. Server permission failures are surfaced rather than reported as successful saves.

Screenshots: [detail actions](evidence/tv-detail-actions.png), [sidebar](evidence/tv-sidebar.png), [About](evidence/tv-about.png), [Playback Details](evidence/tv-playback-details.png). Download evidence: [iPhone](evidence/iphone-download.png), [iPad](evidence/ipad-download.png), [Vision Pro recording frame](evidence/vision-download.png). All images use the rights-cleared local demo, not the owner's private media/account.
