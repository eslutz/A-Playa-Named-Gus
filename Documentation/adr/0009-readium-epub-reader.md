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

Products used: `ReadiumShared`, `ReadiumStreamer`, `ReadiumNavigator`,
`ReadiumAdapterGCDWebServer` (the navigator serves publication resources over a loopback
server).

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
  GCDWebServer fork, Fuzi fork, Zip, DifferenceKit) into the iOS/visionOS link units
  only. tvOS/macOS binaries are unchanged.
- The reader inherits Readium's accessibility and pagination behavior rather than Apple
  Books' polish; the share sheet remains the escape hatch to Books on every non-tvOS
  platform.
- Privacy: Readium renders local files over loopback; no network beyond the existing
  Jellyfin fetch, no analytics. The compliance audit's framework list gains Readium.
