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

    @Test("task dismissal keeps one immutable request through native fallback")
    func taskDismissal() throws {
        var memory = TVFocusMemory()
        memory.remember(id: "more", index: 1, section: "actions", context: "detail")
        memory.remember(id: "other-card", index: 0, section: "latest", context: "home")
        memory.requestRestoration(context: "detail")
        let initialRequest = try #require(memory.restorationRequest(context: "detail"))
        let acceptedFallback = memory.remember(id: "play", index: 0, section: "actions", context: "detail", ids: ["play", "more"])
        #expect(!acceptedFallback)
        #expect(memory.restorationRequest(context: "detail") == initialRequest)
        let acceptedSecondFallback = memory.remember(id: "other", index: 0, section: "other", context: "detail")
        #expect(!acceptedSecondFallback)
        #expect(memory.restorationRequest(context: "detail") == initialRequest)
        #expect(memory.bookmarks["actions"]?.id == "more")
        #expect(memory.restoredID(section: "actions", context: "detail", ids: ["play", "more"], initial: false) == "more")
        memory.remember(id: "more", index: 1, section: "actions", context: "detail", ids: ["play", "more"])
        #expect(memory.restorationRequest(context: "detail") == nil)
        #expect(memory.bookmarks["actions"]?.id == "more")
        memory.requestRestoration(context: "missing")
        #expect(memory.restorationRequest(context: "missing") == nil)
    }

    @Test("an explicit opener and a replacement generation survive earlier focus callbacks")
    func fallbackBeforeDismissal() throws {
        var memory = TVFocusMemory()
        memory.remember(id: "more", index: 1, section: "actions", context: "detail")
        memory.remember(id: "play", index: 0, section: "actions", context: "detail")
        #expect(memory.bookmarks["actions"]?.id == "play")
        // The dismissing task explicitly identifies its More opener.
        memory.requestRestoration(context: "detail", section: "actions", bookmark: TVFocusBookmark(id: "more", index: 1))
        let firstRequest = try #require(memory.restorationRequest(context: "detail"))
        #expect(memory.bookmarks["actions"]?.id == "play", "An explicit return target is not an observed focus change")
        #expect(memory.restoredID(section: "actions", context: "detail", ids: ["play", "more"], initial: false) == "more")
        memory.requestRestoration(context: "detail", section: "actions", bookmark: TVFocusBookmark(id: "favorite", index: 2))
        let replacementRequest = try #require(memory.restorationRequest(context: "detail"))
        #expect(replacementRequest != firstRequest)
        let acceptedOldTarget = memory.remember(id: "more", index: 1, section: "actions", context: "detail", ids: ["play", "more", "favorite"])
        #expect(!acceptedOldTarget)
        #expect(memory.restorationRequest(context: "detail") == replacementRequest)
        #expect(memory.restoredID(section: "actions", context: "detail", ids: ["play", "more", "favorite"], initial: false) == "favorite")
    }

    @Test("target acknowledgement clears the request and later navigation only updates history")
    func subsequentUserChoice() {
        var memory = TVFocusMemory()
        let ids = ["play", "favorite", "more"]
        memory.remember(id: "more", index: 2, section: "actions", context: "detail")
        memory.requestRestoration(context: "detail")
        let acceptedFallback = memory.remember(id: "play", index: 0, section: "actions", context: "detail", ids: ids)
        #expect(!acceptedFallback)
        let acceptedTarget = memory.remember(id: "more", index: 2, section: "actions", context: "detail", ids: ids)
        #expect(acceptedTarget)
        #expect(memory.restorationRequest(context: "detail") == nil)
        let acceptedChoice = memory.remember(id: "favorite", index: 1, section: "actions", context: "detail", ids: ids)
        #expect(acceptedChoice)
        #expect(memory.restorationRequest(context: "detail") == nil)
        #expect(memory.restoredID(section: "actions", context: "detail", ids: ids, initial: false) == "favorite")
        let acceptedLaterChoice = memory.remember(id: "play", index: 0, section: "actions", context: "detail", ids: ids)
        #expect(acceptedLaterChoice)
        #expect(memory.restorationRequest(context: "detail") == nil)
    }

    @Test("a retained parent pop immediately requests its saved rail")
    func popRequestsImmediately() throws {
        var memory = TVFocusMemory()
        memory.remember(id: "b", index: 1, section: "latest", context: "home")
        memory.navigationChanged(section: "home", from: 0, to: 1)
        memory.remember(id: "play", index: 0, section: "actions", context: "detail")
        memory.navigationChanged(section: "home", from: 1, to: 0)
        _ = try #require(memory.restorationRequest(context: "home"))
        let acceptedFallback = memory.remember(id: "book", index: 0, section: "books", context: "home")
        #expect(!acceptedFallback)
        #expect(memory.restoredID(section: "latest", context: "home", ids: ["a", "c"], initial: false) == "c")
    }

    @Test("invalid fallback positions are clamped")
    func clamped() {
        #expect(TVFocusBookmark(id: "missing", index: -1).restoredID(in: ["a", "b"]) == "a")
    }

    #if os(tvOS)
        @MainActor
        @Test("detail task restores More after fallback and keeps its nearest surviving action")
        func detailOpenerRestoration() throws {
            let root = RootNavigationState()
            let item = MediaItem(id: "movie", type: .movie)
            let context = "detail:" + ItemRef(item: item).id
            root.tvFocus.remember(id: "play", index: 0, section: context, context: context)
            root.restoreTVDetailFocus(item: item)
            _ = try #require(root.tvFocus.restorationRequest(context: context))
            #expect(root.tvFocus.bookmarks[context]?.id == "play")
            #expect(root.tvFocus.restoredID(section: context, context: context, ids: ["play", "version", "nextUp", "favorite", "more", "synopsis"], initial: false) == "more")
            #expect(root.tvFocus.restoredID(section: context, context: context, ids: ["play", "version", "nextUp", "favorite", "synopsis"], initial: false) == "synopsis")
        }

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
