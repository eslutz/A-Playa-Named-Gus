import Foundation

extension OfflineDownloadRecord {
    /// A downloaded file carries its own source snapshot. Item-wide defaults and
    /// server resume data may describe another cut.
    var playbackItem: MediaItem {
        var result = item
        if let mediaSourceID, var source = item.mediaSources.first(where: { $0.id == mediaSourceID }) {
            if activity?.sourceOperation == .remuxed || activity?.sourceOperation == .transcoded {
                // Progressive conversions select/copy streams and may burn subtitles.
                // Original indexes and defaults do not describe the saved file, and
                // the record has no trustworthy output-track mapping.
                source.mediaStreams = []
                source.defaultAudioStreamIndex = nil
                source.defaultSubtitleStreamIndex = nil
            } else {
                // An original download saves the media container, not its separate
                // subtitle/audio sidecars. Only embedded tracks remain local choices.
                let externalIndexes = Set(source.mediaStreams.filter { $0.isExternal == true }.compactMap(\.index))
                source.mediaStreams.removeAll { $0.isExternal == true }
                if let index = source.defaultAudioStreamIndex, externalIndexes.contains(index) {
                    source.defaultAudioStreamIndex = nil
                }
                if let index = source.defaultSubtitleStreamIndex, externalIndexes.contains(index) {
                    source.defaultSubtitleStreamIndex = nil
                }
            }
            result.mediaSources = [source]
            result.runTimeTicks = source.runTimeTicks ?? (item.mediaSources.count == 1 ? item.runTimeTicks : nil)
        } else {
            // Unknown existing downloads retain no guessed source or track catalog.
            result.mediaSources = []
            result.runTimeTicks = nil
        }
        if item.mediaSources.count > 1, mediaSourceID == nil || mediaSourceID != item.mediaSources.first?.id {
            result.chapters = []
        }
        result.userData?.playbackPositionTicks = nil
        return result
    }

    var playbackRequest: PlaybackRequest {
        PlaybackRequest(item: playbackItem, streamSelection: PlaybackStreamSelection(audioStreamIndex: nil, subtitleStreamIndex: nil, mediaSourceID: mediaSourceID))
    }

    @MainActor
    func playbackSelection(for request: PlaybackRequest) -> PlaybackStreamSelection {
        guard let source = playbackItem.mediaSources.first else {
            return PlaybackStreamSelection(audioStreamIndex: nil, subtitleStreamIndex: request.subtitleIntent == .off ? -1 : nil, mediaSourceID: mediaSourceID)
        }
        var selection = request.selection(in: source)
        selection.mediaSourceID = mediaSourceID
        if let index = selection.audioStreamIndex, !source.mediaStreams.contains(where: { $0.type == .audio && $0.index == index }) {
            selection.audioStreamIndex = nil
        }
        if let index = selection.subtitleStreamIndex, index >= 0, !source.mediaStreams.contains(where: { $0.type == .subtitle && $0.index == index }) {
            selection.subtitleStreamIndex = nil
        }
        return selection
    }
}

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
    static func albums(in records: [OfflineDownloadRecord]) -> [MediaItem] {
        let policy = ContentRatingGate.storedPolicy()
        let albums = records.compactMap { record -> MediaItem? in
            let track = record.item
            guard record.status.isComplete, record.isAdmitted(by: policy.admits), track.type == .audio,
                  let id = track.albumID, !id.isEmpty, let name = track.album, !name.isEmpty else { return nil }
            let album = MediaItem(providerKind: track.providerKind, albumArtist: track.albumArtist, artists: track.artists, id: id, name: name, type: .musicAlbum)
            return policy.admits(album) ? album : nil
        }
        return MediaPageLoader.unique(albums)
    }

    static func tracks(in records: [OfflineDownloadRecord], albumID: String) -> [OfflineDownloadRecord] {
        let policy = ContentRatingGate.storedPolicy()
        return records.filter {
            $0.status.isComplete && $0.item.type == .audio && $0.item.id != nil && $0.item.albumID == albumID && $0.isAdmitted(by: policy.admits)
        }.sorted {
            let lhs = $0.item
            let rhs = $1.item
            return (lhs.parentIndexNumber ?? 0, lhs.indexNumber ?? 0, lhs.displayTitle, $0.id) <
                (rhs.parentIndexNumber ?? 0, rhs.indexNumber ?? 0, rhs.displayTitle, $1.id)
        }
    }

    static func sections(
        records: [OfflineDownloadRecord], filter: DownloadedLibraryFilter, search: String,
        admits: (MediaItem) -> Bool = { ContentRatingGate.admitsStored($0) }
    ) -> [DownloadedLibrarySection] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = records.filter { record in
            record.status.isComplete && filter.includes(record.item) && record.isAdmitted(by: admits) &&
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
        let policy = ContentRatingGate.storedPolicy()
        let candidates = records.filter { $0.status.isComplete && $0.isAdmitted(by: policy.admits) }.map(\.item).filter {
            $0.type == .episode && $0.id != item.id && seriesKey($0) == seriesKey(item)
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
