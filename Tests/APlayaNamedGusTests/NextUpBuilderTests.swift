import Foundation
@testable import Gus
import Testing

@Suite("Unified Next Up")
struct NextUpBuilderTests {
    private let scope = AccountScope(serverID: "server", userID: "user")
    private func episode(_ id: String, series: String = "series", at: Date? = nil, watched: Bool = false) -> MediaItem {
        MediaItem(id: id, seriesID: series, type: .episode, userData: MediaUserData(playbackPositionTicks: 10, isWatched: watched, lastPlayedAt: at))
    }

    private func saved(_ item: MediaItem, at: Date? = nil) -> UpNextEntry {
        UpNextEntry(id: UUID(), reference: MediaReference(item: item, scope: scope), activityAt: at)
    }

    @Test("resume and saved intent merge reasons; a different explicitly saved episode survives series suppression")
    func reasonsAndSeriesSuppression() {
        let resume = episode("resume")
        let explicit = episode("explicit")
        let cards = NextUpBuilder.build(resume: [resume], nextEpisodes: [episode("automatic")], saved: [saved(resume), saved(explicit)])
        #expect(cards.map { $0.item?.id } == ["resume", "explicit"])
        #expect(cards[0].reasons == [.resume, .saved])
    }

    @Test("one unfinished automatic episode per series uses genuine recent activity")
    func newestUnfinishedEpisode() {
        let old = episode("old", at: Date(timeIntervalSince1970: 10))
        let recent = episode("recent", at: Date(timeIntervalSince1970: 20))
        let cards = NextUpBuilder.build(resume: [old, recent], nextEpisodes: [episode("next")], saved: [])
        #expect(cards.map { $0.item?.id } == ["recent"])
    }

    @Test("completed items disappear from automatic and explicitly saved sources")
    func completion() {
        let watched = episode("watched", watched: true)
        let cards = NextUpBuilder.build(resume: [watched], nextEpisodes: [watched], saved: [saved(watched)])
        #expect(cards.isEmpty)
    }

    @Test("dated activity leads; equal dates and unknown dates preserve stable first-seen order")
    func stableRecentActivity() {
        let date = Date(timeIntervalSince1970: 10)
        let entries = [saved(episode("legacy-a")), saved(episode("legacy-b")), saved(episode("dated-a"), at: date), saved(episode("dated-b"), at: date)]
        let first = NextUpBuilder.build(resume: [], nextEpisodes: [], saved: entries)
        let second = NextUpBuilder.build(resume: [], nextEpisodes: [], saved: entries.reversed(), firstSeenIDs: first.map(\.id))
        #expect(first.map { $0.item?.id } == ["dated-a", "dated-b", "legacy-a", "legacy-b"])
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.last?.activityAt == nil)
    }

    @Test("missing saved references remain and playlist cards never collapse into their current item")
    func missingAndPlaylistIdentity() {
        let item = episode("item")
        var missing = saved(episode("missing"))
        missing.availability = .unavailable
        let one = NextUpPlaylistCandidate(id: UUID(), name: "One", item: item, position: 1, total: 2)
        let two = NextUpPlaylistCandidate(id: UUID(), name: "Two", item: item, position: 1, total: 2)
        let cards = NextUpBuilder.build(resume: [], nextEpisodes: [], saved: [missing, saved(item)], playlists: [one, two])
        #expect(cards.count == 3)
        #expect(cards.first?.savedEntry?.availability == .unavailable)
        #expect(Set(cards.map(\.id)).count == 3)
    }

    @Test("active playlists suppress all current and future members including explicitly saved items")
    func playlistMembership() {
        let first = episode("first")
        let future = episode("future", series: "other")
        let movie = MediaItem(id: "movie", type: .movie, userData: MediaUserData(playbackPositionTicks: 20))
        let candidate = NextUpPlaylistCandidate(id: UUID(), name: "Queue", item: first, position: 1, total: 3, members: [first, future, movie])
        let cards = NextUpBuilder.build(resume: [first, movie], nextEpisodes: [future], saved: [saved(first), saved(future), saved(movie)], playlists: [candidate])
        #expect(cards.count == 1)
        #expect(cards[0].playlist?.id == candidate.id)
    }

    @Test("only an unfinished episode left behind by every covering playlist can appear independently")
    func skippedEpisodeException() {
        let skipped = episode("skipped")
        let current = episode("current", series: "other")
        let movie = MediaItem(id: "movie", type: .movie, userData: MediaUserData(playbackPositionTicks: 20))
        let candidate = NextUpPlaylistCandidate(id: UUID(), name: "Queue", item: current, position: 3, total: 3, members: [skipped, movie, current])
        let cards = NextUpBuilder.build(resume: [skipped, current, movie], nextEpisodes: [], saved: [saved(movie)], playlists: [candidate])
        #expect(cards.filter { $0.playlist == nil }.compactMap { $0.item?.id } == ["skipped"])
        let unplayed = MediaItem(id: "skipped", seriesID: "series", type: .episode)
        #expect(NextUpBuilder.build(resume: [], nextEpisodes: [unplayed], saved: [saved(unplayed)], playlists: [candidate]).count == 1)
        let alsoCurrent = NextUpPlaylistCandidate(id: UUID(), name: "Other", item: skipped, position: 1, total: 1, members: [skipped])
        #expect(NextUpBuilder.build(resume: [skipped], nextEpisodes: [], saved: [], playlists: [candidate, alsoCurrent]).count == 2)
    }

    @Test("metadata refresh and reordered provider responses cannot invent activity or reorder unknown dates")
    func refreshedUnknownDates() {
        let first = NextUpBuilder.build(resume: [], nextEpisodes: [episode("a", series: "a"), episode("b", series: "b")], saved: [])
        let second = NextUpBuilder.build(resume: [], nextEpisodes: [episode("b", series: "b"), episode("a", series: "a")], saved: [], firstSeenIDs: first.map(\.id))
        #expect(first.map(\.id) == second.map(\.id))
        #expect(second.allSatisfy { $0.activityAt == nil })
    }

    @Test("partially watched next-up records outside the resume page are promoted to Resume")
    func promotesPartialNextRecord() {
        let partial = episode("partial", at: Date(timeIntervalSince1970: 30))
        let future = MediaItem(id: "future", seriesID: "series", type: .episode)
        let cards = NextUpBuilder.build(resume: [], nextEpisodes: [future, partial], saved: [])
        #expect(cards.count == 1)
        #expect(cards[0].item?.id == "partial")
        #expect(cards[0].reasons == [.resume])
    }
}
