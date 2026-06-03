import Foundation
import JellyfinAPI

// Typed navigation values so a `NavigationStack` can distinguish "open this library"
// from "open this item" even though both wrap a `BaseItemDto`.
//
// Hashing/equality is by item id, so we don't require `BaseItemDto: Hashable`.

struct LibraryRef: Hashable, Identifiable {
    let item: BaseItemDto
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
    let item: BaseItemDto
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
