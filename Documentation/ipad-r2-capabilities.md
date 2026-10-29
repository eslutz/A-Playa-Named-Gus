# iPad R2 client and service boundaries

The iPad redesign uses the existing media-provider sessions, Seerr client, session navigation and playback coordinators. It introduces no new server service or runtime dependency. The external comparison report owns the scenario checklist and runtime evidence; this document records durable implementation boundaries.

## Presentation and state ownership

- The regular-width sidebar owns the trailing visibility control and a dedicated global Search destination. Each section retains its navigation path; query, per-library layout, photo-album selection and scroll state belong to the signed-in session. Compact windows use the existing native tab navigation. Accessibility text defaults to the detail pane with a native Show Sidebar action available.
- Ordinary media details push into the selected section, including external item links. Photos, Reader and Now Playing use the stable session cover above adaptive layout changes. Closing prepared audio returns to the persistent accessory without stopping playback.
- Music separates album browsing and artists when width and text size permit. Album detail separates artwork/actions from tracks; media detail separates artwork/actions from synopsis. Narrow windows and accessibility text use the stacked layout.
- Request creation, profile editing, chapter selection and queue selection remain focused sheets. From a confirmed iPad request, View My Requests leaves the task sheet and pushes history in the main content stack.
- Common toolbar actions use SF Symbols with semantic labels. Save, Cancel, destructive choices and recovery actions retain explicit text. Native volume/output controls retain system behavior; simulator output limitations do not justify a simulated volume slider.
- The profile sheet is hosted above adaptive container replacement so its draft survives layout changes. Saves expose native progress; failed saves keep the editor draft. A requested reload confirms before replacing changed fields. Reader opening failures expose retry without resetting a successfully opened publication.

## Comparison workflow

Keep all evidence outside the repository. After the single final scenario pass, export result-bundle attachments with `xcrun xcresulttool export attachments`. Run `Scripts/update-ipad-comparison.py --report-root <external-review-root> --attachments <export-directory> ...` to append implementation images. The tool requires all indexed scenarios by default, keeps original before/Sketch files intact, and records screenshot hashes, dimensions, test identifiers and simulator provenance. Use `--dry-run` to inspect coverage; `--allow-partial` is only for an explicitly incomplete report.

Captures are not behavioral acceptance. The external implementation checklist separately records focused interaction tests, supporting-state coverage, visual review, platform builds and remaining physical/minimum-OS checks. Fixture titles and colors may differ from synthetic Sketch examples; presentation and behavior are the acceptance targets.

| Designed behavior | Existing capability | Backend work |
| --- | --- | --- |
| Sidebar, Search destination, adaptive grids and editor presentation | SwiftUI and client-owned navigation state | None |
| Library filtering, paging, media detail, artwork and global search | Media-provider queries and cached feature stores | None for the supported Jellyfin operations; respect provider capability flags |
| Playlist/collection creation, membership and ordering | Existing server-media-list clients and scoped mutation queues | None for supported server capabilities; permission and unsupported-operation responses remain explicit |
| Seerr setup, catalog/search, requests, history and cancellation | Existing Seerr authentication, browse/search, request and user-history endpoints | None for the designed supported operations; server configuration and user permissions still determine availability |
| Audio queue, transport, volume, output and persistent accessory | AudioPlaybackCoordinator, AudioPlayerStore, AVFoundation and MediaPlayer | None beyond existing media streaming/progress APIs |
| EPUB chapters, local reading position and photo slideshow | Readium, scoped local progress and native client presentation | None; synchronize book progress only when the provider advertises support |
| Profile preferences, themes, custom colors and navigation order | Existing profile client plus account/device-scoped client preferences | None |

## Guarantees the client cannot manufacture

An operation whose response is lost is not confirmed successful. Retain the existing mutation journal and reconcile with server readback before permitting a retry that could duplicate a write. A stronger exactly-once guarantee would require a server-supported idempotency key and durable operation-status lookup; it is not implied by the redesign.

Client mutation queues serialize this client's changes, not independent external clients. Guaranteed atomic conflict detection for list edits would require a server revision/precondition contract. Where that guarantee is unavailable, refresh and reconcile the server list rather than claiming a transaction or silently overwriting an unknown result.

No mandatory new backend endpoint has been identified for the designed core flows. Any concrete unsupported flow discovered during scenario validation must be recorded with its missing operation, permissions, required server contract and visible fallback. Do not add speculative backend functionality or replace native controls with simulated results.
