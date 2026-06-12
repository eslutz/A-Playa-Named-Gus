# 0011 — Direct import of Get package for HTTP error code access

Date: 2026-06-12
Status: accepted

## Context

The native-first mandate limits runtime dependencies to `jellyfin-sdk-swift` (plus Readium
on iOS/iPadOS — ADR 0009). `jellyfin-sdk-swift` uses the
[Get](https://github.com/kean/Get) package as its HTTP transport layer, meaning Get is a
*transitive* dependency that arrives automatically but is not a *declared* direct
dependency of A Playa Named Gus.

Two files need to inspect the HTTP status code carried inside SDK error values:

- `Sources/Services/GusError.swift` — maps SDK errors to `GusError` cases (e.g.
  `.unauthorized`, `.notFound`) by reading the HTTP status from `APIError`.
- `Sources/Services/DownloadSourceResolver.swift` — inspects the status code from a
  failed `Paths.getPostedPlaybackInfo` call to decide whether to fall back to progressive
  download.

Both files use `import Get` to access `APIError` and its `.statusCode` property. There is
no native `URLSession` or Foundation API that exposes the HTTP status from a request the
SDK manages internally — the SDK wraps URLSession responses and surfaces them only through
its own error types. Casting through `URLError` or `NSError` does not reach the HTTP
layer; `swift-openapi-runtime`'s error types are also SDK-internal at this point. The only
stable extraction path is `Get.APIError.statusCode`.

## Decision

Accept the direct `import Get` in `GusError.swift` and `DownloadSourceResolver.swift` as
an approved exception to the no-undeclared-dependency rule. The import is intentional and
minimal — it touches only these two files. This ADR records the decision so contributors
know the import is not an oversight and understand the constraint that motivates it.

The surface is kept deliberately narrow: only `GusError.fromHTTPStatusCode(_:)` and the
playback-info error branch in `DownloadSourceResolver` reach into Get directly. All other
SDK error handling goes through the `GusError` abstraction.

## Consequences

- If `jellyfin-sdk-swift` migrates its transport from Get to another package (e.g.
  `swift-openapi-runtime` becomes the sole error surface), `GusError.swift` and
  `DownloadSourceResolver.swift` will need updating to the replacement error type. The
  impact is bounded: there are exactly two call sites and a single extraction pattern.
- Contributors adding new SDK error inspection must route through the existing
  `GusError.fromHTTPStatusCode` helper rather than adding new `import Get` sites.
- No change to any other file or to App Review compliance — Get is already present in the
  dependency graph as a transitive package; this ADR documents usage, not introduction.
