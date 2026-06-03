import Foundation
import Observation

/// App-wide fixed-destination routing for platform entry points and commands.
@MainActor
@Observable
final class AppNavigationModel {
    private(set) var route: AppRoute = .home
    private(set) var searchFocusRequest = 0

    func open(_ route: AppRoute) {
        self.route = route

        if route == .search {
            searchFocusRequest += 1
        }
    }

    func open(url: URL) {
        guard let route = AppRoute(url: url) else { return }
        open(route)
    }
}
