import Foundation
import Testing

private final class RepositoryFixtureBundleMarker: NSObject {}

/// Exact build-time inputs travel with the test bundle to separate Cloud workers.
enum RepositoryTestFixtures {
    static func url(for path: String) throws -> URL {
        let bundle = Bundle(for: RepositoryFixtureBundleMarker.self)
        let root = try #require(bundle.resourceURL)
        let url = root.appendingPathComponent("RepositoryFixtures").appendingPathComponent(path)
        try #require(FileManager.default.fileExists(atPath: url.path), "Missing packaged test fixture: \(path)")
        return url
    }
}
