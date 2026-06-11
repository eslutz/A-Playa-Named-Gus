import Foundation

/// A deep link to a specific media item, alongside the fixed `AppRoute` destinations:
/// `gus://item/<id>` opens the item's detail surface; `gus://play/<id>` starts playback
/// (routed by media type — video player, audio player, book reader, photo viewer).
///
/// This is the shared primitive behind the content-aware Top Shelf, Handoff, Spotlight
/// results, Siri/App Intents, and screenshot automation. Item ids are Jellyfin item ids
/// on the active server; links to items the current session can't resolve fail softly.
enum ContentLink: Equatable {
    case item(id: String)
    case play(id: String)

    var url: URL {
        switch self {
        case let .item(id):
            return URL(string: "gus://item/\(id)")!
        case let .play(id):
            return URL(string: "gus://play/\(id)")!
        }
    }

    var itemID: String {
        switch self {
        case let .item(id), let .play(id):
            return id
        }
    }

    init?(url: URL) {
        guard url.scheme == "gus",
              let host = url.host(percentEncoded: false)
        else { return nil }

        let id = url.lastPathComponent
        guard !id.isEmpty, id != "/" else { return nil }

        switch host {
        case "item":
            self = .item(id: id)
        case "play":
            self = .play(id: id)
        default:
            return nil
        }
    }
}
