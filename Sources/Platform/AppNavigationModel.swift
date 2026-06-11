import Foundation
import Observation

/// App-wide routing for platform entry points and commands: fixed destinations
/// (`AppRoute`) plus content deep links (`ContentLink`).
@MainActor
@Observable
final class AppNavigationModel {
    /// The app-wide instance. SwiftUI injects it via `@Environment`; non-view entry
    /// points (App Intents) route through the same instance so a Siri/Shortcuts
    /// invocation drives the foregrounded app's navigation.
    static let shared = AppNavigationModel()

    private(set) var route: AppRoute = .home
    private(set) var searchFocusRequest = 0

    /// Pending content deep link plus a monotonically increasing request token so the
    /// same link can fire twice in a row. The signed-in root consumes the pending link
    /// exactly once (`consumeContentLink`); links arriving while signed out stay pending
    /// until a session exists.
    private(set) var contentLinkRequest = 0
    private var pendingContentLink: ContentLink?

    func open(_ route: AppRoute) {
        if route == .search {
            searchFocusRequest += 1
            return
        }

        self.route = route
    }

    func open(url: URL) {
        if let route = AppRoute(url: url) {
            open(route)
        } else if let link = ContentLink(url: url) {
            open(link)
        }
    }

    func open(_ link: ContentLink) {
        pendingContentLink = link
        contentLinkRequest += 1
    }

    /// Returns the pending content link once, clearing it — so a re-mounted handler
    /// doesn't re-present a link that was already handled.
    func consumeContentLink() -> ContentLink? {
        defer { pendingContentLink = nil }
        return pendingContentLink
    }
}
