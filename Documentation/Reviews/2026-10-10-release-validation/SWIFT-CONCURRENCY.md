# Swift concurrency boundaries

The app uses complete concurrency checking. Watch, Top Shelf, tvOS and visionOS use
Swift 6 language mode; iOS and macOS remain in Swift 5 mode pending the boundaries
below. Configuration alone does not prove a warning-free build.

- Readium's asynchronous asset retrieval, publication opening and navigation APIs
  use non-Sendable objects in the MainActor reader model. Resolve upstream isolation
  or introduce a reviewed confined service before migrating the iOS target; an
  unchecked conformance alone is not proof of safety.
- SwiftUI's `DeclaredAgeRangeAction` has an unannotated asynchronous boundary on
  iOS/macOS. The settings flow permits one request at a time and retains a manual
  content-limit fallback. Entitlement and device acceptance remain separate.
- Preserve the documented ownership around download delegate locks, callback bridges,
  cancellation and the ordered audio-session queue when changing those systems.

The deployment floor is OS 26.0; newer APIs require availability checks. Exact
minimum-runtime execution remains a separate acceptance gate.
