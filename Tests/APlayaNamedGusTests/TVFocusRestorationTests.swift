@testable import Gus
import SwiftUI
import Testing

@Suite("TV focus restoration")
struct TVFocusRestorationTests {
    @Test("restoration follows identity across reorder")
    func reordered() {
        #expect(TVFocusBookmark(id: "b", index: 1).restoredID(in: ["c", "b", "a"]) == "b")
    }

    @Test("removed item selects the nearest surviving position")
    func removed() {
        #expect(TVFocusBookmark(id: "b", index: 1).restoredID(in: ["a", "c"]) == "c")
        #expect(TVFocusBookmark(id: "c", index: 2).restoredID(in: ["a"]) == "a")
    }

    @MainActor
    @Test("a new signed-in tree does not inherit another account’s focus")
    func accountIsolation() {
        let first = RootNavigationState()
        first.tvFocus.remember(id: "private-item", index: 0, section: "home.next", context: "home")
        let second = RootNavigationState()
        #expect(second.tvFocus.bookmarks.isEmpty)
    }

    @Test("empty data never requests a nonexistent focus target")
    func empty() {
        #expect(TVFocusBookmark(id: "b", index: 1).restoredID(in: []) == nil)
    }

    @Test("child detail focus preserves the parent’s last rail")
    func screenContexts() {
        var memory = TVFocusMemory()
        memory.remember(id: "latest-card", index: 0, section: "latest", context: "home")
        memory.remember(id: "play", index: 0, section: "actions", context: "detail")
        #expect(memory.restoredID(section: "latest", context: "home", ids: ["latest-card"], initial: false) == "latest-card")
        #expect(memory.restoredID(section: "next", context: "home", ids: ["next-card"], initial: false) == nil)
        #expect(memory.restoredID(section: "next", context: "home", ids: ["new-card"], initial: true) == nil, "New rails do not override existing screen focus")
    }

    @Test("task dismissal restores its opener without borrowing another context")
    func taskDismissal() {
        var memory = TVFocusMemory()
        memory.remember(id: "more", index: 3, section: "actions", context: "detail")
        memory.remember(id: "other-card", index: 0, section: "latest", context: "home")
        memory.requestRestoration(context: "detail")
        #expect(memory.restorationRequest(context: "detail") == nil)
        let acceptedFallback = memory.remember(id: "play", index: 0, section: "actions", context: "detail", ids: ["play", "more"])
        #expect(!acceptedFallback)
        #expect(memory.restorationRequest(context: "detail") != nil)
        #expect(memory.restoredID(section: "actions", context: "detail", ids: ["play", "more"], initial: false) == "more")
        memory.remember(id: "more", index: 1, section: "actions", context: "detail", ids: ["play", "more"])
        #expect(memory.restorationRequest(context: "detail") == nil)
        memory.requestRestoration(context: "missing")
        #expect(memory.restorationRequest(context: "missing") == nil)
    }

    @Test("invalid fallback positions are clamped")
    func clamped() {
        #expect(TVFocusBookmark(id: "missing", index: -1).restoredID(in: ["a", "b"]) == "a")
    }

    #if os(tvOS)
        @MainActor
        @Test("retained parent preserves its rail through native fallback after a pop")
        func retainedParentPop() {
            let root = RootNavigationState()
            root.tvFocus.remember(id: "b", index: 1, section: "latest", context: "home")
            root.paths["home", default: NavigationPath()].append("child")
            root.tvFocus.remember(id: "play", index: 0, section: "actions", context: "detail")
            root.paths["home"] = NavigationPath()
            root.tvFocus.remember(id: "book", index: 0, section: "books", context: "home")
            #expect(root.tvFocus.restoredID(section: "latest", context: "home", ids: ["a", "c"], initial: false) == "c")
        }
    #endif
}
