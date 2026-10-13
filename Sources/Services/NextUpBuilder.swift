import Foundation

/// A playlist remains a separate navigation target even when its current video is
/// also resumable or saved independently.
struct NextUpPlaylistCandidate: Equatable, Sendable {
    let id: UUID
    let name: String
    let item: MediaItem?
    let position: Int
    let total: Int
    var activityAt: Date? = nil
}

enum NextUpReason: String, Equatable, Sendable {
    case resume, nextEpisode, saved, playlist
}

struct NextUpEntry: Identifiable, Equatable, Sendable {
    let id: String
    var item: MediaItem?
    var reasons: [NextUpReason]
    var activityAt: Date?
    var savedEntry: UpNextEntry?
    var playlist: NextUpPlaylistCandidate?
}

/// Pure presentation merge. Provider response order and metadata refresh times
/// never become playback activity. Callers persist first-seen IDs separately.
enum NextUpBuilder {
    static func mediaID(_ item: MediaItem) -> String? {
        item.id.map { "media:\(item.providerKind.rawValue):\($0)" }
    }

    static func build(
        resume: [MediaItem], nextEpisodes: [MediaItem], saved: [UpNextEntry],
        playlists: [NextUpPlaylistCandidate] = [], activity: [String: Date] = [:],
        firstSeenIDs: [String] = []
    ) -> [NextUpEntry] {
        var cards: [NextUpEntry] = []
        var indices: [String: Int] = [:]
        let ranks = Dictionary(firstSeenIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        func date(for item: MediaItem, explicit: Date? = nil, inheritsSeriesActivity: Bool = false) -> Date? {
            // Only an automatic next episode continues the preceding episode's
            // activity. Other saved episodes keep their own explicit chronology.
            let seriesDate = inheritsSeriesActivity && item.type == .episode ? item.seriesID.flatMap { activity["media:\(item.providerKind.rawValue):\($0)"] } : nil
            return [item.userData?.lastPlayedAt, mediaID(item).flatMap { activity[$0] }, explicit, seriesDate].compactMap { $0 }.max()
        }
        func add(_ item: MediaItem, reason: NextUpReason, intent: UpNextEntry? = nil) {
            guard let id = mediaID(item) else { return }
            if let index = indices[id] {
                if !cards[index].reasons.contains(reason) {
                    cards[index].reasons.append(reason)
                }
                cards[index].activityAt = [cards[index].activityAt, date(for: item, explicit: intent?.activityAt, inheritsSeriesActivity: reason == .nextEpisode)].compactMap { $0 }.max()
                if let intent {
                    cards[index].savedEntry = intent
                }
                return
            }
            indices[id] = cards.count
            cards.append(NextUpEntry(id: id, item: item, reasons: [reason], activityAt: date(for: item, explicit: intent?.activityAt, inheritsSeriesActivity: reason == .nextEpisode), savedEntry: intent))
        }
        func completed(_ item: MediaItem) -> Bool {
            if item.userData?.isWatched == true || (item.userData?.playedPercentage ?? 0) >= 100 {
                return true
            }
            if let runtime = item.runTimeTicks, runtime > 0, (item.userData?.playbackPositionTicks ?? 0) >= runtime {
                return true
            }
            return false
        }
        func seriesKey(_ item: MediaItem) -> String? {
            guard item.type == .episode else { return nil }
            return item.seriesID.map { "\(item.providerKind.rawValue):\($0)" }
        }

        // Pick one unfinished automatic episode per series, favoring genuine
        // activity and using persisted first-seen order for undated ties.
        let promoted = nextEpisodes.filter { item in
            item.type == .episode && !completed(item) && ((item.userData?.playbackPositionTicks ?? 0) > 0 || (item.userData?.playedPercentage ?? 0) > 0)
        }
        let promotedIDs = Set(promoted.compactMap(mediaID))
        let unfinished = (resume + promoted).enumerated().filter { !completed($0.element) }
        let orderedResume = unfinished.sorted { a, b in
            let ad = date(for: a.element), bd = date(for: b.element)
            if ad != bd {
                return (ad ?? .distantPast) > (bd ?? .distantPast)
            }
            let ar = mediaID(a.element).flatMap { ranks[$0] } ?? (firstSeenIDs.count + a.offset)
            let br = mediaID(b.element).flatMap { ranks[$0] } ?? (firstSeenIDs.count + b.offset)
            return ar < br
        }
        var unfinishedSeries = Set<String>()
        for pair in orderedResume {
            let item = pair.element
            if let key = seriesKey(item), !unfinishedSeries.insert(key).inserted {
                continue
            }
            add(item, reason: .resume)
        }
        var nextSeries = Set<String>()
        for item in nextEpisodes where item.type == .episode && !completed(item) {
            if let id = mediaID(item), promotedIDs.contains(id) {
                continue
            }
            if let key = seriesKey(item) {
                guard !unfinishedSeries.contains(key), nextSeries.insert(key).inserted else { continue }
            }
            add(item, reason: .nextEpisode)
        }
        // Saved snapshots remain even after completion or confirmed removal from
        // the server, so the user can explicitly rewatch, replace, or remove them.
        for entry in saved {
            add(entry.reference.item, reason: .saved, intent: entry)
        }
        for playlist in playlists {
            cards.append(NextUpEntry(id: "playlist:\(playlist.id.uuidString)", item: playlist.item, reasons: [.playlist], activityAt: playlist.activityAt, playlist: playlist))
        }
        let candidateOrder = Dictionary(cards.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return cards.sorted { a, b in
            if a.activityAt != b.activityAt {
                return (a.activityAt ?? .distantPast) > (b.activityAt ?? .distantPast)
            }
            let ar = ranks[a.id] ?? (firstSeenIDs.count + (candidateOrder[a.id] ?? 0))
            let br = ranks[b.id] ?? (firstSeenIDs.count + (candidateOrder[b.id] ?? 0))
            return ar < br
        }
    }
}
