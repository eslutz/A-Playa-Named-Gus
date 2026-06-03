import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("App navigation model")
struct AppNavigationModelTests {
    @Test("opens routes and records the latest fixed destination")
    func opensRoutes() {
        let model = AppNavigationModel()

        model.open(.settings)

        #expect(model.route == .settings)
    }

    @Test("opening search increments the search focus token")
    func openingSearchRequestsSearchFocus() {
        let model = AppNavigationModel()

        model.open(.search)
        let firstRequest = model.searchFocusRequest
        model.open(.search)

        #expect(model.route == .search)
        #expect(firstRequest == 1)
        #expect(model.searchFocusRequest == 2)
    }

    @Test("opens supported URLs and ignores unsupported URLs")
    func opensSupportedURLsOnly() throws {
        let model = AppNavigationModel()

        model.open(url: AppRoute.home.url)
        try model.open(url: #require(URL(string: "https://example.com")))

        #expect(model.route == .home)
    }
}
