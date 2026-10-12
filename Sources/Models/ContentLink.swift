import Foundation

/// A deep link to a specific media item, alongside the fixed `AppRoute` destinations:
/// `gus://item/<id>` opens the item's detail surface; `gus://play/<id>` starts playback
/// (routed by media type — video player, audio player, book reader, photo viewer).
/// Universal Links use the same route shape at `https://gus.ericslutz.dev/item/<id>`
/// and `/play/<id>` so Messages/Shared with You can hand off content through the
/// system universal-link pipeline.
///
/// This is the shared primitive behind the content-aware Top Shelf, Handoff, Spotlight
/// results, Siri/App Intents, Shared with You, and screenshot automation. Item ids are
/// Jellyfin item ids on the active server; links to items the current session can't
/// resolve fail softly.
enum ContentLink: Hashable, Sendable {
    static let universalLinkHost = "gus.ericslutz.dev"

    case item(id: String, serverID: String? = nil, provider: MediaProviderKind? = nil)
    case play(id: String, serverID: String? = nil, provider: MediaProviderKind? = nil)

    var url: URL {
        makeURL(universal: false)
    }

    var universalURL: URL {
        makeURL(universal: true)
    }

    var itemID: String {
        switch self {
        case let .item(id, _, _), let .play(id, _, _): return id
        }
    }

    var serverID: String? {
        switch self {
        case let .item(_, serverID, _), let .play(_, serverID, _): return serverID
        }
    }

    var provider: MediaProviderKind? {
        switch self {
        case let .item(_, _, provider), let .play(_, _, provider): return provider
        }
    }

    func accepts(server: ServerConnection) -> Bool {
        (serverID == nil || serverID == server.id) && (provider == nil || provider == server.providerKind)
    }

    private func makeURL(universal: Bool) -> URL {
        let action: String
        switch self { case .item: action = "item"; case .play: action = "play" }
        var components = URLComponents()
        components.scheme = universal ? "https" : "gus"
        components.host = universal ? Self.universalLinkHost : action
        components.path = universal ? "/\(action)/\(itemID)" : "/\(itemID)"
        if let serverID, let provider {
            components.queryItems = [URLQueryItem(name: "server", value: serverID), URLQueryItem(name: "provider", value: provider.rawValue)]
        }
        return components.url!
    }

    init?(url: URL) {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let serverID = query.first { $0.name == "server" }?.value
        let providerText = query.first { $0.name == "provider" }?.value
        let provider = providerText.flatMap(MediaProviderKind.init(rawValue:))
        guard (serverID == nil && providerText == nil) || (serverID?.isEmpty == false && provider != nil) else { return nil }
        if url.scheme == "gus" {
            guard let host = url.host(percentEncoded: false) else { return nil }

            let id = url.lastPathComponent
            guard !id.isEmpty, id != "/" else { return nil }

            switch host {
            case "item":
                self = .item(id: id, serverID: serverID, provider: provider)
            case "play":
                self = .play(id: id, serverID: serverID, provider: provider)
            default:
                return nil
            }
            return
        }

        guard url.scheme == "https",
              url.host(percentEncoded: false) == Self.universalLinkHost
        else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2 else { return nil }

        switch components[0] {
        case "item":
            self = .item(id: components[1], serverID: serverID, provider: provider)
        case "play":
            self = .play(id: components[1], serverID: serverID, provider: provider)
        default:
            return nil
        }
    }
}
