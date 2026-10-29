import Foundation
@testable import Gus
import SwiftUI
import Testing

@MainActor
@Suite("iPhone design navigation")
struct IPhoneNavigationLayoutTests {
    #if os(iOS)
        @Test("global Search routing preserves the originating section history")
        func searchRetainsSectionHistory() {
            let state = RootNavigationState()
            var path = NavigationPath()
            path.append(AppScreen.downloads)
            state.paths["home"] = path
            state.scrollAnchors["home"] = "recent-movies"
            state.adopt(.search)
            #expect(state.selectedSectionID == RootNavigationState.searchID)
            #expect(state.paths["home"]?.count == 1)
            #expect(state.scrollAnchors["home"] == "recent-movies")
            state.adopt(.home)
            #expect(state.selectedSectionID == "home")
            #expect(state.paths["home"]?.count == 1)
        }

        @Test("sidebar collapse leaves section paths and selection intact")
        func collapseRetainsNavigation() {
            let state = RootNavigationState()
            state.selectedSectionID = "category.music"
            var path = NavigationPath()
            path.append(AppScreen.navigationSettings)
            state.paths[state.selectedSectionID] = path
            state.sidebarVisibility = .detailOnly
            #expect(state.selectedSectionID == "category.music")
            #expect(state.paths["category.music"]?.count == 1)
            state.sidebarVisibility = .doubleColumn
            #expect(state.paths["category.music"]?.count == 1)
        }
    #endif

    @Test("new accounts prioritize Home, Movies and Shows without losing remaining destinations")
    func defaultTabs() {
        let ids = ["home", "downloaded", "libraries", "playlists", "category.movies", "category.tvshows", "settings"]
        #expect(RootNavigationState.iPhoneDirectSectionIDs(ids, usesSavedOrder: false) == ["home", "category.movies", "category.tvshows"])
    }

    @Test("an account's saved order controls the three direct tabs")
    func customizedTabs() {
        let ids = ["home", "category.books", "downloaded", "libraries", "settings"]
        #expect(RootNavigationState.iPhoneDirectSectionIDs(ids, usesSavedOrder: true) == Array(ids.prefix(3)))
    }

    @Test("missing or hidden media categories fall back to available sections")
    func unavailableCategories() {
        let ids = ["home", "downloaded", "libraries", "settings"]
        #expect(RootNavigationState.iPhoneDirectSectionIDs(ids, usesSavedOrder: false) == ["home", "downloaded", "libraries"])
        #expect(RootNavigationState.iPhoneDirectSectionIDs(["home"], usesSavedOrder: false) == ["home"])
    }
}
