# Swift concurrency review

Xcode 27.0 / Swift 6.4, with complete checking on every app and test target.
Target-specific settings in `project.yml` select Swift 6 for Watch, Top Shelf and the
tvOS/visionOS app. iOS/macOS remain in Swift 5 mode with complete checking because
Readium's async non-Sendable publication APIs and Apple's Declared Age Range action
lack the isolation contract needed for a safe full-target migration.
Final compiler results belong in `VALIDATION.md`; configuration alone is not proof.

## Ownership changes

- Retry operations inherit the caller's actor through `isolated (any Actor)? = #isolation`.
  A regression checks MainActor ownership across retry and suspension.
- The MainActor provider contract is Sendable. Home task groups await that actor without
  assigning an isolated child closure that the region checker cannot model.
- Watch relay state is MainActor-owned; its delegate hops to that actor and reads its
  own payload. The receiver and MetricKit collector have immutable Sendable storage.
- Diagnostic summary read/modify/write is serialized, including concurrent MetricKit
  deliveries. A forty-writer regression verifies no lost records.
- Download delegate maps and callbacks use one lock; cached URLSession creation uses
  a separate lock. Its Foundation callback adapter remains explicitly unchecked
  Sendable with these documented invariants, rather than claiming actor isolation.
- The socket receive function is Sendable. Notification/display-link bridges extract
  Sendable error/time values before entering MainActor, rather than transferring the
  Foundation notification or CADisplayLink.
- Shared With You's installed SDK header guarantees its highlight completion on the
  main queue. The narrow adapter consumes the highlight there, returns only Void
  through its continuation, and ignores cancelled deliveries. The local
  `nonisolated(unsafe)` highlight binding documents the unannotated SDK guarantee;
  the delegate reads its own center after the actor hop. No blanket import suppression.
- Detail loads reject cancelled successful results and stale related-content results.
  Cancelled Sign In, Live TV and Watch loads return to idle, allowing re-entry.
- Audio/video session operations share a MainActor-owned ordered queue. Native OS 27
  asynchronous activation/deactivation and blocking legacy category/session calls run
  off MainActor. A suspension regression verifies activation → dismissal → replacement
  order; preparation generations are checked again after activation completes.
- Test URLProtocol adapters serialize shared response state and lifecycle cancellation.
  Their narrowly documented unchecked boundaries are test fixtures, not app-wide
  concurrency exemptions. The release validation records sanitizer coverage separately.

## Remaining migration boundaries

Readium `AssetRetriever.retrieve`, `PublicationOpener.open`, `Publication.tableOfContents`
and `Publication.locate` are async APIs on non-Sendable objects used by the MainActor
reader model. Do not assert that adding an unchecked conformance proves the toolkit
safe. Resolve upstream isolation or introduce a reviewed, confined reader service before
switching the iOS target to Swift 6.

SwiftUI's `DeclaredAgeRangeAction.callAsFunction` has a similar unannotated asynchronous
boundary on iOS/macOS. The settings action already permits one request at a time and
falls back to the manual content limit when unavailable. The actual service requires
Apple's entitlement and device acceptance; compiler checking cannot grant either.

Modern APIs do not require raising deployment targets to OS 27. Availability guards
retain iOS/tvOS 18, macOS 15, Watch 11 and Vision 2 support. Those minimum runtimes are
not installed here and remain an execution gate.

References: [Swift migration guide](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/),
[Apple SwiftUI](https://developer.apple.com/documentation/swiftui),
[Readium toolkit](https://github.com/readium/swift-toolkit).
