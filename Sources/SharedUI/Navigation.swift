import Foundation

// Typed navigation values so a `NavigationStack` can distinguish "open this library"
// from "open this item" even though both wrap a `MediaItem`.
//
// Hashing/equality is by item id.

struct LibraryRef: Hashable, Identifiable {
    let item: MediaItem
    var id: String {
        item.id ?? UUID().uuidString
    }

    static func == (lhs: LibraryRef, rhs: LibraryRef) -> Bool {
        lhs.item.id == rhs.item.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(item.id)
    }
}

struct ItemRef: Hashable, Identifiable {
    let item: MediaItem
    var id: String {
        item.id ?? UUID().uuidString
    }

    static func == (lhs: ItemRef, rhs: ItemRef) -> Bool {
        lhs.item.id == rhs.item.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(item.id)
    }
}
