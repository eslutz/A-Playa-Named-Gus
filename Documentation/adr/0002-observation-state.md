# ADR 0002: Observation for app and feature state

## Status

Accepted

## Context

The app needs shared session state and feature-specific loading state, but the project
mandate favors SwiftUI-native mechanisms and avoids adding a dependency injection container
or Combine-based view model layer.

## Decision

State stores are `@Observable @MainActor` classes injected with SwiftUI environment values.
`AppModel` owns root session state, while feature stores such as `HomeStore`,
`LibraryStore`, and `PlaybackStore` are created inside views once environment dependencies
are available.

## Consequences

The architecture remains small and idiomatic for modern SwiftUI. Store mutations stay on
the main actor, and feature views avoid custom coordinators or a separate DI framework.
