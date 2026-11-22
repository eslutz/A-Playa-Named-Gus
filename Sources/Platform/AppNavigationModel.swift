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

    let playerWindows = PlayerWindowRequests()
    private(set) var route: AppRoute = .home
    /// Explicit routes must also be handled when they repeat the last routed value.
    private(set) var routeRequest = 0
    private(set) var searchFocusRequest = 0
    private var handledSearchFocusRequest = 0
    #if !os(tvOS)
        private var pendingSharePlay: (itemID: String, lease: SessionLease)?
        private(set) var sharePlayRequest = 0

        func prepareSharePlay(itemID: String, for session: SessionStore) {
            guard session.isActive else { return }
            pendingSharePlay = (itemID, session.lease)
            sharePlayRequest += 1
        }

        func consumeSharePlay(for lease: SessionLease) -> String? {
            defer { pendingSharePlay = nil }
            guard let pendingSharePlay, pendingSharePlay.lease == lease else { return nil }
            return pendingSharePlay.itemID
        }
    #endif
    private var pendingLibrarySearch: (term: String, lease: SessionLease)?

    /// Pending content deep link plus a monotonically increasing request token so the
    /// same link can fire twice in a row. The signed-in root consumes the pending link
    /// exactly once (`consumeContentLink`); links arriving while signed out stay pending
    /// until a session exists.
    private(set) var contentLinkRequest = 0
    private var pendingContentLink: (link: ContentLink, account: SessionCredential?, lease: SessionLease?)?

    func open(_ route: AppRoute) {
        if route == .search {
            pendingLibrarySearch = nil
            searchFocusRequest += 1
            return
        }

        self.route = route
        routeRequest += 1
    }

    func openLibrarySearch(_ term: String, for session: SessionStore) {
        guard session.isActive else { return }
        pendingLibrarySearch = (term, session.lease)
        searchFocusRequest += 1
    }

    func consumeLibrarySearch(for lease: SessionLease) -> String? {
        defer { pendingLibrarySearch = nil }
        guard let search = pendingLibrarySearch, search.lease == lease else { return nil }
        return search.term
    }

    func consumeSearchFocus() -> Bool {
        guard handledSearchFocusRequest != searchFocusRequest else { return false }
        handledSearchFocusRequest = searchFocusRequest
        return true
    }

    func open(url: URL) {
        #if os(tvOS)
            if url.scheme == "gus", url.host == "top-shelf" {
                if let selection = TopShelfSnapshot.load()?.selection(for: url) {
                    let account = SessionCredential(serverID: selection.serverID, userID: selection.userID)
                    let link: ContentLink = selection.play
                        ? .play(id: selection.id, serverID: selection.serverID, provider: .jellyfin)
                        : .item(id: selection.id, serverID: selection.serverID, provider: .jellyfin)
                    open(link, account: account)
                } else {
                    open(.home)
                }
                return
            }
        #endif
        if let route = AppRoute(url: url) {
            open(route)
        } else if let link = ContentLink(url: url) {
            open(link)
        }
    }

    func open(_ link: ContentLink) {
        pendingContentLink = (link, nil, nil)
        contentLinkRequest += 1
    }

    /// Intent work belongs to the exact credential installation that resolved the item.
    func open(_ link: ContentLink, for session: SessionStore) {
        guard session.isActive else { return }
        pendingContentLink = (link, session.lease.credential, session.lease)
        contentLinkRequest += 1
    }

    /// System donations can arrive before Keychain restore. Carry their original
    /// account through to consumption without putting user IDs into shared URLs.
    func open(_ link: ContentLink, account: SessionCredential) {
        pendingContentLink = (link, account, nil)
        contentLinkRequest += 1
    }

    /// Returns the pending content link once, clearing it — so a re-mounted handler
    /// doesn't re-present a link that was already handled.
    func consumeContentLink(for lease: SessionLease? = nil) -> ContentLink? {
        defer { pendingContentLink = nil }
        guard let pendingContentLink,
              pendingContentLink.account == nil || pendingContentLink.account == lease?.credential,
              pendingContentLink.lease == nil || pendingContentLink.lease == lease else { return nil }
        return pendingContentLink.link
    }
}
