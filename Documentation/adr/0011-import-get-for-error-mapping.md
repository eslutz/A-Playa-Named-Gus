# 0011 — Direct import of Get package for HTTP error code access

Date: 2026-06-12
Status: accepted

## Context

The native-first mandate limits runtime dependencies to `jellyfin-sdk-swift` (plus Readium
on iOS/iPadOS — ADR 0009). `jellyfin-sdk-swift` uses the
[Get](https://github.com/kean/Get) package as its HTTP transport layer, meaning Get is a
*transitive* dependency that arrives automatically but is not a *declared* direct
dependency of A Playa Named Gus.

One file needs to expose Get's `Request<T>` type in its public API:

- `Sources/Services/DownloadSourceResolver.swift` — stores the Jellyfin SDK `Request<Data>`
  value returned by `Paths.*` functions in its `Source` struct. The URL in those requests is
  relative to the client's base URL, so it cannot be resolved to an absolute URL without a
  `JellyfinClient`. There is no alternative to naming `Request<T>` here.

`Sources/Services/GusError.swift` previously imported Get to pattern-match `APIError`, but
was updated to detect the type by its fully-qualified name (`"Get.APIError"`) and extract
the HTTP status code through `Mirror` reflection, removing the direct import.

JellyfinAPI does not use `@_exported import Get`, so `Request<T>` and `APIError` are not
available from `JellyfinAPI` alone.

## Decision

Accept the direct `import Get` in `DownloadSourceResolver.swift` as an approved exception
to the no-undeclared-dependency rule. The import is intentional and minimal — it touches
only this one file. This ADR records the decision so contributors know the import is not
an oversight and understand the constraint that motivates it.

`GusError.swift` avoids the direct import by using `Mirror`-based reflection to extract
the status code. This is fragile only if Get renames `APIError` or its associated value —
unlikely given that Get is pinned transitively by the SDK.

The surface is kept deliberately narrow: only the `Source.request` field in
`DownloadSourceResolver` names a Get type. All other SDK error handling goes through the
`GusError` abstraction without importing Get.

## Consequences

- If `jellyfin-sdk-swift` migrates its transport from Get to another package, only
  `DownloadSourceResolver.swift` requires updating — plus a minor adjustment to the
  `Mirror` branch in `GusError.swift` if the replacement error type has a different name
  or shape. The impact is bounded to two files and one extraction pattern.
- Contributors adding new SDK error inspection must route through the existing
  `GusError.fromHTTPStatusCode` helper rather than adding new `import Get` sites.
- No change to any other file or to App Review compliance — Get is already present in the
  dependency graph as a transitive package; this ADR documents usage, not introduction.
