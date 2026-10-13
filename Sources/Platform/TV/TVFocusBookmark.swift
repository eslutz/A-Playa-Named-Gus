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

    mutating func remember(id: String, index: Int, section: String, context: String) {
        bookmarks[section] = TVFocusBookmark(id: id, index: index)
        sectionsByContext[context] = section
    }

    func restoredID(section: String, context: String, ids: [String], initial: Bool) -> String? {
        if sectionsByContext[context] == section {
            return bookmarks[section]?.restoredID(in: ids)
        }
        return initial && sectionsByContext[context] == nil ? ids.first : nil
    }
}
