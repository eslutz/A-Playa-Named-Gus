import Foundation

/// Session-owned focus identity; index is only a fallback when an item disappears.
struct TVFocusBookmark: Equatable {
    let id: String
    let index: Int

    func restoredID(in ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        if ids.contains(id) {
            return id
        }
        return ids[min(max(index, 0), ids.count - 1)]
    }
}

enum TVDetailActionOrder {
    private static let leadingIDs = ["play", "version", "nextUp", "favorite"]
    static let moreID = "more"
    static let ids = leadingIDs + [moreID, "synopsis"]
}

/// Focus history belongs to each screen context, not the most recently pushed child.
struct TVFocusMemory {
    private(set) var bookmarks: [String: TVFocusBookmark] = [:]
    private var sectionsByContext: [String: String] = [:]
    private var lastContext: String?
    private struct FrameKey: Hashable { let section: String; let depth: Int }
    private struct Frame {
        let context: String
        let section: String
        let bookmark: TVFocusBookmark
        let request: UUID?
    }

    private var frames: [FrameKey: Frame] = [:]
    private var returning: [String: Frame] = [:]

    mutating func navigationChanged(section: String, from oldDepth: Int, to newDepth: Int) {
        if newDepth > oldDepth, let context = lastContext,
           let focusedSection = sectionsByContext[context], let bookmark = bookmarks[focusedSection]
        {
            frames[FrameKey(section: section, depth: oldDepth)] = Frame(context: context, section: focusedSection, bookmark: bookmark, request: nil)
        } else if newDepth < oldDepth, let frame = frames.removeValue(forKey: FrameKey(section: section, depth: newDepth)) {
            returning[frame.context] = Frame(context: frame.context, section: frame.section, bookmark: frame.bookmark, request: UUID())
            frames = frames.filter { $0.key.section != section || $0.key.depth < newDepth }
        }
    }

    /// Each pushed related-results page has a unique focus context for its own scroll position.
    mutating func discardResults(context: String) {
        bookmarks[context] = nil
        sectionsByContext[context] = nil
        returning[context] = nil
        frames = frames.filter { $0.value.context != context }
        if lastContext == context {
            lastContext = nil
        }
    }

    /// A dismissed task returns to the control that opened it in the same context.
    mutating func requestRestoration(context: String) {
        guard let section = sectionsByContext[context], let bookmark = bookmarks[section] else { return }
        requestRestoration(context: context, section: section, bookmark: bookmark)
    }

    /// An explicit opener is a return preference, not an observed focus change.
    mutating func requestRestoration(context: String, section: String, bookmark: TVFocusBookmark) {
        returning[context] = Frame(context: context, section: section, bookmark: bookmark, request: UUID())
    }

    func restorationRequest(context: String) -> UUID? {
        returning[context]?.request
    }

    @discardableResult
    mutating func remember(id: String, index: Int, section: String, context: String, ids: [String]? = nil) -> Bool {
        if let frame = returning[context] {
            let target = ids.flatMap { frame.bookmark.restoredID(in: $0) } ?? frame.bookmark.id
            if section == frame.section, id == target {
                returning.removeValue(forKey: context)
            } else {
                // SwiftUI focus changes do not identify user input. Preserve the
                // immutable return target until it receives focus; never reissue it.
                return false
            }
        }
        bookmarks[section] = TVFocusBookmark(id: id, index: index)
        sectionsByContext[context] = section
        lastContext = context
        return true
    }

    func restoredID(section: String, context: String, ids: [String], initial: Bool) -> String? {
        if let frame = returning[context] {
            return frame.section == section ? frame.bookmark.restoredID(in: ids) : nil
        }
        if sectionsByContext[context] == section {
            return bookmarks[section]?.restoredID(in: ids)
        }
        return initial && sectionsByContext[context] == nil ? ids.first : nil
    }
}
