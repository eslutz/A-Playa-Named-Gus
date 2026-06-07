import Foundation

/// Fixed app-level destinations addressable from commands, keyboard shortcuts, and
/// platform entry points such as tvOS Top Shelf.
enum AppRoute: String, CaseIterable, Hashable, Identifiable {
    case home
    case libraries
    case search
    case settings

    var id: String {
        rawValue
    }

    var url: URL {
        URL(string: "gus://\(rawValue)")!
    }

    init?(url: URL) {
        guard url.scheme == "gus",
              let host = url.host(percentEncoded: false),
              let route = AppRoute(rawValue: host)
        else { return nil }

        self = route
    }
}
