import Foundation
@testable import Gus
import Testing

@Suite("URL normalization")
struct URLNormalizationTests {
    @Test("adds http scheme when the user enters only a host")
    func addsDefaultScheme() throws {
        let url = try AppModel.normalizeURL("jellyfin.local")

        #expect(url.absoluteString == "http://jellyfin.local")
    }

    @Test("trims whitespace and trailing slashes")
    func trimsWhitespaceAndTrailingSlashes() throws {
        let url = try AppModel.normalizeURL("  https://jellyfin.example.com///  ")

        #expect(url.absoluteString == "https://jellyfin.example.com")
    }

    @Test("rejects input without a URL host")
    func rejectsInvalidInput() {
        #expect(throws: AppModel.ConnectError.self) {
            try AppModel.normalizeURL("https://")
        }
    }
}
