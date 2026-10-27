import Foundation
@testable import Gus
import Testing

@MainActor
@Suite("iPhone design navigation")
struct IPhoneNavigationLayoutTests {
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
