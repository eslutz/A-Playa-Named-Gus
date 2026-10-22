# Gus × Seerr — proposed experience

Design revision 2 · October 20, 2026 · source checkpoint `d715c05`.

This is a proposal for the next implementation, extending the existing integration. It is not a claim that the expanded features work today. Review the visuals before changing app code. The existing `Gus/**/05 Discover.fig` files now contain both references: App Screens preserves the current app, and Discover Proposal contains the expanded Seerr design. Proposal resources are grouped within Components and Guide & Coverage.

## Design locations

Review [the shared preview in Discover proposal mode](Exports/Preview/Preview.html#discover-proposal), or open one of the existing Discover files below and select **Discover Proposal**. The current app remains on **App Screens**. There is no separate Seerr master/review file.

| Layout / appearance | Editable file | Proposed artboards |
|---|---|---:|
| iPhone / Dark | [05 Discover.fig](Gus/iPhone/Dark/05%20Discover.fig) | 51 |
| iPhone / Light | [05 Discover.fig](Gus/iPhone/Light/05%20Discover.fig) | 51 |
| iPad-Landscape / Light | [05 Discover.fig](Gus/iPad-Landscape/Light/05%20Discover.fig) | 2 |
| iPad-Landscape / Dark | [05 Discover.fig](Gus/iPad-Landscape/Dark/05%20Discover.fig) | 1 |
| iPad / Light | [05 Discover.fig](Gus/iPad/Light/05%20Discover.fig) | 2 |
| macOS / Dark | [05 Discover.fig](Gus/macOS/Dark/05%20Discover.fig) | 1 |
| macOS / Light | [05 Discover.fig](Gus/macOS/Light/05%20Discover.fig) | 3 |
| macOS-Narrow / Light | [05 Discover.fig](Gus/macOS-Narrow/Light/05%20Discover.fig) | 2 |
| tvOS / Dark | [05 Discover.fig](Gus/tvOS/Dark/05%20Discover.fig) | 4 |
| visionOS / Dark | [05 Discover.fig](Gus/visionOS/Dark/05%20Discover.fig) | 3 |

The specification and scope apply across platforms; All 51 app-owned phone states have Light and Dark designs, plus 18 selected adaptive artboards. This is not every state multiplied across every device. Proposal viewports in the shared preview are static; current-app scroll behavior remains available.

## Product direction

Discover should feel like a native media catalog inside Gus. Artwork and useful metadata lead; requesting is the natural action when a title is missing. A user can move from discovery to a request, then to playback in their accessible Jellyfin library. Managers can make informed approval decisions without leaving Gus.

Use the familiar Seerr concepts and server rules, expressed through Apple navigation, controls, search, sheets and inspectors. Do not reproduce the web app's dashboard chrome. Do not replace Gus's library or playback destinations.

## Navigation and first use

- Preserve the existing configurable navigation destination. Discover can be visible, reordered, hidden and restored in Settings → Navigation. Phone mockups show a **user-customized direct Discover tab**; this does not silently change the app's default tab order.
- On first selection, show **Connect to Seerr** and **Hide Menu Item**. Hiding preserves any saved connection. Restore it from Settings → Navigation or Discover settings.
- Native setup has two destinations: Server URL → validated server and enabled sign-in methods → Sign In. Keep Back/Cancel distinct. Back discards transient credentials; Cancel dismisses the sheet and returns to the prior navigation state.
- Retain the supported Seerr version check and legacy migration guidance from current code. Revalidate the version policy against released Seerr versions during implementation. Do not present abandoned services as equivalent supported choices.
- One connection is scoped to the Gus server/account. Session cookies remain in per-device Keychain storage. Never store a password or sync a Seerr session through iCloud.
- Within Discover: Browse / My Requests / Manage Requests. Only managers see Manage. Compact mockups use “Requests” and “Manage”; accessibility labels retain full titles. If this does not fit, use a native menu rather than clipping or shrinking text. Issues and blocklist are discoverable through settings and relevant title actions, not extra global tabs.

## Screen contracts

| Destination | Content and behavior | Implementation status |
|---|---|---|
| Browse | One leading trending backdrop; horizontally scrolling shelves for supported server feeds; See All opens a paginated grid. Hero has View Title, not a surprise request. Catalog Grid is a dedicated paginated destination; it retains filters and retries a failed page in place. | Catalog foundation exists; shelves/backdrops/layout are new. |
| Search | Debounced native search; stable results; title, year, media type and availability. Two columns on normal phone, adaptive columns elsewhere, one column at accessibility sizes. | Text search exists; richer grid/filter presentation is new. |
| Filters | Genre/year/language/sort/availability only where the chosen endpoint supports them. Native pickers; explicit reset; applied state survives detail/back. Do not imply arbitrary filtering of `/search`. | New endpoint and capability mapping. |
| Movie detail | Backdrop, title/year/runtime/certification, rating source, director, synopsis, cast/crew, recommendations. No missing metadata placeholders read as real data. | Basic metadata exists; richer fields/endpoints and composition, including a Person & Credits destination, are new. |
| Series detail | Above plus seasons, episode counts and distinct available/requested/missing states. Season 0 is explicit Specials. | Season request foundation exists; richer presentation is new. |
| Request movie | Native sheet summarizes movie, format, server defaults, quota and approval requirement. One explicit submit. | Existing submission with new review presentation. |
| Request seasons | Select only eligible seasons. Available/pending seasons cannot be selected. Submit labels exact season count. Preserve selection when returning from options. | Existing selection logic; new sheet and options. |
| Advanced options | Standard/4K, permitted service, profile, root folder, optional language and user-on-behalf. Omit unsupported or unauthorized controls. Values are fetched, never freeform credentials. | New service/profile/user endpoints and authorization mapping. |
| Confirmation | Show success only after authoritative server response. Auto-approved requests show Approved; pending ones show Pending approval. Movie and series confirmations remain distinct. | Existing mutation safeguards retained. |
| My Requests | Own request history, status filters, meaningful metadata, refresh, stable position. Approval and media availability are distinct fields. | Existing history; expanded filtering/detail UI. |
| Request detail | Requester/time/seasons/format/approval and availability. Cancel only when allowed. Render only timestamps returned by the server; no fabricated audit timeline. | Rich detail/cancel expansion. |
| Available title | Show Play in Gus only after accessible Jellyfin identity match; choose a specific match if several exist. Seerr availability alone does not authorize playback. | Preserve existing provider-ID matching; richer presentation. |
| Manager queue | Pending queue by default; filter and review requester/title/seasons/format/destination before approve or decline. One decision at a time; retain selection on refresh. | Basic decisions exist; split view/filter/inspector are new. |
| Issue list/detail | Open/resolved filters, report title/episode/type/message, comments, resolve/reopen as permitted. Do not expose another user's reports merely because the UI exists. | New issue API support. |
| Blocklist | Authorized add/remove confirmation; blocklisted and content-restricted items disappear from normal discovery. Clear stale detail/selection after changes. | Existing filtering policy retained; administration is new. |
| Discover settings | Connection/account, visibility, region/language, notifications, issues, blocklist and open server settings. Disconnect affects this device; hiding preserves the connection. | Connection/visibility exist; expanded preferences are new. |
| Notifications | Server-configured supported channels and event preferences. Save/revert and unavailable-channel states. | New preferences API. Native push remains a separate project. |

## Backend feasibility and source ledger

Reviewed official Seerr documentation on October 20, 2026. Validate actual responses and permissions against the target supported server version before implementation. The public docs do not by themselves establish every deployment's capabilities.

| Capability | Official reference | Design consequence |
|---|---|---|
| Trending/catalog | [Trending](https://docs.seerr.dev/api/trending-movies-and-tv/), [discover sliders](https://docs.seerr.dev/api/get-all-discover-sliders/) | Use supported/enabled feeds; tolerate unavailable custom types and empty feeds. Do not invent personalized recommendations. |
| Request body and status | [Create request](https://docs.seerr.dev/api/create-new-request/) | API distinguishes approval from media status and accepts seasons, format, service/profile/folder/user choices. Presence in the schema is not permission to expose a field. |
| Issues/comments/status | [Issue API](https://docs.seerr.dev/api/get-all-issues/) | Reports, conversation and resolution can be native client features after endpoint/permission work. |
| Blocklist | [List](https://docs.seerr.dev/api/returns-blocklisted-items/), [add](https://docs.seerr.dev/api/add-media-to-blocklist/) | Admin actions are conditional and confirmed; blocked items stay out of catalog results. |
| User preferences | [General settings](https://docs.seerr.dev/api/get-general-settings-for-a-user/) | Region, language and quota data use the current user; other-user access requires appropriate permissions. |
| Notifications | [Agents and user preferences](https://docs.seerr.dev/using-seerr/notifications/) | Existing server notification agents are separate from native APNs. Never label web push as native iOS push. |
| Inspiration | [Pocket for Seerr](https://apps.apple.com/us/app/pocket-for-seerr/id6746105104) | Browse, request, track and approve are the central journey; artwork and richer native adaptation are Gus's proposed expression. No asset copying. |

Do not add a generic “Watchlist synced with Seerr” control: the documented user watchlist endpoint is Plex-specific. A future Gus-only saved list or Plex linkage must state its scope and get its own implementation design. Retain current local/Jellyfin authentication; Plex/Emby authentication would require separately specified secure provider flows. The native client can link to Seerr for full infrastructure administration, notification-agent secrets, service setup and user/security administration.

## Component and visual rules

- System SF Pro styles and semantic Dynamic Type; no fixed runtime font sizes copied from artboard coordinates. Native text fields, secure fields, pickers, segmented controls, buttons, forms, menus, tabs, sheets and split views own their platform rendering.
- Light and dark semantic palettes: surfaces remain neutral. Winter Chill accents use `#315F67` in this light proposal and `#B8E3E9` in dark; this is a proposed darker light accent for readable actions, not an already changed app asset. Original brand teal remains available for artwork. Review the accent decision before implementation.
- Body 17, secondary 15, footnote 13 and large title 34 in normal iPhone mockups. macOS controls use compact 12–13 point references. tvOS metadata uses 29 point references. Runtime uses platform text styles.
- Posters approximately 2:3, consistent top alignment, no fixed single-line title truncation hiding identity. Show title/year/type below art, status text with a semantic symbol as appropriate; color alone never conveys status.
- Landscape hero is a content card, not glass. Keep text in a stable safe region over a contrast scrim; use readable title text if artwork wordmarks are unavailable. Avoid auto-advancing carousels, trailer autoplay and layout shifts on image arrival.
- All artwork here is original fictional editable vector landscape art. Implementation substitutes licensed server-provided posters/backdrops with attribution required by the metadata provider. The mockups are layout/content hierarchy references, not literal replacement assets for real movies.
- Artwork placeholders reserve dimensions; show a generic film/TV symbol for missing art. Retry individual shelf failures independently. Avoid a single failed feed blanking the whole catalog.
- Native glass/material surfaces and controls are flat approximations in this document. Do not implement these rectangles as custom chrome to force pixel equality.

## Platform adaptation

| Platform | Navigation / layout | Input and adaptation |
|---|---|---|
| iPhone | Existing TabView and NavigationStack. Rich catalog scrolls beneath native chrome. Native modal sheets for setup/request. | 44-point minimum targets; safe-area inset behavior; keyboard avoidance; swipe back; restore scroll/search. Accessibility uses one column and a section menu. |
| iPad | Existing sidebar plus adaptive content; optional detail/request inspector when width supports both. Compact widths collapse to stack. | Pointer hover, keyboard search and escape, multitasking, rotation, hardware keyboard. Keep forms constrained and centered. |
| Mac | Native sidebar and toolbar/search. Request list with selected-item inspector. Narrow window navigates to detail instead. | Existing AppKit literal URL/search fields retained. Command-F returns to Browse and focuses search, Escape dismisses, Return submits valid forms, arrows/select and standard context menus. Never rebuild the sidebar as rounded cards. |
| Apple TV | Native tabs/sidebar and large artwork shelves; two-column couch-readable title detail; dedicated request confirmation. | Predictable remote focus, saved focus on return, no hover-only actions, no swipe-only operations. Minimum 29-point content references; 64–72-point action references. Expensive account/admin forms may open in Seerr on another device rather than being forced into a tiny form. |
| Vision | Native window, toolbar and tab ornament. Large content and season columns. | At least 60-point interactive targets with spacing; gaze/indirect input; readable volume; window resize and accessibility. 2D mockups cannot verify stereo depth, materials or gaze ergonomics. |
| Watch | Existing Gus experience. | No Discover destination in this scope. |

The implementation must use the target SDK's documented OS 27 APIs and availability guards. This design does not certify unreleased API behavior or bypass platform runtime review.

## State, privacy and mutation rules

1. Load cached presentation only within the same account/connection identity. A new session revision clears unauthorized details and transient selections.
2. Distinguish disconnected, validating, unsupported version, rejected credentials, expired session, offline, empty, partial-load failure and full failure. Keep the server URL for reconnect. Never silently substitute demo data.
3. Request eligibility combines media state, account permissions, quota, blocks/content restrictions and current connection revision. Refresh before mutation and revalidate on the server response.
4. Disable only the relevant in-flight action; show a labeled progress indicator. Do not clear selected seasons before confirmation. Reconcile duplicates/server conflicts against authoritative state.
5. On timeout after submit, show the uncertain-result state and refresh before any retry. No optimistic approval, cancellation, issue submission or blocklist success.
6. Available/partial/processing are availability states; Pending/Approved/Declined are approval states. Preserve unknown/deleted/error states. Do not infer torrent progress, quality, ETA or requested-by details absent from the response.
7. Request/issue destructive actions use native confirmations naming the title and scope. TV/visionOS use platform input patterns; avoid long press as the only route.
8. Never log cookies, credentials, private server paths or full user catalogs. Root-folder/service labels shown to managers come from the permitted API; redact them from diagnostic exports.
9. Restriction changes remove blocked content immediately, including visible detail and image accessibility labels. Playback rechecks accessible Jellyfin matches using external IDs.

## Implementation order after design review

1. **Catalog and detail presentation:** existing API flow, artwork loading/cache, shelves and paginated grids, adaptive navigation and detailed metadata. Keep current request safety logic. Add missing browse/detail endpoints with captured contract fixtures.
2. **Request and manager UX:** distinct movie/season sheets, status detail, cancellation eligibility, queue filters and native inspector. Validate new lifecycle transitions, account/session changes, quota conflicts and uncertain mutations.
3. **Advanced request choices:** fetch permitted services/profiles/folders/users; support Standard/4K and user-on-behalf only when authorized. No freeform service secrets.
4. **Issues and blocklist:** model permissions and IDs, report/comment/resolve/reopen, block/unblock, filter invalidation and conflict recovery.
5. **Preferences and polish:** available server notification preferences, region/language, keyboard/remote/gaze, Dynamic Type, localization and contrast. Native push and provider authentication extensions remain separate.

Sequential acceptance gates: targeted model/API tests → one-platform build/test at a time → representative GUI paths → live Seerr with restricted user and manager → physical iPhone/iPad/Mac/TV/Vision checks → hosted checks/distribution when separately requested. No builds, simulators or live requests were necessary for this design proposal.

## Coverage boundaries

The integrated Discover Proposal pages contain 120 artboards, covering all 51 app-owned phone states in both appearances and 18 selected native adaptive compositions. `References/Source/discover/coverage-contract.json` declares the required inventory and is checked against the saved documents. It is a focused feature design, not every state multiplied across every device. `References/Source/discover/manifest.json` records each editable file and its saved page/node IDs. `References/QA/Discover/` records saved-file checks, font checks, raster proofs and visual review.

Native system share sheets, password AutoFill/save, trust/permission dialogs and web authentication belong to the OS. The proposal documents their entry points rather than fabricating their entire interface. Region/genre/profile selections use native pickers; their data-specific options are specified here but not exhaustively artboarded. Native prototype reactions, runtime focus and accessibility acceptance remain distinct from editable design coverage.

The completion audit added dedicated catalog pagination, person/credits, request-filter, unsupported-server, sign-in error, connection error, partial shelf failure, permission-change and mutation-rejection designs. TV movie request and confirmation are distinct from season requests; Vision has its own confirmation. These remain proposed behavior.
