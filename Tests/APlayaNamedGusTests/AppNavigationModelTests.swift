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

        model.open(.libraries)

        #expect(model.route == .libraries)
    }

    @Test("opening search increments the search focus token without changing route")
    func openingSearchRequestsSearchFocus() {
        let model = AppNavigationModel()

        model.open(.settings)
        #expect(!model.consumeSearchFocus())
        model.open(.search)
        let firstRequest = model.searchFocusRequest
        #expect(model.consumeSearchFocus())
        #expect(!model.consumeSearchFocus())
        model.open(.search)

        #expect(model.route == .settings)
        #expect(firstRequest == 1)
        #expect(model.searchFocusRequest == 2)
        #expect(model.consumeSearchFocus())
    }

    @Test("a focused scene's Find command preserves the other window's search and navigation")
    func searchFocusIsLocalToTheCommandWindow() {
        let downloadsWindow = RootNavigationState()
        let browsingWindow = RootNavigationState()
        downloadsWindow.selectSection(NavigationSectionPreference.downloadedID)
        downloadsWindow.paths[NavigationSectionPreference.downloadedID] = [.screen(.downloads)]
        browsingWindow.focusSearch()
        #expect(browsingWindow.globalSearch.typed.isPresented)
        #expect(downloadsWindow.paths[NavigationSectionPreference.downloadedID] == [.screen(.downloads)])
        #expect(downloadsWindow.pendingLocalSearchFocus == nil)
        downloadsWindow.focusSearch()
        #expect(downloadsWindow.paths[NavigationSectionPreference.downloadedID]?.isEmpty == true)
        #expect(downloadsWindow.pendingLocalSearchFocus == NavigationSectionPreference.downloadedID)
        #expect(browsingWindow.selectedSectionID == RootNavigationState.searchID)
    }

    @Test("opens supported URLs and ignores unsupported URLs")
    func opensSupportedURLsOnly() throws {
        let model = AppNavigationModel()

        model.open(url: AppRoute.home.url)
        try model.open(url: #require(URL(string: "https://example.com")))

        #expect(model.route == .home)
    }
}
