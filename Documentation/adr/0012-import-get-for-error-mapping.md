# 0012 — Typed use of the existing Jellyfin transport

Status: accepted; revised for app-wide refinement on 2026-11-15.

The resolved Jellyfin SDK already depends on Get. Gus imports that existing
transport in `DownloadSourceResolver` to name SDK `Request<Data>` values and in
`GusError` to match `APIError` using its public type. `JellyfinClientFactory` installs
`SessionAuthentication`, which conforms to Get's transport delegate so authenticated
errors pass through one identity-bound boundary. These four imports add no runtime package.

Use the shared error adapter for HTTP status classification: 401 requests
identity-bound reauthentication; 403 reports insufficient permission without
removing credentials or account data. Remove reflection on type names/associated
values. Feature stores do not inspect Get errors independently.

If the SDK replaces Get, update these boundary files and their tests. Typed
matching makes an incompatible transport change a compile-time concern rather
than silently losing authentication/error classification.
