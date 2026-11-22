import Foundation
@testable import Gus
import Testing

@Suite("Siri library identities and filters")
struct GusIntentRuntimeTests {
    @Test("Opaque IDs confine colliding provider IDs to the originating profile, server and resource")
    func identities() {
        let scope = AccountScope(serverID: "media:/north", userID: "a.b_現")
        let raw = "id/with:spaces and é"
        let id = GusIntentID.make(resource: "media", id: raw, provider: .jellyfin, scope: scope)
        #expect(GusIntentID.value(id, resource: "media", provider: .jellyfin, scope: scope) == raw)
        #expect(GusIntentID.value(id, resource: "device", provider: .jellyfin, scope: scope) == nil)
        #expect(GusIntentID.value(id, resource: "media", provider: .jellyfin, scope: .init(serverID: scope.serverID, userID: "other")) == nil)
        #expect(GusIntentID.value(id, resource: "media", provider: .jellyfin, scope: .init(serverID: "elsewhere", userID: scope.userID)) == nil)
        for invalid in [raw, "2." + id.dropFirst(2), id + ".", String(repeating: "A", count: 8200)] {
            #expect(GusIntentID.value(invalid, resource: "media", provider: .jellyfin, scope: scope) == nil)
        }
    }

    @MainActor @Test("Scoped Handoff preserves required selections and refuses damaged or cross-profile legacy payloads")
    func handoff() {
        let activity = NSUserActivity(activityType: GusUserActivity.playback)
        let item = MediaItem(id: "movie", name: "Movie", officialRating: "G", type: .movie)
        let request = PlaybackRequest(item: item, startPositionTicks: 135)
        GusUserActivity.configure(activity, item: item, serverID: "server", userID: "viewer", playbackRequest: request)
        #expect(activity.requiredUserInfoKeys == ["itemID", "serverID", "userID", "playbackIntent"])
        #expect(GusUserActivity.contentLink(from: activity, currentServerID: nil, currentUserID: nil)?.playbackRequest?.startPositionTicks == 135)
        #expect(GusUserActivity.contentLink(from: activity, currentServerID: "server", currentUserID: "guest") == nil)

        // A scoped activity published by an older Gus carries just the item and profile.
        activity.userInfo = ["itemID": "movie", "userID": "viewer", "serverID": "server"]
        #expect(GusUserActivity.contentLink(from: activity, currentServerID: "server", currentUserID: "viewer") == .play(id: "movie", serverID: "server", provider: .jellyfin))
        activity.addUserInfoEntries(from: ["playbackIntent": Data([0xFF])])
        #expect(GusUserActivity.contentLink(from: activity, currentServerID: nil, currentUserID: nil) == nil)
        activity.userInfo = ["itemID": "movie"]
        #expect(GusUserActivity.contentLink(from: activity, currentServerID: nil, currentUserID: nil) == nil)
    }

    @Test("Title resolution accepts exact spoken spelling variants and rejects partial titles")
    func titles() {
        #expect(PlayMediaIntent.matchesTitle("Café", "  CAFE "))
        #expect(!PlayMediaIntent.matchesTitle("Café Society", "cafe"))
    }

    @Test("Missing and one-sided filter bounds work and inverted bounds are rejected")
    func filterBounds() {
        #expect(FilterGusLibraryIntent.validRange(nil, nil, minimum: 0))
        #expect(FilterGusLibraryIntent.validRange(nil, 1970, minimum: 1))
        #expect(FilterGusLibraryIntent.validRange(0, 0, minimum: 0))
        #expect(!FilterGusLibraryIntent.validRange(nil, -1, minimum: 0))
        #expect(!FilterGusLibraryIntent.validRange(2024, 1992, minimum: 1))
    }

    @Test("A calendar-day release filter preserves the selected local date and excludes the next UTC day")
    func premiereDates() throws {
        let timezone = try #require(TimeZone(identifier: "Pacific/Auckland"))
        // At 13:00 UTC, New Zealand has crossed into the next calendar day.
        let selected = Date(timeIntervalSince1970: 13 * 3600)
        let lower = try #require(FilterGusLibraryIntent.premiereDay(selected, timeZone: timezone))
        let upper = try #require(FilterGusLibraryIntent.premiereDay(selected, timeZone: timezone, endOfDay: true))
        #expect(lower.timeIntervalSince1970 == 86400)
        #expect(upper.timeIntervalSince1970 == 172_800)
        var filters = GusSearchIntent()
        filters.premieredOnOrAfter = lower
        filters.premieredBefore = upper
        #expect(GusLibraryMatching.accepts(MediaItem(id: "on", premiereDate: lower, type: .movie), intent: filters))
        #expect(!GusLibraryMatching.accepts(MediaItem(id: "after", premiereDate: upper, type: .movie), intent: filters))
        #expect(!GusLibraryMatching.accepts(MediaItem(id: "unknown", type: .movie), intent: filters))
    }

    @Test("Version and chapter choices survive as source-specific playback intent")
    func sourceSelection() throws {
        let french = MediaStreamInfo(displayTitle: "French", index: 3, type: .audio)
        let item = MediaItem(
            chapters: [.init(name: "Arrival", startPositionTicks: 40)],
            id: "cut",
            mediaSources: [.init(id: "long", mediaStreams: [french], name: "Extended", runTimeTicks: 100), .init(id: "regular", name: "Original")],
            type: .movie
        )
        let request = try GusPlaybackChoices.request(item: item, version: "extended", audio: "french", subtitle: nil, subtitlesOff: true, chapter: "Arrival", startOver: false, position: nil)
        #expect(request.streamSelection == .init(audioStreamIndex: 3, subtitleStreamIndex: -1, mediaSourceID: "long"))
        #expect(request.startPositionTicks == 40)
        #expect(request.audioTrack == french)
        #expect(throws: GusError.self) {
            try GusPlaybackChoices.request(item: item, version: "Original", audio: nil, subtitle: nil, subtitlesOff: false, chapter: "Arrival", startOver: false, position: nil)
        }
        #expect(throws: GusError.self) {
            try GusPlaybackChoices.request(item: item, version: "Original", audio: "French", subtitle: nil, subtitlesOff: false, chapter: nil, startOver: false, position: nil)
        }
        #expect(throws: GusError.self) {
            try GusPlaybackChoices.request(item: item, version: nil, audio: nil, subtitle: nil, subtitlesOff: false, chapter: nil, startOver: false, position: Int.max)
        }
    }

    @Test("Downloaded albums include only completed audio and preserve disc and track order")
    func downloadedAlbums() {
        func record(_ id: String, album: String, disc: Int, track: Int, status: DownloadStatus = .complete) -> OfflineDownloadRecord {
            let item = MediaItem(
                album: album,
                albumID: album,
                id: id,
                indexNumber: track,
                name: id,
                officialRating: "G",
                parentIndexNumber: disc,
                type: .audio
            )
            return OfflineDownloadRecord(id: id, item: item, filePath: "", byteCount: 1, serverID: "server", userID: "viewer", downloadedAt: .now, status: status)
        }
        let records = [
            record("second disc", album: "A", disc: 2, track: 1),
            record("second track", album: "A", disc: 1, track: 2),
            record("first track", album: "A", disc: 1, track: 1),
            record("queued", album: "B", disc: 1, track: 1, status: .queued),
        ]
        #expect(DownloadedLibrary.albums(in: records).compactMap(\.id) == ["A"])
        #expect(DownloadedLibrary.tracks(in: records, albumID: "A").map(\.id) == ["first track", "second track", "second disc"])
    }

    @MainActor @Test("Offline intent playback checks the downloaded file and both saved ratings in the active account")
    func persistedDownloadAccess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = OfflineDownloadFileStore(directory: directory)
        let scope = AccountScope(serverID: UUID().uuidString, userID: "viewer")
        let url = try #require(URL(string: "https://example.invalid"))
        let session = SessionStore(
            client: JellyfinClientFactory.makeClient(url: url),
            user: .init(id: scope.userID, name: "Viewer", serverID: scope.serverID),
            server: .init(id: scope.serverID, name: "Server", url: url),
            mediaProvider: FakeMediaProviderSession(capabilities: .init())
        )
        let policy = ContentRatingGate.Policy(manual: .off, hideUnrated: false, ageCeiling: .general)
        func save(_ id: String, type: MediaItemType = .movie, rating: String?, remote: MediaItem? = nil, account: AccountScope) throws -> OfflineDownloadRecord {
            let source = directory.appendingPathComponent(UUID().uuidString)
            try Data([1]).write(to: source)
            return try files.persistDownloadedFile(
                source, item: MediaItem(id: id, officialRating: rating, type: type),
                serverID: account.serverID, userID: account.userID, fileExtension: "mov",
                remoteReference: remote.map { MediaReference(item: $0, scope: account) }
            )
        }
        func download(_ id: String) -> OfflineDownloadRecord? {
            GusIntentRuntime.download(id: id, in: session, files: files, policy: policy)
        }

        let movie = try save("movie", rating: "G", account: scope)
        if !DownloadsAvailability.isSupported {
            #expect(download("movie") == nil)
            return
        }
        #expect(download("movie")?.id == movie.id)
        for type in [MediaItemType.episode, .audioBook] {
            let record = try save(type.rawValue, type: type, rating: "G", account: scope)
            #expect(download(type.rawValue)?.id == record.id)
        }
        _ = try save("restricted", rating: "R", remote: MediaItem(id: "restricted", officialRating: "G", type: .movie), account: scope)
        _ = try save("unrated", rating: nil, account: scope)
        _ = try save("reclassified", rating: "G", remote: MediaItem(id: "replacement", officialRating: "R", type: .movie), account: scope)
        #expect(download("restricted") == nil)
        #expect(download("unrated") == nil)
        #expect(download("reclassified") == nil)

        _ = try save("other-profile", rating: "G", account: .init(serverID: scope.serverID, userID: "another"))
        _ = try save("other-server", rating: "G", account: .init(serverID: "another", userID: scope.userID))
        #expect(download("other-profile") == nil)
        #expect(download("other-server") == nil)
        try FileManager.default.removeItem(atPath: movie.filePath)
        #expect(download("movie") == nil)
    }

    @MainActor @Test("Offline playback cannot be substituted for a current authentication, permission or deleted-content error")
    func offlineFallback() {
        #expect(GusIntentRuntime.canUseDownload(after: URLError(.notConnectedToInternet)))
        #expect(GusIntentRuntime.canUseDownload(after: GusError.timeout))
        for failure in [GusError.unauthorized, .forbidden, .notFound, .cancelled] {
            #expect(!GusIntentRuntime.canUseDownload(after: failure))
        }
    }

    @MainActor @Test("Bookmarks persist by account and version and replayed insertions are idempotent")
    func bookmarks() throws {
        let suite = "gus-intent-bookmarks-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = GusAudiobookBookmarks(credential: .init(serverID: "one", userID: "a"), defaults: defaults)
        let b = GusAudiobookBookmarks(credential: .init(serverID: "one", userID: "b"), defaults: defaults)
        let first = try a.add(name: " First ", itemID: "book", sourceID: "narrator-a", ticks: 20)
        #expect(try a.add(name: "First", itemID: "book", sourceID: "narrator-a", ticks: 20) == first)
        let other = try a.add(name: "First", itemID: "book", sourceID: "narrator-b", ticks: 20)
        #expect(other.id != first.id)
        #expect(try a.all().count == 2)
        #expect(try b.all().isEmpty)
        _ = try b.add(name: "My place", itemID: "book", sourceID: nil, ticks: 0)
        try a.remove(first.id)
        #expect(try a.all() == [other])
        a.forget()
        #expect(try a.all().isEmpty)
        #expect(try b.all().count == 1)
    }
}
