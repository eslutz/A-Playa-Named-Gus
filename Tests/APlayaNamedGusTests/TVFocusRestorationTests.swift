@testable import Gus
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

    @Test("invalid fallback positions are clamped")
    func clamped() {
        #expect(TVFocusBookmark(id: "missing", index: -1).restoredID(in: ["a", "b"]) == "a")
    }
}
