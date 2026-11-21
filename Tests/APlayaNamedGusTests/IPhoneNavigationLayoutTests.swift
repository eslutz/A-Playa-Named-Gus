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
            state.paths["home"] = [.screen(.downloads)]
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
            state.paths[state.selectedSectionID] = [.screen(.navigationSettings)]
            state.sidebarVisibility = .detailOnly
            #expect(state.selectedSectionID == "category.music")
            #expect(state.paths["category.music"]?.count == 1)
            state.sidebarVisibility = .doubleColumn
            #expect(state.paths["category.music"]?.count == 1)
        }
    #endif

    @Test("native More pushes a section, retains its child when switching tabs, and pops back to the index")
    func moreSectionHistory() {
        let root = RootNavigationState()
        let ids = ["libraries", "settings"]
        root.selectSection(RootNavigationState.moreID)
        root.rememberOverflowSelection(in: ids)
        root.morePathBinding(overflowIDs: ids).wrappedValue = [.section("settings")]
        #expect(root.selectedSectionID == "settings")
        let settings = root.morePathBinding(overflowIDs: ids)
        settings.wrappedValue.append(.screen(.navigationSettings))
        #expect(root.paths["settings"] == [.screen(.navigationSettings)])
        root.selectSection("home")
        settings.wrappedValue = []
        root.selectMoreTab(overflowIDs: ids)
        #expect(root.selectedSectionID == "settings")
        #expect(root.morePathBinding(overflowIDs: ids).wrappedValue == [.section("settings"), .screen(.navigationSettings)])
        root.morePathBinding(overflowIDs: ids).wrappedValue.removeLast()
        #expect(root.selectedSectionID == "settings")
        root.morePathBinding(overflowIDs: ids).wrappedValue.removeLast()
        #expect(root.selectedSectionID == RootNavigationState.moreID)
        #expect(root.paths["settings"] == [])
        root.morePathBinding(overflowIDs: ids).wrappedValue = [.section("settings")]
        #expect(root.morePathBinding(overflowIDs: ids).wrappedValue == [.section("settings")])
    }

    @Test("promotion from More to a direct tab or sidebar preserves the section's path")
    func overflowPromotion() {
        let root = RootNavigationState()
        root.adopt(.settings)
        root.paths["settings"] = [.screen(.downloads)]
        root.rememberOverflowSelection(in: ["settings", "libraries"])
        let previous = root.morePathBinding(overflowIDs: ["settings", "libraries"])
        root.rememberOverflowSelection(in: ["libraries"])
        previous.wrappedValue = []
        #expect(root.selectedSectionID == "settings")
        #expect(root.pathBinding(for: "settings").wrappedValue == [.screen(.downloads)])
        root.rememberOverflowSelection(in: ["settings"])
        let compact = root.morePathBinding(overflowIDs: ["settings"])
        root.useSidebar()
        compact.wrappedValue = []
        #expect(root.paths["settings"] == [.screen(.downloads)])
    }

    @Test("Settings child pages survive the transition from More to the sidebar and back")
    func settingsChildrenRetainHistory() {
        #if os(tvOS)
            let screens: [AppScreen] = [.seerrSettings, .clientLogs]
        #else
            let screens: [AppScreen] = [.seerrSettings, .clientLogs, .libraryIntelligence]
        #endif
        let root = RootNavigationState()
        let settings = NavigationSectionPreference.settingsID
        root.selectSection(RootNavigationState.moreID)
        root.rememberOverflowSelection(in: [settings])
        root.morePathBinding(overflowIDs: [settings]).wrappedValue = [.section(settings)]

        for screen in screens {
            let compact = root.morePathBinding(overflowIDs: [settings])
            compact.wrappedValue.append(.screen(screen))
            root.useSidebar()
            compact.wrappedValue = []
            #expect(root.pathBinding(for: settings).wrappedValue == [.screen(screen)])
            root.rememberOverflowSelection(in: [settings])
            let restored = root.morePathBinding(overflowIDs: [settings])
            #expect(restored.wrappedValue == [.section(settings), .screen(screen)])
            restored.wrappedValue.removeLast()
            #expect(restored.wrappedValue == [.section(settings)])
        }
    }

    @Test("a deep link can push onto the More index independently of section history")
    func moreIndexDeepLink() {
        let root = RootNavigationState()
        root.selectSection(RootNavigationState.moreID)
        root.rememberOverflowSelection(in: ["settings"])
        let item = GusRoute.item(ItemRef(item: MediaItem(id: "movie", type: .movie)))
        root.paths[RootNavigationState.moreID] = [item]
        let more = root.morePathBinding(overflowIDs: ["settings"])
        #expect(more.wrappedValue == [item])
        more.wrappedValue.removeLast()
        #expect(more.wrappedValue.isEmpty)
        #expect(root.selectedSectionID == RootNavigationState.moreID)
    }

    @Test("only a resolved library listing can discard a restored hidden section")
    func hiddenSectionSelection() {
        let root = RootNavigationState()
        root.selectSection("category.books")
        root.reconcileTabSelection(sectionIDs: ["home", "settings"], overflowIDs: ["settings"], librariesLoaded: false)
        #expect(root.selectedSectionID == "category.books")
        root.reconcileTabSelection(sectionIDs: ["home", "settings"], overflowIDs: ["settings"], librariesLoaded: true)
        #expect(root.selectedSectionID == RootNavigationState.moreID)
        root.morePathBinding(overflowIDs: ["settings"]).wrappedValue = [.section("settings")]
        #expect(root.selectedSectionID == "settings")
    }

    @Test("keyword selection records one push and leaves history alone during restoration or Back")
    func nativeKeywordSelection() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = SearchHistoryStore(scope: .init(serverID: "server", userID: "user"), defaults: defaults)
        let root = RootNavigationState(searchHistory: history)
        let search = RootNavigationState.searchID
        root.selectSection(search)
        root.editSearchText("advent")
        let ref = ItemRef(item: MediaItem(id: "genre", name: "Adventure", type: .genre))
        let route = GusRoute.searchResult(ref, query: "advent")
        let selection = root.pathBinding(for: search)
        selection.wrappedValue.append(route)
        #expect(history.entries == [.related(.init(kind: .genre, id: "genre", name: "Adventure")), .typed("advent")])
        history.clear()
        selection.wrappedValue = [route]
        #expect(history.entries.isEmpty)
        selection.wrappedValue.removeLast()
        root.paths[search] = [route]
        #expect(history.entries.isEmpty)
    }

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
        private func reconcile(_ root: RootNavigationState, sections: [String]) {
            let direct = Set(RootNavigationState.visionDirectSectionIDs(sections))
            root.reconcileTabSelection(sectionIDs: sections, overflowIDs: sections.filter { !direct.contains($0) }, librariesLoaded: true)
        }

        @Test("Vision native tabs fit eight slots without losing destinations", arguments: [0, 7, 8, 9, 10])
        func nativeTabBudget(sectionCount: Int) {
            let ids = (0 ..< sectionCount).map { "section-\($0)" }
            let direct = RootNavigationState.visionDirectSectionIDs(ids)
            let overflow = ids.filter { !direct.contains($0) }
            let renderedTabCount = 1 + direct.count + (overflow.isEmpty ? 0 : 1)
            let reachable = direct + overflow
            #expect(renderedTabCount <= 8)
            #expect(reachable == ids)
            if sectionCount <= 7 {
                #expect(direct == ids)
                #expect(overflow.isEmpty)
            } else {
                #expect(direct.count == 6)
                #expect(!overflow.isEmpty)
            }
        }

        @Test("Vision preserves configured order across direct tabs and More")
        func configuredTabOrder() {
            let ids = ["home", "settings", "category.books", "downloaded", "category.photos", "libraries", "category.music", "playlists", "discover", "category.movies"]
            let direct = RootNavigationState.visionDirectSectionIDs(ids)
            let overflow = ids.filter { !direct.contains($0) }
            #expect(direct == ["home", "settings", "category.books", "downloaded", "category.photos", "libraries"])
            #expect(overflow == ["category.music", "playlists", "discover", "category.movies"])
        }

        @Test("Vision overflow routes preserve real section selection and history")
        func overflowRoutesRetainHistory() {
            let ids = ["home", "category.movies", "category.tvshows", "category.music", "category.books", "category.photos", "category.livetv", "libraries", "downloaded", "settings", "discover"]
            let direct = RootNavigationState.visionDirectSectionIDs(ids)
            let state = RootNavigationState()
            state.paths["home"] = [.screen(.downloads)]
            state.paths["settings"] = [.screen(.navigationSettings)]
            state.scrollAnchors = ["home": "recent-movies", "settings": "navigation"]
            for route in [AppRoute.libraries, .downloaded, .settings] {
                state.adopt(route)
                let selected = state.selectedSectionID
                reconcile(state, sections: ids)
                #expect(!direct.contains(selected))
                #expect(state.selectedSectionID == selected)
            }
            state.adopt(.home)
            reconcile(state, sections: ids)
            #expect(direct.contains(state.selectedSectionID))
            #expect(state.selectedSectionID == "home")
            state.selectedSectionID = RootNavigationState.moreID
            reconcile(state, sections: ids)
            #expect(state.selectedSectionID == RootNavigationState.moreID)
            #expect(state.paths["home"]?.count == 1)
            #expect(state.paths["settings"]?.count == 1)
            #expect(state.scrollAnchors == ["home": "recent-movies", "settings": "navigation"])
        }

        @Test("Vision removes a stale More selection without clearing section history")
        func removingMoreRetainsHistory() {
            let ids = ["settings", "home", "downloaded", "libraries", "playlists", "category.music", "category.books", "discover"]
            let state = RootNavigationState()
            state.paths["settings"] = [.screen(.navigationSettings)]
            state.scrollAnchors["settings"] = "navigation"
            for count in [0, 6, 7] {
                let sections = Array(ids.prefix(count))
                state.selectedSectionID = RootNavigationState.moreID
                reconcile(state, sections: sections)
                #expect(state.selectedSectionID == (sections.first ?? NavigationSectionPreference.homeID))
                #expect(state.paths["settings"]?.count == 1)
                #expect(state.scrollAnchors["settings"] == "navigation")
            }
            state.adopt(.settings)
            reconcile(state, sections: ids)
            #expect(state.selectedSectionID == "settings")
            // Persisted selection can arrive after the sections are already resolved.
            state.selectedSectionID = RootNavigationState.moreID
            reconcile(state, sections: Array(ids.prefix(7)))
            #expect(state.selectedSectionID == "settings")
            #expect(state.paths["settings"]?.count == 1)
            #expect(state.scrollAnchors["settings"] == "navigation")
        }
    }
#endif

@MainActor
@Suite("Related search navigation")
struct RelatedSearchNavigationTests {
    private let horror = RelatedSearch(kind: .genre, id: "genre-id", name: "Horror")
    private let movie = ItemRef(item: MediaItem(id: "movie", name: "The Lantern House", type: .movie))

    @Test func nativeBackRestoresOnlyTheOriginatingDetailAndReleasesItsResults() throws {
        let root = RootNavigationState()
        let origin = root.selectedSectionID
        let viewport = DetailScrollLocation(key: "detail:movie", y: 245)
        root.paths[origin] = [.item(movie)]
        root.openRelatedSearch(horror, viewport: viewport)
        let results = try #require(root.relatedResults.values.first)
        #expect(results.resolved == horror)
        #expect(root.selectedSectionID == origin)
        #expect(root.paths[origin] == [.item(movie), .related(results.id)])
        #expect(root.showsSearchResults(results.viewport))
        root.selectSection(RootNavigationState.searchID)
        #expect(!root.showsSearchResults(results.viewport))
        root.selectSection(origin)
        root.pathBinding(for: origin).wrappedValue = [.item(movie)]
        #expect(root.returningDetailViewport?.location == viewport)
        #expect(root.relatedResults.isEmpty)
    }

    @Test func relatedFilterLeavesTheUnderlyingSearchDraftAndResultsIntact() throws {
        let root = RootNavigationState()
        let search = RootNavigationState.searchID
        root.selectSection(search)
        root.editSearchText("Lantern")
        let typedViewport = root.globalSearch.typed.viewport
        #expect(root.showsSearchResults(typedViewport))
        root.paths[search] = [.searchResult(movie, query: "Lantern")]
        root.openRelatedSearch(horror)
        let results = try #require(root.relatedResults.values.first)
        root.selectSection(NavigationSectionPreference.homeID)
        root.selectSection(search)
        #expect(root.showsSearchResults(results.viewport))
        #expect(!root.showsSearchResults(typedViewport))
        root.pathBinding(for: search).wrappedValue = [.searchResult(movie, query: "Lantern")]
        #expect(root.globalSearch.text == "Lantern")
        #expect(root.paths[search]?.count == 1)
        root.pathBinding(for: search).wrappedValue = []
        #expect(root.showsSearchResults(typedViewport))
        #expect(root.relatedResults.isEmpty)
    }

    @Test func nestedSheetFiltersOwnIndependentPagesAndBackMenuCanPopSeveral() throws {
        let root = RootNavigationState()
        let firstViewport = DetailScrollLocation(key: "detail:movie", y: 125)
        let secondViewport = DetailScrollLocation(key: "detail:movie", y: 745)
        root.detailItem = movie
        root.openRelatedSearch(horror, viewport: firstViewport)
        let first = try #require(root.relatedResults.values.first)
        first.viewport.distanceFromTop = 680
        root.sheetPath.append(.item(movie))
        root.openRelatedSearch(horror, viewport: secondViewport)
        let second = try #require(root.relatedResults.values.first { $0.id != first.id })
        #expect(root.sheetPath == [.related(first.id), .item(movie), .related(second.id)])
        #expect(root.detailItem == movie && root.paths.isEmpty)
        #expect(first.storeKey != second.storeKey)
        #expect(second.viewport.distanceFromTop == nil)
        root.sheetPath.removeLast()
        #expect(root.returningDetailViewport?.location == secondViewport)
        #expect(root.relatedResults.count == 1 && root.relatedResults[first.id] === first)
        root.sheetPath.removeLast()
        #expect(root.returningDetailViewport == nil && root.showsSearchResults(first.viewport))
        #expect(first.viewport.distanceFromTop == 680)
        root.sheetPath.append(.item(movie))
        root.sheetPath = []
        #expect(root.detailItem == movie && root.returningDetailViewport?.location == firstViewport)
        #expect(root.relatedResults.isEmpty)
    }

    @Test func identicalDetailsInTheSectionSheetAndNestedPageConsumeOnlyTheirOwnReturn() throws {
        let root = RootNavigationState()
        let section = root.selectedSectionID
        let key = "detail:" + movie.id
        root.paths[section] = [.item(movie)]
        let sectionPage = try #require(root.detailPosition(in: .section(section)))
        root.rememberDetailAnchor("metadata", at: sectionPage, key: key)
        root.presentDetail(movie)
        let sheetRoot = try #require(root.detailPosition(in: .sheet(itemID: movie.id)))
        root.rememberDetailAnchor("cast", at: sheetRoot, key: key)
        root.sheetPath.append(.item(movie))
        let nestedPage = try #require(root.detailPosition(in: .sheet(itemID: movie.id)))
        root.rememberDetailAnchor("recommended", at: nestedPage, key: key)
        let offset = DetailScrollLocation(key: key, y: 745)
        root.openRelatedSearch(horror, viewport: offset)
        root.sheetPath.removeLast()
        #expect(root.takeReturningViewport(at: sectionPage, key: key) == nil)
        #expect(root.takeReturningViewport(at: sheetRoot, key: key) == nil)
        #expect(root.takeReturningViewport(at: nestedPage, key: key) == offset)
        #expect(root.takeReturningViewport(at: nestedPage, key: key) == nil)
        root.sheetPath.removeLast()
        #expect(root.detailAnchor(at: nestedPage, key: key) == nil)
        #expect(root.detailAnchor(at: sheetRoot, key: key) == "cast")
        root.detailItem = nil
        #expect(root.detailAnchor(at: sheetRoot, key: key) == nil)
        #expect(root.detailAnchor(at: sectionPage, key: key) == "metadata")
    }

    @Test func closingDeepLinkReleasesOnlyItsFilters() throws {
        let root = RootNavigationState()
        root.openRelatedSearch(horror)
        let sectionResults = try #require(root.relatedResults.values.first)
        root.detailItem = movie
        root.openRelatedSearch(horror, viewport: .init(key: "detail:movie", y: 160))
        root.detailItem = nil
        #expect(root.sheetPath.isEmpty && root.relatedResults.count == 1)
        #expect(root.showsSearchResults(sectionResults.viewport))
        #expect(root.returningDetailViewport == nil)
    }

    @Test func recentRelatedSearchReplaysAsANewPushAndOnlyResolvedFiltersAreRecorded() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = SearchHistoryStore(scope: .init(serverID: "s", userID: "u"), defaults: defaults)
        let root = RootNavigationState(searchHistory: history)
        let origin = root.selectedSectionID
        root.openRelatedSearch(.init(kind: .studio, name: "Unknown"))
        #expect(history.entries.isEmpty)
        root.paths[origin] = []
        root.openRelatedSearch(horror)
        let original = try #require(root.relatedResults.values.first)
        root.paths[origin] = []
        root.selectSection(RootNavigationState.searchID)
        try root.replaySearch(#require(history.entries.first))
        let reopened = try #require(root.relatedResults.values.first)
        #expect(original.id != reopened.id && reopened.resolved == horror)
        #expect(root.paths[RootNavigationState.searchID] == [.related(reopened.id)])
        root.pathBinding(for: RootNavigationState.searchID).wrappedValue = []
        #expect(root.globalSearch.text.isEmpty && history.entries == [.related(horror)])
    }
}
