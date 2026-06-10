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

    @Test("schemeless addresses try https before http")
    func schemelessTriesHTTPSFirst() throws {
        let candidates = try AppModel.candidateURLs(for: "jellyfin.example.com:8096")

        #expect(candidates.map(\.absoluteString) == [
            "https://jellyfin.example.com:8096",
            "http://jellyfin.example.com:8096",
        ])
    }

    @Test("an explicit scheme is honored as the only candidate")
    func explicitSchemeIsSingleCandidate() throws {
        #expect(try AppModel.candidateURLs(for: "http://192.168.1.50:8096").map(\.absoluteString) == ["http://192.168.1.50:8096"])
        #expect(try AppModel.candidateURLs(for: "https://jellyfin.example.com").map(\.absoluteString) == ["https://jellyfin.example.com"])
    }
}
