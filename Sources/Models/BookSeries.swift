import Foundation

/// Jellyfin can return a series name without a series ID. Format is part of the
/// key so an ebook and its audio edition stay in their respective stacks.
struct BookSeriesKey: Hashable {
    let format: MediaItemType
    let identity: String

    init?(item: MediaItem, usingID: Bool = true) {
        guard item.isBookFormat, let format = item.type else { return nil }
        self.format = format
        if usingID, let id = Self.explicitID(item.seriesID) {
            identity = "id:" + id
        } else {
            guard let name = item.seriesName.map(Self.normalizedName), !name.isEmpty else { return nil }
            identity = "name:" + name
        }
    }

    static func explicitID(_ raw: String?) -> String? {
        let id = raw?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: "").lowercased()
        guard let id, id.contains(where: { $0 != "0" }) else { return nil }
        return id
    }

    static func normalizedName(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ").precomposedStringWithCanonicalMapping.lowercased()
    }
}

/// Jellyfin's writable SeriesName identifies name-based ebook series. A series
/// managed by a server ID cannot be assigned, renamed or detached by that field.
struct BookSeriesEditScope {
    let editableBooks: [MediaItem]
    private let idBackedNames: Set<String>

    init(_ catalog: [MediaItem]) {
        let books = catalog.filter { $0.type == .book }
        editableBooks = books.filter { BookSeriesKey.explicitID($0.seriesID) == nil }
        idBackedNames = Set(books.compactMap { book in
            guard BookSeriesKey.explicitID(book.seriesID) != nil, let name = book.seriesName else { return nil }
            return BookSeriesKey.normalizedName(name)
        })
    }

    func allowsAssignment(to name: String) -> Bool {
        !idBackedNames.contains(BookSeriesKey.normalizedName(name))
    }
}

struct BookSeries: Identifiable {
    let id: BookSeriesKey
    let name: String
    let members: [MediaItem]

    /// A track/disc number on an audiobook identifies part of a recording.
    /// Only ebook index numbers represent volumes in the standard Jellyfin DTO.
    static func volumeOrder(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        if lhs.type == .book, rhs.type == .book,
           lhs.indexNumber != rhs.indexNumber
        {
            return (lhs.indexNumber ?? .max) < (rhs.indexNumber ?? .max)
        }
        let leftYear = lhs.displayYear
        let rightYear = rhs.displayYear
        if leftYear != rightYear {
            return (leftYear ?? .max) < (rightYear ?? .max)
        }
        if lhs.premiereDate != rhs.premiereDate {
            return (lhs.premiereDate ?? .distantFuture) < (rhs.premiereDate ?? .distantFuture)
        }
        let order = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
        return order == .orderedSame ? (lhs.id ?? "") < (rhs.id ?? "") : order == .orderedAscending
    }
}

enum BookShelfEntry: Identifiable {
    case title(MediaItem)
    case series(BookSeries)

    var id: String {
        switch self {
        case let .title(item): return item.id ?? "title:" + item.displayTitle
        case let .series(series): return "series:" + series.id.format.rawValue + ":" + series.id.identity
        }
    }

    var title: String {
        switch self {
        case let .title(item): item.displayTitle
        case let .series(series): series.name
        }
    }
}

/// Prefer a real ID if all entries with this name and format agree on one.
/// Name-based ebook stacks remain editable. For audiobooks with conflicting
/// series IDs, only volumes with an explicit ID can be grouped reliably.
struct BookSeriesCatalog {
    let books: [MediaItem]
    private let aliases: [BookSeriesKey: BookSeriesKey]
    private let groups: [BookSeriesKey: BookSeries]

    init(_ books: [MediaItem]) {
        self.books = books
        var namedIDs: [BookSeriesKey: Set<BookSeriesKey>] = [:]
        for book in books {
            guard let key = BookSeriesKey(item: book), let name = BookSeriesKey(item: book, usingID: false), key != name else { continue }
            namedIDs[name, default: []].insert(key)
        }
        let aliases = namedIDs.compactMapValues { $0.count == 1 ? $0.first : nil }
        self.aliases = aliases
        var members: [BookSeriesKey: [MediaItem]] = [:]
        for book in books {
            if let key = BookSeriesKey(item: book) {
                if key.format == .audioBook, let ids = namedIDs[key], ids.count > 1 {
                    continue
                }
                members[aliases[key] ?? key, default: []].append(book)
            }
        }
        groups = members.reduce(into: [:]) { groups, entry in
            let sorted = entry.value.sorted(by: BookSeries.volumeOrder)
            let names = sorted.lazy.compactMap(\.seriesName).map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            if let displayName = names.first(where: { !$0.isEmpty }) {
                groups[entry.key] = BookSeries(id: entry.key, name: displayName, members: sorted)
            }
        }
    }

    func series(_ key: BookSeriesKey) -> BookSeries? {
        groups[aliases[key] ?? key]
    }

    /// Filters affect which stacks appear, while the detail always contains
    /// the accessible series membership in the current browse scope.
    func entries(visible: [MediaItem], sortByName: Bool) -> [BookShelfEntry] {
        var seen = Set<BookSeriesKey>()
        let entries: [BookShelfEntry] = visible.compactMap { item in
            guard let key = BookSeriesKey(item: item), let group = series(key) else { return .title(item) }
            return seen.insert(group.id).inserted ? .series(group) : nil
        }
        guard sortByName else { return entries }
        return entries.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
