import Foundation

/// Local-only projections of the completed download index; no provider requests.
enum DownloadedLibraryFilter: String, CaseIterable, Identifiable {
    case all, movies, shows, audio, books
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: return String(localized: "All", comment: "Downloaded filter")
        case .movies: return String(localized: "Movies", comment: "Downloaded filter")
        case .shows: return String(localized: "Shows", comment: "Downloaded filter")
        case .audio: return String(localized: "Audio", comment: "Downloaded filter")
        case .books: return String(localized: "Books", comment: "Downloaded filter")
        }
    }

    func includes(_ item: MediaItem) -> Bool {
        switch self {
        case .all: return true
        case .movies: return item.type == .movie || item.type == .video || item.type == .recording
        case .shows: return item.type == .episode
        case .audio: return item.isAudioPlayable
        case .books: return item.type == .book
        }
    }
}

struct DownloadedLibrarySection: Identifiable {
    let id: String
    let title: String
    let records: [OfflineDownloadRecord]
}

enum DownloadedLibrary {
    static func sections(
        records: [OfflineDownloadRecord], filter: DownloadedLibraryFilter, search: String,
        admits: (MediaItem) -> Bool = { ContentRatingGate.admitsStored($0) }
    ) -> [DownloadedLibrarySection] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = records.filter { record in
            record.status.isComplete && filter.includes(record.item) && admits(record.item) &&
                (query.isEmpty || searchText(record.item).localizedStandardContains(query))
        }
        var sections: [DownloadedLibrarySection] = []
        let other = visible.filter { $0.item.type != .episode }.sorted { precedes($0.item, $1.item) }
        if !other.isEmpty {
            sections.append(DownloadedLibrarySection(id: "items", title: filter.title, records: other))
        }
        let episodes = Dictionary(grouping: visible.filter { $0.item.type == .episode }) { record in
            seriesKey(record.item) + ":season:\(record.item.parentIndexNumber ?? -1)"
        }
        let episodeSections = episodes.map { key, group in
            let sorted = group.sorted { precedes($0.item, $1.item) }
            let item = sorted[0].item
            let series = item.seriesName ?? String(localized: "Shows", comment: "Unknown downloaded series")
            let title: String
            if let season = item.parentIndexNumber {
                title = String(localized: "\(series) — Season \(season)", comment: "Downloaded series season heading")
            } else {
                title = series
            }
            return DownloadedLibrarySection(id: key, title: title, records: sorted)
        }.sorted { lhs, rhs in
            let left = lhs.records[0].item
            let right = rhs.records[0].item
            if seriesKey(left) == seriesKey(right) {
                return (left.parentIndexNumber ?? -1) < (right.parentIndexNumber ?? -1)
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        sections.append(contentsOf: episodeSections)
        return sections
    }

    static func episodeLabel(_ item: MediaItem) -> String? {
        guard item.type == .episode else { return nil }
        if let season = item.parentIndexNumber, let episode = item.indexNumber {
            return String(format: NSLocalizedString("S%02d E%02d", comment: "Downloaded season and episode number, with zero padding"), season, episode)
        }
        if let episode = item.indexNumber {
            return String(localized: "Episode \(episode)", comment: "Downloaded episode number")
        }
        return nil
    }

    /// Auto-play only the immediate numbered successor. Gaps require explicit selection
    /// rather than silently skipping an undownloaded episode or streaming it.
    static func nextEpisode(after item: MediaItem, records: [OfflineDownloadRecord]) -> MediaItem? {
        guard item.type == .episode, let number = item.indexNumber,
              let season = item.parentIndexNumber, item.seriesID != nil || item.seriesName != nil
        else { return nil }
        let candidates = records.filter { $0.status.isComplete }.map(\.item).filter {
            $0.type == .episode && $0.id != item.id && seriesKey($0) == seriesKey(item) &&
                ContentRatingGate.admitsStored($0)
        }
        if let next = candidates.first(where: {
            $0.parentIndexNumber == season && $0.indexNumber == number + 1
        }) {
            return next
        }
        return nil
    }

    private static func searchText(_ item: MediaItem) -> String {
        ([item.name, item.seriesName, item.album, item.albumArtist, episodeLabel(item)].compactMap { $0 } + item.artists).joined(separator: " ")
    }

    private static func seriesKey(_ item: MediaItem) -> String {
        item.seriesID ?? item.seriesName ?? item.parentID ?? item.id ?? "unknown"
    }

    private static func precedes(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
        if lhs.type == .episode && rhs.type == .episode {
            let left = lhs.indexNumber ?? Int.max
            let right = rhs.indexNumber ?? Int.max
            if left != right {
                return left < right
            }
        }
        return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
    }
}

/// Other downloaded book originals stay available through native sharing instead of
/// entering the PDF or EPUB reader, which cannot render those formats.
enum DownloadedBookFormat {
    case pdf
    case epub
    case externalReader

    init(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "pdf": self = .pdf
        case "epub": self = .epub
        default: self = .externalReader
        }
    }
}
