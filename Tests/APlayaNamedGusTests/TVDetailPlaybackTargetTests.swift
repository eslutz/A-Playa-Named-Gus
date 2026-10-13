@testable import Gus
import Testing

@Suite("TV detail playback targets")
struct TVDetailPlaybackTargetTests {
    @Test("series plays its existing Next Up episode rather than the series container")
    func nextEpisode() {
        let show = MediaItem(id: "show", type: .series)
        let next = MediaItem(id: "episode", seriesID: "show", type: .episode)
        let entries = [NextUpEntry(id: "media:episode", item: next, reasons: [.nextEpisode], activityAt: nil)]
        #expect(TVDetailPlaybackTarget.resolve(item: show, nextUp: entries, episodes: [])?.id == "episode")
    }

    @Test("an independent playlist cursor does not select the series primary episode")
    func independentPlaylist() {
        let cursor = MediaItem(id: "playlist-episode", seriesID: "show", type: .episode)
        let next = MediaItem(id: "next", seriesID: "show", type: .episode)
        let candidate = NextUpPlaylistCandidate(id: .init(), name: "List", item: cursor, position: 1, total: 1)
        let entries = [NextUpEntry(id: "playlist", item: cursor, reasons: [.playlist], activityAt: nil, playlist: candidate)]
        #expect(TVDetailPlaybackTarget.resolve(item: MediaItem(id: "show", type: .series), nextUp: entries, episodes: [next])?.id == "next")
    }

    @Test("empty series and collection containers have no direct play action")
    func emptyContainers() {
        #expect(TVDetailPlaybackTarget.resolve(item: MediaItem(id: "show", type: .series), nextUp: [], episodes: []) == nil)
        #expect(TVDetailPlaybackTarget.resolve(item: MediaItem(id: "collection", type: .boxSet), nextUp: [], episodes: []) == nil)
        let episode = MediaItem(id: "other-season", parentIndexNumber: 2, seriesID: "show", type: .episode)
        let entry = NextUpEntry(id: "other-season", item: episode, reasons: [.nextEpisode], activityAt: nil)
        #expect(TVDetailPlaybackTarget.resolve(item: MediaItem(id: "season-one", indexNumber: 1, seriesID: "show", type: .season), nextUp: [entry], episodes: []) == nil, "A season container must not borrow another season’s episode")
    }

    @Test("selected-season fallback prefers an unfinished episode")
    func seasonFallback() {
        let first = MediaItem(id: "watched", seriesID: "show", type: .episode, userData: MediaUserData(isWatched: true))
        let next = MediaItem(id: "unwatched", seriesID: "show", type: .episode)
        #expect(TVDetailPlaybackTarget.resolve(item: MediaItem(id: "show", type: .series), nextUp: [], episodes: [first, next])?.id == "unwatched")
    }
}
