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
        var request: UUID?
    }

    private var frames: [FrameKey: Frame] = [:]
    private var returning: [String: Frame] = [:]

    mutating func navigationChanged(section: String, from oldDepth: Int, to newDepth: Int) {
        if newDepth > oldDepth, let context = lastContext,
           let focusedSection = sectionsByContext[context], let bookmark = bookmarks[focusedSection]
        {
            frames[FrameKey(section: section, depth: oldDepth)] = Frame(context: context, section: focusedSection, bookmark: bookmark)
        } else if newDepth < oldDepth, let frame = frames.removeValue(forKey: FrameKey(section: section, depth: newDepth)) {
            returning[frame.context] = frame
            frames = frames.filter { $0.key.section != section || $0.key.depth < newDepth }
        }
    }

    func restorationRequest(context: String) -> UUID? {
        returning[context]?.request
    }

    @discardableResult
    mutating func remember(id: String, index: Int, section: String, context: String, ids: [String]? = nil) -> Bool {
        if var frame = returning[context] {
            let target = ids.flatMap { frame.bookmark.restoredID(in: $0) } ?? frame.bookmark.id
            if section == frame.section, id == target {
                returning.removeValue(forKey: context)
            } else if frame.request == nil {
                // The retained parent is now focusable. Its automatic first-card
                // fallback must not replace the saved rail before the native request.
                frame.request = UUID()
                returning[context] = frame
                return false
            } else {
                // A subsequent different focus choice belongs to the user/engine;
                // cancel the old request instead of repeatedly stealing focus.
                returning.removeValue(forKey: context)
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
