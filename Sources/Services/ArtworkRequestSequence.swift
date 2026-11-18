import Foundation

/// One ordered set of native image requests. A late failure can advance only
/// the URL actually on screen, and the final failure is reported just once.
struct ArtworkRequestSequence {
    enum FailureResult { case ignored, advanced, exhausted }

    let urls: [URL]
    private var index = 0
    private var exhausted = false

    init(_ urls: [URL]) {
        self.urls = Self.unique(urls)
    }

    var currentURL: URL? {
        urls.indices.contains(index) ? urls[index] : nil
    }

    mutating func failed(_ url: URL) -> FailureResult {
        guard currentURL == url, !exhausted else { return .ignored }
        guard index + 1 < urls.count else {
            exhausted = true
            return .exhausted
        }
        index += 1
        return .advanced
    }

    static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }
}
