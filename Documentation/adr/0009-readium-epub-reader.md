# 0009 — Readium for in-app EPUB reading

Date: 2026-06-10
Status: accepted

## Context

The native-first mandate allows a non-system dependency only when no system API can do
the job, recorded as an explicit decision. In-app EPUB reading is that case: Apple ships
no EPUB rendering framework (Apple Books is an app, not an API), and a bespoke reader
means a ZIP/OPF/XHTML rendering engine — a product-sized custom subsystem that violates
the same mandate from the other direction.

The alternative — share-sheet handoff to Apple Books — remains in place, but it breaks
the Jellyfin-client contract: position and library state fork into Apple's silo and never
return to the server, and reading becomes a two-app flow. Gus's goal is a one-stop shop
for the user's Jellyfin media.

## Decision

Adopt the **Readium Swift Toolkit** (BSD-3, Readium Foundation) for in-app EPUB reading,
linked **only** into the iOS/iPadOS destination via XcodeGen `destinationFilters`. tvOS
and macOS do not link Readium by design: tvOS has no WebKit (book details only), macOS
keeps the share-sheet/Apple Books path.

**visionOS is intended scope but blocked upstream**: `ReadiumStreamer`'s audiobook
manifest augmentor uses the synchronous `AVAsset.metadata`, which Apple marked
unavailable on visionOS, so the toolkit does not compile for the native xrOS SDK (as of
3.9.0 and current `main`). visionOS gets the share-sheet path meanwhile; add visionOS to
the destination filters when upstream adopts the async `load(.metadata)` API. The fix is
small and worth offering upstream as a PR.

Products used: `ReadiumShared`, `ReadiumStreamer`, and `ReadiumNavigator`.
Readium 3.9 serves EPUB resources through WebKit `WKURLSchemeHandler`; its legacy
HTTP-server initializer is deprecated. The unused `ReadiumAdapterGCDWebServer`
product was removed from Gus on October 11, 2026.

Readium 3.9's publication/retriever/opener classes do not declare Sendable
conformance. Each EPUB load now constructs its own object graph in an explicitly
concurrent, nonisolated operation, resolves chapters and the initial locator there,
then transfers the completed result once with Swift's `sending` ownership boundary
to the main-actor reader. The graph is not shared with a navigator while loading;
Gus does not add unchecked Sendable conformances or relax its concurrency checks.
Reading-order resource comparisons use Readium's normalized `isEquivalentTo` API.

The reader retains and binds Readium's `DirectionalNavigationAdapter` for edge taps
and hardware-key page navigation. Its chapter browser uses a native SwiftUI sheet,
`List`, and recursive `DisclosureGroup` entries, including separate parent-link
navigation. A toolbar-hosted nested `Menu` exposed an unwanted software keyboard in
the iOS 27 simulator; the chapter button ends editing in its own reader window before
presenting the sheet. Dismissal restores the visible navigator's first-responder
status. Opening chapter navigation is not treated as reader completion for automatic
download deletion.

Reading position uses two layers. The exact Readium `Locator` persists locally per book
(`BookProgressStore`) for precise same-device resume. A coarse 0...1 fraction also syncs
to Jellyfin via `UserData.PlaybackPositionTicks` (a spike confirmed Jellyfin 10.11
round-trips it against a book's 1-second synthetic runtime, and surfaces the book in
"Continue"), so reading position carries across devices and other clients; on open with
no local locator the reader restores from the server fraction. Server sync is gated by
`ProviderCapabilities.supportsBookProgressSync` and is best-effort — a failed write never
interrupts reading. See `JellyfinBookProgress` for the mapping.

## Consequences

- The "only runtime dependency is jellyfin-sdk-swift" rule in AGENTS.md becomes "…plus
  Readium on iOS/iPadOS/visionOS for EPUB reading"; AGENTS.md is updated alongside this
  ADR.
- Readium pulls transitive dependencies (CryptoSwift, SwiftSoup, ZIPFoundation fork,
  Fuzi fork, Zip, DifferenceKit) into the iOS/iPadOS build graph only.
  GCDWebServer and SQLite may still resolve because Readium declares optional
  adapters at package level; Gus does not select those products.
- The reader inherits Readium's accessibility and pagination behavior rather than Apple
  Books' polish; the share sheet remains the escape hatch to Books on every non-tvOS
  platform.
- Privacy: Readium renders local files through a WebKit URL-scheme handler; no network beyond the existing
  Jellyfin fetch, no analytics. The compliance audit's framework list gains Readium.
