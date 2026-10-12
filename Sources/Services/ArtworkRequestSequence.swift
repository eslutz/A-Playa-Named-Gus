import Foundation

/// Preserve preference order while ensuring a failing URL is attempted only once.
enum ArtworkRequestSequence {
    static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }
}
