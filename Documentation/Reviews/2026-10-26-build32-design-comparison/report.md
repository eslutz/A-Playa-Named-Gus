# Gus iPhone light comparison — Build 32 vs Sketch R5

80 captured app views: 57 matched to a closest valid Sketch counterpart and 23 with no matching saved design screen/state found. The source/walkthrough inventory contains 120 entries: 80 captures, 4 controls covered within those captures and 36 capture limitations. These are inventory entries, not a claim to cover every possible data/error permutation.

The app is a Release simulator rebuild of verified TestFlight source c2301c2e16cc7841368cbb65b8d4cd4e31d29992. All 302 runtime fingerprints and the package lockfile match release evidence. Installed version 1.0.0 (32); arm64, zero build warnings/errors. iPhone 17, iOS 27.0, 402 × 874 points; original app PNGs 1206 × 2622. System light appearance, default text size; app System/light initially and explicitly Light later. Native media canvases remain black. gus-demo-jellyfin supplies all authenticated content.

Sketch baseline: [R5 Light, eeGbj2](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2), the latest recorded checkpoint. Fresh 3× exports were made from a separate copy of the preserved snapshot in Sketch 2026.3.1. Snapshot SHA-256 b06c897172380c57f5c0a41a74e249375cdea5d5f85eacea8d9ab11f6b27f802. Live cloud history could not be independently refreshed because the browser is signed out. No design changes or acceptance decisions were made.

Artwork, titles, metadata, counts and available services differ between abstract design fixtures and public-domain demo media. Notes distinguish these from layout differences. Some pairs deliberately use the closest valid counterpart at a different state/scroll position; those differences are stated. No Sketch-only screens are included. GUS-052 is reserved for an excluded duplicate AirPlay attempt and is intentionally absent.

Review each ID using **Prefer Sketch / Prefer app / Combine / Additional changes**. The private Page is the commentable review destination. The local image set is retained in the ignored design archive, not in source.


## Index

- [Connection and accounts](#chapter-1)
- [Home and navigation](#chapter-2)
- [Downloads](#chapter-3)
- [Movies and shows](#chapter-4)
- [Playback](#chapter-5)
- [Settings](#chapter-6)
- [Discover and Live TV](#chapter-7)
- [Playlists and collections](#chapter-8)
- [Music and photos](#chapter-9)
- [Books](#chapter-10)


<a id="chapter-1"></a>

## Connection and accounts

### GUS-001 — Connect to Jellyfin



Sketch uses a branded introduction, one address field, a local-server row and a prominent Connect button. Build 32 uses grouped form sections and a separate local-discovery empty state. Both captures have no entered server address.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/B4183496-BCCD-4491-8713-97BC66F36E82) — Connect / Ready / iPhone Regular

**GUS-001 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-002 — Jellyfin Sign In



Sketch places the brand and sign-in explanation above labeled fields and includes More sign-in options. The app uses the server name as its navigation title and shows Quick Connect directly. Sketch has example credentials entered; the app fields are empty.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/151C5678-F5DD-4649-9EBD-96E8CF7A9836) — Sign in / Ready / iPhone Regular

**GUS-002 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-003 — Quick Connect authorization



Sketch gives the approval code a dedicated screen and large type. The app inserts the code and Cancel action into its existing sign-in form. Codes and server identities are capture content, not design differences.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/DE6C0C05-3D1B-48AE-A483-DB36836E3132) — Quick Connect / quick-code / iPhone Regular

**GUS-003 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-080 — Connecting to server



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-080 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-081 — Sign-in error



Sketch changes the sign-in heading and displays recovery text; Build 32 retains the form and inserts a red error row. One deliberately incorrect demo password produced this capture; no repeated failures were attempted.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/D6880C8F-87DC-4451-8DE5-A303CFC3A008) — Sign In / signin-rejected / iPhone Regular

**GUS-081 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

<a id="chapter-2"></a>

## Home and navigation

### GUS-004 — Home



Both use landscape Next Up cards and portrait media shelves. Sketch uses separate Movies/Series tabs and a trailing Search control; the app exposes Search Library above the shelves and different default tabs. Available shelves and artwork differ with demo content.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/76FDFFE0-7D2F-4368-A8B5-B38CE01A4256) — Home / Ready / iPhone Regular

**GUS-004 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-005 — Next Up full list



Sketch shows a poster grid with a List switch. Build 32 shows a compact episode row. Item counts, titles and resume progress differ.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/24196BBE-1758-4DC9-923F-A292C46E73EA) — Next Up / Show All / Poster grid

**GUS-005 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-008 — Libraries



Sketch lists named libraries as text rows. The app presents a two-column artwork grid. Library names and counts come from different fixtures.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/EAFE64FF-6414-4030-A020-26AA07D14494) — Libraries / Accessible individual libraries

**GUS-008 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-019 — More destinations



Sketch uses a flat list of sections; the app uses a grouped card with icons. Different entries reflect navigation configuration; Photos and Live TV were enabled later through the app’s Navigation settings for their captures.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/CB8C0E2F-6FA4-4180-A055-46C20CC5B73B) — More / Ready / iPhone Regular

**GUS-019 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-071 — Search entry



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-071 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-072 — Search results



Both show poster search results. Sketch uses a titled Search destination and bottom search field; the app uses a top search field. Queries, results and counts differ.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/8C7DE654-FCF9-4282-AAD1-37F18A189236) — Search / Results / iPhone Regular

**GUS-072 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-073 — Search — no results



Both represent no search results. Sketch adds explanatory text and Edit Search; the app centers a symbol and No Results while retaining the top query.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/FC125CFE-3C8A-4F00-8A25-C38E79EF1AF1) — Search / search-empty / iPhone Regular

**GUS-073 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-074 — Home — lower shelves



Supplementary Home scroll capture. Both continue media shelves, but this app viewport shows Books/Movies while the design shows Shows/Music. Shelf availability/order and artwork differ with the fixture; do not compare those titles as visual defects.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/B1624478-D5B8-422B-B44C-A386BBEF2B59) — Home / Scrolled Shows and Music / Reference

**GUS-074 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

<a id="chapter-3"></a>

## Downloads

### GUS-006 — Downloaded media — empty



Closest destination counterpart: Sketch shows a populated Downloads list with transfer states and Download Options. The app capture is the empty Downloaded library with search, media segments and Manage Downloads. The empty versus populated state is intentional and is not evidence of missing downloads.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/3A547C2E-3FCA-4B0E-8A76-6444728C8BD7) — iPhone / Downloads / Ready / 402

**GUS-006 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-007 — Manage Downloads — empty



Both show storage statistics and Delete After Finishing. The app wraps sections in grouped cards and uses a centered No Downloads state; Sketch uses a flatter list and inline empty copy.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/AB246454-FB78-4E9B-838C-990BADE24CA5) — Downloads / All removals confirmed / Alex / Off / Regular

**GUS-007 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-017 — Manage Downloads — completed item



Both show storage totals, transfer counts and Delete After Finishing. Sketch contains several transfer states; the app has one completed movie. Different sizes and active/paused counts are demo-state differences.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/96B9E779-4CB5-4D6B-8918-80479682C2C1) — Downloads / Manage / Alex / Off / Regular

**GUS-017 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-018 — Download selection mode



Both enter download selection mode with Done and Select All. The app also exposes a disabled Delete Selected (0) row. The Sketch fixture has more download records, extending below the viewport.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/544756F4-B249-4D15-9D88-03381F2BF425) — Downloads / Selecting / None of seven / Alex

**GUS-018 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-076 — Delete downloads confirmation



Both show a destructive download confirmation that preserves the server copy. The app warning names a movie; Sketch names an EPUB/PDF fixture. The confirmation was canceled.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/467B72E9-DBC1-4A54-9CD2-30804B5B12EA) — Downloads / Delete one PDF / Confirmation / Alex

**GUS-076 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-077 — Downloaded media — populated



Sketch’s Downloads destination mixes transfer status with downloaded items and a Download Options button. Build 32 separates the completed Downloaded library from management, adding search and media segments. The single retained movie is demo state.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/3A547C2E-3FCA-4B0E-8A76-6444728C8BD7) — iPhone / Downloads / Ready / 402

**GUS-077 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

<a id="chapter-4"></a>

## Movies and shows

### GUS-009 — Movies library



Sketch shows a single-library poster grid with a List toggle and scope caption. The app includes a Collections shelf above movies and a filter menu. Artwork and movie counts differ.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/3A0F093A-403C-4D6D-9EB8-F257D4ABCFB5) — Library / Movies / Single-library scope

**GUS-009 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-010 — Library sort and status filter



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-010 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-011 — Movie details



Both have hero artwork, playback and circular secondary actions. Sketch places overview text in the hero and Cast & Crew immediately below; the app shows Recommended below this movie. Metadata and available credits differ by title.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/C3BD6F17-3046-42CC-B65C-267D971682E3) — Movie / Play detail · Unstarted / iPhone Regular

**GUS-011 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-012 — Movie detail actions



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-012 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-013 — Add to playlist



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-013 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-014 — Add to collection



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-014 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-015 — Movie details — lower sections



Supplementary scroll capture of GUS-011. Build 32 reveals Recommended and About lower down; the same Sketch detail frame is repeated because no equivalent scrolled frame was found.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/C3BD6F17-3046-42CC-B65C-267D971682E3) — Movie / Play detail · Unstarted / iPhone Regular

**GUS-015 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-043 — Shows library



Closest show-library counterpart: Sketch’s Show All grid is scoped to shows, while Build 32 is the Shows destination. Both use posters; toolbar and navigation context differ. The app includes two demo series.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/2547202C-4FD5-434A-9493-3091ABAA1A90) — Show All / Recently Added / Shows library

**GUS-043 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-044 — Series details and episodes



Both present a series with episode browsing. The Sketch counterpart retains an episode scroll anchor; the app shows the hero and Season 1 entry. Different viewport position and series metadata must be considered.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/88EBED7F-3626-441C-8F26-1B1506EC2359) — Library Series / Blue Hour / Season1 restored episode anchor / iPhone Regular

**GUS-044 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-045 — Season picker



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-045 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-046 — Episode details



Both show episode hero details and playback. Sketch uses the unstarted Play state; the app has Resume after playback. Cast presentation also differs: Sketch uses a row, the app visible cast cards.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/1689C969-AA7C-40C1-8629-51A71A2E3798) — Episode / Play detail · Unstarted / iPhone Regular

**GUS-046 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-075 — Media context menu



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-075 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

<a id="chapter-5"></a>

## Playback

### GUS-016 — Video player — controls visible



Both represent the native video-player surface. The Sketch frame is a sparse AVKit placeholder with Done; the real app exposes playback, seek, route and speed controls. AVKit keeps a black playback background even with system/app light appearance; this is not a dark-mode app capture.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/4968CF2A-B950-4E71-B7CE-25D1FE7339F9) — Playback / System AVKit / Dark / iPhone Regular

**GUS-016 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-078 — Video playback speed



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-078 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

<a id="chapter-6"></a>

## Settings

### GUS-020 — Settings — account and playback



Sketch gathers account, navigation and preferences into a concise settings list. Build 32 expands user/server details and account status inline and shows search. The server/user values are demo content.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/0D191B85-7D20-421E-8536-BFCD1C803EAB) — Settings / Ready / iPhone Regular

**GUS-020 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-021 — User profile



Both edit username and preferred audio/subtitle languages. Build 32 uses a sheet with avatar and grouped fields; Sketch uses a flatter form with a prominent Save Changes button. No profile changes were saved.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/7C98D9EF-4019-4D7D-917E-C8863E3D895A) — Profile / Ready · current server values / Native sheet content

**GUS-021 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-022 — Profile language choices



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-022 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-023 — Streaming quality choices



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-023 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-024 — Settings — playback, appearance and content



Closest settings counterpart: Sketch separates Preferences into its own screen. Build 32 keeps playback, iCloud, appearance, navigation and restrictions in the scrollable Settings form.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/D154C4B9-BC24-4103-8FD1-EFBF33391C8E) — iPhone / Preferences / Ready / 402

**GUS-024 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-025 — Appearance choices



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-025 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-026 — Content rating choices



Sketch shows a dedicated Restrictions screen with the limit Off. Build 32 shows the rating-choice popup in Settings. This pair compares the same setting at different presentation stages; it is not an exact open-menu design match.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/E75B73CE-0287-4173-8CB1-6E778BEF3AD6) — iPhone / Restrictions / Limit Off · Hide Unrated hidden / 402

**GUS-026 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-027 — Navigation sections



Sketch shows removal/reordering controls immediately. Build 32 starts with a read-only shown/hidden list and an Edit button. Section order differs with configuration.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/7A188E60-9BE8-4B35-974B-43AFC51BF787) — Navigation / Ready / iPhone Regular

**GUS-027 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-028 — Edit navigation sections



Sketch separates Shown and Hidden using segments. Build 32 displays both groups in one scrolling editor with remove/add controls and a checkmark to finish.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/E1975D08-671C-4EE7-9A13-AB497E864039) — Navigation / Edit shown sections / Available sections

**GUS-028 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-029 — Settings — content, Seerr and About



Supplementary Settings scroll capture. Build 32 shows restrictions, Sign Out, Seerr and About values inline; Sketch’s root settings frame uses navigation rows. The root design is repeated for context.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/0D191B85-7D20-421E-8536-BFCD1C803EAB) — Settings / Ready / iPhone Regular

**GUS-029 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

<a id="chapter-7"></a>

## Discover and Live TV

### GUS-030 — Seerr settings — disconnected



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-030 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-031 — Connect to Seerr



Both collect a Seerr URL in a sheet. Sketch shows a filled example and Continue button near the middle; Build 32 has an empty grouped field and disabled Continue row. Server values and input completeness differ.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/6707C1F7-1677-4BEB-99D9-F2123A3CF49B) — Discover / Seerr server setup

**GUS-031 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-042 — Discover — not connected



Both explain Discover and offer Connect to Seerr plus Hide Menu Item. Build 32 adds a centered symbol and uses more compact controls. Both are disconnected.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/2C074268-BF73-4C1D-8279-627997284154) — Discover / First use

**GUS-042 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-070 — Live TV — no channels



Closest Live TV destination counterpart: Sketch contains channels, Recordings/Scheduled segments and Reload. The app shows No Live TV Content because the demo server has no TV source. Populated versus empty content is an explicit state difference.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/072BF5B2-1A4B-4FC1-9FB8-18A3CCA49F88) — iPhone / Live TV / Ready / 402

**GUS-070 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-079 — Seerr connection validation error



Both display an inline connection error. Sketch says the Seerr server cannot be reached; Build 32 reports that the item is unavailable when given the Jellyfin-only demo URL. These are different validation causes in the same setup flow.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/1F6B8693-8351-43AB-8BE9-9E0427BCCCE7) — Discover / Seerr unreachable server

**GUS-079 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

<a id="chapter-8"></a>

## Playlists and collections

### GUS-032 — Playlist update error



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-032 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-033 — Playlists



Both list playlists. Sketch includes a Grid toggle and bottom New Playlist button; Build 32 uses a toolbar plus button. Playlist names and counts are existing demo fixtures.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/58241D21-C2A0-4CA9-ABF4-44497AA9B688) — iPhone / Playlists / Ready / 402

**GUS-033 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-034 — Create playlist



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-034 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-035 — Video playlist details



Sketch uses numbered media rows and a bottom Resume action. Build 32 places Play, repeat and shuffle beneath the title, with Add Items above grouped rows. Playback progress and entry counts differ.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/96E9FF8D-4BD9-4926-A6CC-DDE8CBC935E5) — Canonical · Video Playlist

**GUS-035 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-036 — Playlist actions



Both expose playlist actions in a menu. Sketch’s menu includes Start from Beginning and Shuffle; Build 32 has playback controls on the parent screen and menu entries for Rename, Edit Items, Add to Next Up and Delete Playlist.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/D93B54B6-BFF4-409B-9060-CD4EC2AC2D60) — Video Playlist / Weekend Films / List / More menu open

**GUS-036 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-037 — Rename playlist



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-037 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-038 — Edit playlist items



Both expose remove/reorder editing. Sketch shows drag handles plus a move-action popup; the app capture shows removal controls and Done. The open move popup is a state difference.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/63D8A9D2-DB06-4FC7-ADBF-92CF5BE276E3) — Canonical · Playlist Edit Items

**GUS-038 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-039 — Add playlist items



Both are Add Media sheets. Sketch shows a populated search with keyboard and results; Build 32 shows the empty query with the search field at the bottom. No items were added.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/A28877FB-F55D-4622-881C-5872B4FB41AD) — Canonical · Playlist Add Media

**GUS-039 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-040 — Delete playlist confirmation



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-040 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-041 — Empty playlist



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-041 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-061 — Collections



Sketch defaults to a collection list with Grid toggle and bottom New Collection. Build 32 shows a grid and a toolbar plus button. Collection names and artwork are demo fixtures.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/8BF37861-2C0C-4E84-9E8E-A8E634BEFF91) — iPhone / Collections / Ready / 402

**GUS-061 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-062 — Create collection



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-062 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-063 — Collection details



Sketch presents collection films as rows with Grid/More controls. Build 32 uses a collection header and poster grid. Membership counts and artwork differ.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/1354BA7D-AF67-4AAD-B6C1-C2350BDA3262) — iPhone / Coastal Stories / Ready / 402

**GUS-063 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-064 — Collection actions and sort order



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-064 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-065 — Edit collection



Both edit name, description and artwork. Build 32 uses a grouped sheet with top Save; Sketch uses a flat form and bottom Save with explanatory copy. No changes were saved.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/70143BB4-4847-432D-838D-0F77E8684819) — Canonical · Collection Editor

**GUS-065 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-066 — Add movies to collection



Both are Add Movies membership sheets. Sketch has a search result and selected item; the app shows an empty search. Existing membership and search state differ. No movies were added.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/20B0504C-D479-44BB-AAAD-7B93758B1255) — Canonical · Collection Membership

**GUS-066 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-067 — Delete collection confirmation



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-067 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

<a id="chapter-9"></a>

## Music and photos

### GUS-047 — Music library



Sketch surfaces an album followed by Artists. Build 32 begins with existing playlist tiles, with artists and albums farther down. This is a hierarchy difference as well as different demo library composition.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/F0050F33-FABD-40BD-BC51-388C614DACEF) — Music / Library / iPhone Regular

**GUS-047 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-048 — Music library — artists and albums



Supplementary GUS-047 scroll capture showing app artists/albums. The same Sketch Music frame is repeated for context; artwork and available artist associations differ.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/F0050F33-FABD-40BD-BC51-388C614DACEF) — Music / Library / iPhone Regular

**GUS-048 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-049 — Artist albums



Both show an empty artist-albums state. Sketch uses inline text under the artist name; the app centers a symbol and No Albums. Different artist names are content.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/2E335A8F-C882-4ACE-8B90-CAE33C94A279) — Music / artist-empty / iPhone Regular

**GUS-049 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-050 — Album and tracks



Both show album artwork, Play/Shuffle and tracks. Sketch uses compact inline metadata and flat rows; Build 32 uses a larger title/artist block and rounded grouped track list.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/D9F886F3-8295-46AA-94C3-07B1A45EA7FA) — Music / browse from library album / idle / iPhone Regular

**GUS-050 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-051 — Audio player



Both show paused audio with scrubber, transport, shuffle and repeat. Sketch also draws volume and queue controls; the app capture exposes an AirPlay route button and close/stop symbols. Missing demo artwork explains the placeholder.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/B94CB013-DA53-4B1B-A83A-DA42D2B2623F) — Audio / Now Playing / paused / Canonical

**GUS-051 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-053 — Persistent Now Playing control



Both retain a mini-player beneath album content. Sketch includes the track’s artwork and a labeled track line; the app uses a compact capsule. The selected track and album artwork differ.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/D220037C-1F19-4A57-8398-9AB9D77323E0) — Music / browse from library album / paused / iPhone Regular

**GUS-053 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-059 — Photos library



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-059 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-060 — Photo album



No equivalent screen/state was found among the saved R5 Light frames. The app capture is retained for review; the blank panel does not mean the app screen is absent.



**GUS-060 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-068 — Photos destination



Both show a photo grid with captions. Sketch has separate List and Filter buttons; the app uses a filter icon. Different photograph aspect ratios and names are content differences.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/47557501-D110-4872-BCC1-A3E9DC61C16A) — Photos / Library / iPhone Regular

**GUS-068 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-069 — Photo viewer



Both display an image against black with title and slideshow control. Build 32 retains the tab bar in this capture; Sketch does not. Black is the viewer’s media canvas while the app remains light.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/43F20F90-A8E7-406E-A4F2-164F9240E450) — Photos / Coast at Dawn / Manual / iPhone Regular

**GUS-069 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

<a id="chapter-10"></a>

## Books

### GUS-054 — Books library



Both use a book-cover grid. Sketch includes separate List and Filter controls; the app has one filter icon. The demo EPUB files have no cover images, so the app displays placeholders.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/E852D5BF-7F46-4D95-A919-83A59BCE2FBC) — Books / Library / iPhone Regular

**GUS-054 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-055 — Book details



Sketch presents a book cover with Read/Share below. Build 32 uses the common media-detail hero, Read/Share and secondary actions, followed by recommendations. EPUB metadata and covers differ.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/6DC5135D-4BA8-405C-B6A0-F255C77DA87C) — Books / The Lantern Route / Details / iPhone Regular

**GUS-055 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-056 — EPUB reader



Both show an EPUB reader with close and chapter navigation. Sketch displays chapter prose; the app capture is Dracula’s title page. Publication typography and content differ, so this is not a like-for-like page-format test.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/3B19CA2E-53F8-4787-A8EC-2C6C2FE351C3) — Books / The Lantern Route / Reader / iPhone Regular

**GUS-056 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-057 — Book chapter navigation



Both show chapter navigation in a sheet. Sketch uses an X and a flatter hierarchy; the app uses Done and grouped rows. Chapter labels and nesting come from different books.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/AC132E84-6E75-427F-BBD1-84F7D44CAC88) — Books / Chapters / Collapsed groups / iPhone Regular

**GUS-057 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

### GUS-058 — Book sharing sheet



Both show a native sharing sheet over the book detail. Available share destinations depend on simulator apps/accounts; their absence is not treated as an app design defect. The app also exposes SharePlay.

[Sketch frame](https://www.sketch.com/s/5d22768f-8a13-470f-badd-0de9f9dec51c/v/eeGbj2/f/875B32E5-A217-4757-9900-2389A5E1EA07) — Books / system-sharing / iPhone Regular

**GUS-058 review:** Prefer Sketch / Prefer app / Combine / Additional changes —

## Capture limitations

- **Connection error** — Connection to an unused localhost port remained pending during observation; canceled through the app. No completed error captured.
- **Local server discovery results** — The requested demo server was not discovered on the local network. Other server results are outside the requested demo scope.
- **Restricted content** — Demo content did not present a restricted-content state during the walkthrough.
- **Audio playback speed** — No audiobook media is present in gus-demo-jellyfin; this control is audiobook-specific.
- **Audiobook chapter menu** — No audiobook media or chapter metadata is present in gus-demo-jellyfin.
- **AirPlay output picker** — AirPlay action did not present a route picker in this simulator.
- **PDF reader** — The demo Books library contains EPUB files, no PDFs.
- **Download in progress** — The tested demo download completed before a stable progress capture was obtained.
- **Video audio and subtitle controls** — The tested demo episode exposed no alternate audio/subtitle menu in the native player.
- **Seerr sign in** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Discover browse** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Discover catalog results** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Discover catalog filters** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Discover movie details** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Discover series details** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Discover season and episodes** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Discover person and credits** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Choose Jellyfin playback match** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Review movie request** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Review series request and options** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **My Requests** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Manage Requests** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Request details and management confirmations** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Issues** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Report an issue** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Issue discussion and status confirmations** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Blocklist and removal confirmation** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Block title confirmation** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Seerr catalog and notification preferences** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Connected Discover settings and disconnect confirmation** — Requires an authenticated Seerr 3 service and appropriate server data or permissions. The requested gus-demo-jellyfin server supplies Jellyfin only.
- **Full synopsis sheet** — The inspected demo detail layouts did not expose a full-synopsis sheet.
- **Media replacement picker** — No stale or missing saved-media reference was encountered; demo library was not damaged to manufacture one.
- **Saved progress transfer and confirmation** — No replacement/progress-recovery condition was encountered in the demo account.
- **Account reauthentication** — The demo account had a valid fresh session; no expired stored-account session was available.
- **SharePlay sharing and unavailable alert** — Native Share sheet is captured, but a SharePlay session requires additional participants/account conditions not available in this simulator walkthrough.
- **Download failure alert** — No download failure occurred during the demo walkthrough.