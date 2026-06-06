import Foundation
@testable import Gus
import Testing

@Suite("App routes")
struct AppRouteTests {
    @Test("parses supported gus URLs")
    func parsesSupportedURLs() throws {
        #expect(try AppRoute(url: #require(URL(string: "gus://home"))) == .home)
        #expect(try AppRoute(url: #require(URL(string: "gus://search"))) == .search)
        #expect(try AppRoute(url: #require(URL(string: "gus://settings"))) == .settings)
    }

    @Test("round trips through URL values")
    func roundTripsThroughURLValues() throws {
        for route in AppRoute.allCases {
            #expect(AppRoute(url: route.url) == route)
        }
    }

    @Test("rejects unsupported schemes and hosts")
    func rejectsUnsupportedURLs() throws {
        #expect(try AppRoute(url: #require(URL(string: "https://home"))) == nil)
        #expect(try AppRoute(url: #require(URL(string: "gus://library"))) == nil)
    }
}
