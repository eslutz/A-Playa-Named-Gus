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

#if os(visionOS)
    @MainActor
    @Suite("Vision tab navigation")
    struct VisionNavigationLayoutTests {
        @Test("Vision native tabs fit eight slots without losing destinations", arguments: [0, 7, 8, 9, 10])
        func nativeTabBudget(sectionCount: Int) {
            let ids = (0 ..< sectionCount).map { "section-\($0)" }
            let direct = RootNavigationState.visionDirectSectionIDs(ids)
            let overflow = ids.filter { !direct.contains($0) }
            let renderedTabCount = direct.count + (overflow.isEmpty ? 0 : 1)
            let reachable = direct + overflow
            #expect(renderedTabCount <= 8)
            #expect(reachable == ids)
            if sectionCount <= 8 {
                #expect(direct == ids)
                #expect(overflow.isEmpty)
            } else {
                #expect(direct.count == 7)
                #expect(!overflow.isEmpty)
            }
        }

        @Test("Vision preserves configured order across direct tabs and More")
        func configuredTabOrder() {
            let ids = ["home", "settings", "category.books", "downloaded", "category.photos", "libraries", "category.music", "playlists", "discover", "category.movies"]
            let direct = RootNavigationState.visionDirectSectionIDs(ids)
            let overflow = ids.filter { !direct.contains($0) }
            #expect(direct == ["home", "settings", "category.books", "downloaded", "category.photos", "libraries", "category.music"])
            #expect(overflow == ["playlists", "discover", "category.movies"])
        }

        @Test("Vision overflow routes preserve real section selection and history")
        func overflowRoutesRetainHistory() {
            let ids = ["home", "category.movies", "category.tvshows", "category.music", "category.books", "category.photos", "category.livetv", "libraries", "downloaded", "settings", "discover"]
            let direct = RootNavigationState.visionDirectSectionIDs(ids)
            let state = RootNavigationState()
            var homePath = NavigationPath()
            homePath.append(AppScreen.downloads)
            state.paths["home"] = homePath
            var settingsPath = NavigationPath()
            settingsPath.append(AppScreen.navigationSettings)
            state.paths["settings"] = settingsPath
            state.scrollAnchors = ["home": "recent-movies", "settings": "navigation"]
            for route in [AppRoute.libraries, .downloaded, .settings] {
                state.adopt(route)
                let selected = state.selectedSectionID
                state.reconcileVisionMoreSelection(sectionIDs: ids)
                #expect(!direct.contains(selected))
                #expect(state.selectedSectionID == selected)
            }
            state.adopt(.home)
            state.reconcileVisionMoreSelection(sectionIDs: ids)
            #expect(direct.contains(state.selectedSectionID))
            #expect(state.selectedSectionID == "home")
            state.selectedSectionID = RootNavigationState.moreID
            state.reconcileVisionMoreSelection(sectionIDs: ids)
            #expect(state.selectedSectionID == RootNavigationState.moreID)
            #expect(state.paths["home"]?.count == 1)
            #expect(state.paths["settings"]?.count == 1)
            #expect(state.scrollAnchors == ["home": "recent-movies", "settings": "navigation"])
        }

        @Test("Vision removes a stale More selection without clearing section history")
        func removingMoreRetainsHistory() {
            let ids = ["settings", "home", "downloaded", "libraries", "playlists", "category.music", "category.books", "discover"]
            let state = RootNavigationState()
            var path = NavigationPath()
            path.append(AppScreen.navigationSettings)
            state.paths["settings"] = path
            state.scrollAnchors["settings"] = "navigation"
            for count in [0, 7, 8] {
                let sections = Array(ids.prefix(count))
                state.selectedSectionID = RootNavigationState.moreID
                state.reconcileVisionMoreSelection(sectionIDs: sections)
                #expect(state.selectedSectionID == (sections.first ?? NavigationSectionPreference.homeID))
                #expect(state.paths["settings"]?.count == 1)
                #expect(state.scrollAnchors["settings"] == "navigation")
            }
            state.adopt(.settings)
            state.reconcileVisionMoreSelection(sectionIDs: ids)
            #expect(state.selectedSectionID == "settings")
            // Persisted selection can arrive after the sections are already resolved.
            state.selectedSectionID = RootNavigationState.moreID
            state.reconcileVisionMoreSelection(sectionIDs: ids)
            #expect(state.selectedSectionID == "settings")
            #expect(state.paths["settings"]?.count == 1)
            #expect(state.scrollAnchors["settings"] == "navigation")
        }
    }
#endif
