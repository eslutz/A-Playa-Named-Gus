# 0008: Media Provider Boundary

## Status

Accepted

## Context

A Playa Named Gus 1.0 ships with Jellyfin as the only production backend, but the app
should not spread Jellyfin DTOs, request builders, or provider conditionals through
SwiftUI features. The app also needs provider-scoped persistence so future backends can
coexist without Keychain or cache key collisions.

## Decision

Core browsing, detail, playback, download, and artwork flows use Gus-native domain models
(`MediaItem`, media source/stream metadata, provider-scoped credentials) and a
`MediaProviderSession` protocol. Jellyfin-specific SDK calls, DTO mapping, playback
reporting payloads, and download URL resolution stay behind `JellyfinMediaProviderSession`
and mapper types under `Sources/Providers/Jellyfin`.

Connect, sign-in, Quick Connect, and server discovery remain Jellyfin-specific entrypoints
for 1.0 because they are authentication/discovery flows for the only supported provider.
If another provider is added, it should supply a separate auth/discovery adapter and feed
the same signed-in `MediaProviderSession` contract.

## Consequences

- Feature stores and views operate on provider/domain contracts for media workflows.
- Existing Jellyfin Keychain accounts migrate from `serverID:userID` to
  `jellyfin:serverID:userID` on restore.
- Persisted Up Next and download records decode legacy Jellyfin DTO-shaped JSON into
  domain `MediaItem` values.
- Provider-specific capability differences should be expressed through provider
  capabilities or provider implementations, not feature-level `if Jellyfin` checks.
