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

    @Test("completed automatic items disappear while explicitly saved rewatches remain")
    func completion() {
        let watched = episode("watched", watched: true)
        let cards = NextUpBuilder.build(resume: [watched], nextEpisodes: [watched], saved: [saved(watched)])
        #expect(cards.count == 1)
        #expect(cards[0].reasons == [.saved])
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
        var missing = saved(item)
        missing.availability = .unavailable
        let one = NextUpPlaylistCandidate(id: UUID(), name: "One", item: item, position: 1, total: 2)
        let two = NextUpPlaylistCandidate(id: UUID(), name: "Two", item: item, position: 1, total: 2)
        let cards = NextUpBuilder.build(resume: [], nextEpisodes: [], saved: [missing], playlists: [one, two])
        #expect(cards.count == 3)
        #expect(cards.first?.savedEntry?.availability == .unavailable)
        #expect(Set(cards.map(\.id)).count == 3)
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
