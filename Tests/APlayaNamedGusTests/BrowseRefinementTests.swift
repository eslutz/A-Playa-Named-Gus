import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@MainActor
@Suite("Browse refinement contracts")
struct BrowseRefinementTests {
    @Test("complete collections advance raw offsets across overlapping server pages")
    func completeCollection() async throws {
        var offsets: [Int] = []
        let items = try await MediaPageLoader.collect(pageSize: 2) { offset, _ in
            offsets.append(offset)
            switch offset {
            case 0: return MediaItemPage(items: [.init(id: "one"), .init(id: "two")], totalRecordCount: 5)
            case 2: return MediaItemPage(items: [.init(id: "two"), .init(id: "three")], totalRecordCount: 5)
            default: return MediaItemPage(items: [.init(id: "four")], totalRecordCount: 5)
            }
        }
        #expect(offsets == [0, 2, 4])
        #expect(items.map(\.id) == ["one", "two", "three", "four"])
    }

    @Test("servers ignoring pagination fail rather than spin or claim completeness")
    func repeatedPage() async {
        await #expect(throws: GusError.self) {
            _ = try await MediaPageLoader.collect(pageSize: 1) { _, _ in
                MediaItemPage(items: [.init(id: "same")], totalRecordCount: nil)
            }
        }
    }

    @Test("an empty page before the advertised total cannot silently complete a partial collection", arguments: [true, false])
    func incompleteCollection(repeatsTotal: Bool) async {
        var offsets: [Int] = []
        await #expect(throws: GusError.self) {
            _ = try await MediaPageLoader.collect(pageSize: 2) { offset, _ in
                offsets.append(offset)
                return MediaItemPage(items: offset == 0 ? [.init(id: "one"), .init(id: "two")] : [], totalRecordCount: offset == 0 || repeatsTotal ? 5 : nil)
            }
        }
        #expect(offsets == [0, 2])
    }

    @Test("raw-page validation retains omitted totals without rejecting legitimate empty lists or duplicate occurrences")
    func rawPageCompleteness() throws {
        let duplicateOccurrences = MediaItemPage(items: [.init(id: "same"), .init(id: "same")], totalRecordCount: nil)
        #expect(try MediaPageLoader.validatedTotal(for: duplicateOccurrences, startIndex: 2, previousTotal: 5) == 5)
        #expect(try MediaPageLoader.validatedTotal(for: .init(items: [], totalRecordCount: nil), startIndex: 5, previousTotal: 5) == 5)
        #expect(try MediaPageLoader.validatedTotal(for: .init(items: [], totalRecordCount: 0), startIndex: 0) == 0)
        #expect(try MediaPageLoader.validatedTotal(for: .init(items: [], totalRecordCount: nil), startIndex: 0) == nil)
        #expect(throws: GusError.self) {
            try MediaPageLoader.validatedTotal(for: .init(items: [], totalRecordCount: nil), startIndex: 2, previousTotal: 5)
        }
        #expect(throws: GusError.self) {
            try MediaPageLoader.validatedTotal(for: .init(items: [], totalRecordCount: 5), startIndex: 0)
        }
    }

    @Test("an incomplete photo album retains its opened image and loaded siblings, and retry restores the complete order")
    func incrementalPhotoCollectionRetry() async throws {
        let opened = MediaItem(id: "three", name: "Three", type: .photo)
        let first = MediaItem(id: "one", name: "One", type: .photo)
        let second = MediaItem(id: "two", name: "Two", type: .photo)
        var visible = [opened]
        var offsets: [Int] = []
        var snapshots: [[String?]] = []
        await #expect(throws: GusError.self) {
            _ = try await MediaPageLoader.collect(pageSize: 2, didLoadPage: { loaded in
                visible = PhotoSelection.includingOpened(opened, in: loaded)
                snapshots.append(visible.map(\.id))
            }) { offset, _ in
                offsets.append(offset)
                return MediaItemPage(items: offset == 0 ? [first, second] : [], totalRecordCount: offset == 0 ? 3 : nil)
            }
        }
        #expect(offsets == [0, 2])
        #expect(snapshots == [["three", "one", "two"]])
        #expect(visible.map(\.id) == ["three", "one", "two"])

        offsets = []
        _ = try await MediaPageLoader.collect(pageSize: 2, didLoadPage: { loaded in
            visible = PhotoSelection.includingOpened(opened, in: loaded)
        }) { offset, _ in
            offsets.append(offset)
            return MediaItemPage(items: offset == 0 ? [first, second] : [opened], totalRecordCount: 3)
        }
        #expect(offsets == [0, 2])
        #expect(visible.map(\.id) == ["one", "two", "three"])
        #expect(visible.contains { $0.id == opened.id })
    }

    @Test("cancellation stops complete collection before the next page")
    func collectionCancellation() async throws {
        let task = Task { @MainActor in
            try await MediaPageLoader.collect(pageSize: 1) { _, _ in
                try await Task.sleep(for: .seconds(10))
                return MediaItemPage(items: [.init(id: "late")], totalRecordCount: 2)
            }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test("episode speech keeps series, full title, locator, runtime and state")
    func episodeSemantics() {
        let episode = MediaItem(id: "pilot", indexNumber: 1, name: "Pilot", parentIndexNumber: 2, runTimeTicks: 600_000_000, seriesName: "Psych", type: .episode, userData: .init(playbackPositionTicks: 100_000_000, playedPercentage: 16, isWatched: false, isFavorite: true))
        let description = episode.mediaAccessibility
        #expect(description.label.contains("Psych"))
        #expect(description.label.contains("Pilot"))
        #expect(description.label.contains("Season 2"))
        #expect(description.label.contains("Episode 1"))
        #expect(description.value.contains("In Progress"))
        #expect(description.value.contains("remaining"))
        #expect(description.value.contains("Favorite"))
    }

    @Test("missing metadata never speaks absent values or nonfinite progress")
    func absentSemantics() {
        let item = MediaItem(id: "item", name: "Only title", userData: .init(playedPercentage: .nan))
        #expect(item.mediaAccessibility.label == "Only title")
        #expect(item.mediaAccessibility.value.isEmpty)
        #expect(item.playbackProgress == nil)
    }

    @Test("episode artwork distinguishes series portrait from its still")
    func artworkRoles() throws {
        let client = try JellyfinClientFactory.makeClient(url: #require(URL(string: "https://example.com")))
        let builder = ImageURLBuilder(client: client)
        let episode = MediaItem(backdropImageTags: ["scene"], id: "episode", imageTags: ["Primary": "still", "Thumb": "thumb"], parentBackdropImageTags: ["parent-wide"], parentBackdropItemID: "series", primaryImageAspectRatio: 16.0 / 9.0, seriesID: "series", seriesPrimaryImageTag: "poster", type: .episode)
        let poster = try #require(builder.artworkURLs(for: episode, request: .init(role: .poster, maxWidth: 200)).first)
        let stills = builder.artworkURLs(for: episode, request: .init(role: .episodeStill, maxWidth: 200))
        #expect(poster.path.contains("/Items/series/Images/Primary"))
        #expect(stills.first?.path.contains("/Items/episode/Images/Primary") == true)
        #expect(!stills.contains { $0.path.contains("/Items/series/Images/Primary") })
    }

    @Test("portrait-only episode primary never becomes a landscape still")
    func excludesPortraitFromStill() throws {
        let client = try JellyfinClientFactory.makeClient(url: #require(URL(string: "https://example.com")))
        let episode = MediaItem(id: "episode", imageTags: ["Primary": "portrait"], parentBackdropImageTags: ["wide"], parentBackdropItemID: "series", primaryImageAspectRatio: 2.0 / 3.0, type: .episode)
        let urls = ImageURLBuilder(client: client).artworkURLs(for: episode, request: .init(role: .episodeStill, maxWidth: 200))
        #expect(urls.count == 1)
        #expect(urls.first?.path.contains("/Items/series/Images/Backdrop") == true)
    }

    @Test("initial season follows resume episode with safe missing-target fallback")
    func preferredSeason() {
        let seasons: [MediaItem] = [.init(id: "one", indexNumber: 1), .init(id: "five", indexNumber: 5)]
        let episode = MediaItem(parentID: "five", parentIndexNumber: 5, type: .episode)
        #expect(SeriesRequest.initialSeasonID(from: seasons, preferredEpisode: episode) == "five")
        #expect(SeriesRequest.initialSeasonID(from: seasons, preferredEpisode: .init(parentID: "deleted", parentIndexNumber: 9)) == "one")
    }

    @Test("timer failure leaves channels available with independent retry")
    func independentLiveTV() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.liveTVAvailabilityHandler = { .enabled }
        provider.liveTVChannelsHandler = { _, _ in .init(items: [.init(id: "channel", name: "Channel", type: .liveChannel)], totalRecordCount: 1) }
        provider.liveTVTimersHandler = { throw GusError.offline }
        let store = try LiveTVStore(session: session(provider))
        await store.load()
        #expect(store.state == .loaded)
        #expect(store.channels.map(\.id) == ["channel"])
        #expect(store.sectionState(.channels) == .loaded)
        guard case .failed = store.sectionState(.scheduled) else { Issue.record("Timer error was hidden"); return }
        provider.liveTVTimersHandler = { [] }
        await store.reload(.scheduled)
        #expect(store.sectionState(.scheduled) == .loaded)
        #expect(store.channels.count == 1)
    }

    @Test("capability request failure does not claim Live TV is unconfigured")
    func liveTVCapabilityFailure() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.liveTVAvailabilityHandler = { throw GusError.offline }
        let store = try LiveTVStore(session: session(provider))
        await store.load()
        guard case .failed = store.state else { Issue.record("Capability failure was collapsed"); return }
        #expect(store.availability == nil)
    }

    @Test("Live TV loads beyond its former channel ceiling")
    func liveTVChannelContinuation() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.liveTVAvailabilityHandler = { .enabled }
        var offsets: [Int] = []
        provider.liveTVChannelsHandler = { offset, size in
            offsets.append(offset)
            return .init(items: (offset ..< min(offset + size, 201)).map { .init(id: "channel-\($0)", type: .liveChannel) }, totalRecordCount: 201)
        }
        let store = try LiveTVStore(session: session(provider))
        await store.load()
        #expect(offsets == [0, 200])
        #expect(store.channels.count == 201)
    }

    @Test("explicit saved season survives resume alignment and refresh")
    func explicitSeasonRetention() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.seasonsHandler = { [.init(id: "one", indexNumber: 1), .init(id: "five", indexNumber: 5)] }
        provider.episodesHandler = { season in .init(items: [.init(id: season + "-episode", parentID: season, seriesID: "series", type: .episode)], totalRecordCount: 1) }
        let store = try SeriesDetailStore(series: .init(id: "series", type: .series), session: session(provider), initialSeasonID: "one")
        await store.loadSeasons()
        await store.preferInitialEpisode(.init(id: "resume", parentID: "five", parentIndexNumber: 5, seriesID: "series", type: .episode))
        #expect(store.selectedSeasonID == "one")
        await store.loadSeasons()
        #expect(store.selectedSeasonID == "one")
    }

    @Test("explicit latest Name and All filter survives store recreation")
    func restoresExplicitLatestFilter() throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        let store = try LibraryStore(scope: .latest(.movies), session: session(provider), initialFilter: .default)
        #expect(store.filter == .default)
        let fresh = try LibraryStore(scope: .latest(.movies), session: session(provider))
        #expect(fresh.filter.sort == .recentlyAdded)
    }

    @Test("CarPlay pages respect native capacity and retain raw continuation offsets")
    func carPlayPagePolicy() {
        #expect(CarPlayPaging.pageSize(capacity: 12) == 9)
        #expect(CarPlayPaging.nextIndex(start: 100, rawCount: 100, total: 201, pageSize: 100) == 200)
        #expect(CarPlayPaging.nextIndex(start: 200, rawCount: 1, total: 201, pageSize: 100) == nil)
        #expect(CarPlayPaging.nextIndex(start: 100, rawCount: 0, total: 999, pageSize: 100) == nil)
    }

    @Test("CarPlay adds choices only for distinct eligible versions or audio tracks")
    func carPlayEligibleChoices() {
        let first = MediaStreamInfo(index: 2, type: .audio)
        let source = MediaSource(id: "one", mediaStreams: [first, first, .init(index: -1, type: .audio), .init(index: 3, type: .subtitle)])
        var item = MediaItem(id: "book", mediaSources: [source, source, .init(id: nil)], type: .audioBook)
        #expect(!CarPlayPlaybackChoices.requiresSelection(item))
        #expect(CarPlayPlaybackChoices.audioStreams(in: source).map(\.index) == [2])
        #expect(CarPlayPlaybackChoices.initialRequest(for: item).streamSelection.mediaSourceID == "one")
        item.mediaSources[0].mediaStreams.append(.init(index: 4, type: .audio))
        #expect(CarPlayPlaybackChoices.requiresSelection(item))
        item.mediaSources = [source, .init(id: "two")]
        #expect(CarPlayPlaybackChoices.requiresSelection(item))
    }

    @Test("CarPlay cut changes use explicit time and rematch semantic audio")
    func carPlayPlaybackIntent() throws {
        let audio = MediaStreamInfo(displayTitle: "English Commentary", index: 2, language: "eng", type: .audio)
        let first = MediaSource(id: "one", mediaStreams: [audio])
        let targetAudio = MediaStreamInfo(displayTitle: "English Commentary", index: 7, language: "eng", type: .audio)
        let second = MediaSource(id: "two", mediaStreams: [targetAudio], runTimeTicks: 100)
        let item = MediaItem(id: "book", mediaSources: [first, second], type: .audioBook)
        let selected = CarPlayPlaybackChoices.selectingAudio(audio, source: first, request: CarPlayPlaybackChoices.initialRequest(for: item))
        let changed = try #require(CarPlayPlaybackChoices.selectingSource(second, request: selected, startTicks: 40))
        #expect(changed.requestedStartTicks == 40)
        #expect(changed.streamSelection.mediaSourceID == "two")
        #expect(changed.streamSelection.audioStreamIndex == nil)
        #expect(changed.audioTrack == audio)
        #expect(changed.selection(in: second).audioStreamIndex == 7)
        #expect(CarPlayPlaybackChoices.isAudioSelected(targetAudio, source: second, request: changed))
        let unavailableSource = MediaSource(id: "missing", mediaStreams: [.init(index: 4, language: "fra", type: .audio)])
        #expect(changed.selection(in: unavailableSource).audioStreamIndex == nil)
        #expect(!CarPlayPlaybackChoices.isAudioSelected(nil, source: unavailableSource, request: changed))
        #expect(CarPlayPlaybackChoices.selectingSource(second, request: selected, startTicks: 100) == nil)
        #expect(CarPlayPlaybackChoices.selectingSource(second, request: selected, startTicks: 0)?.requestedStartTicks == 0)
        let automatic = CarPlayPlaybackChoices.selectingAudio(nil, source: second, request: changed)
        #expect(automatic.audioTrack == nil && automatic.selection(in: second).audioStreamIndex == nil)
        #expect(CarPlayPlaybackChoices.isAudioSelected(nil, source: second, request: automatic))
    }

    @Test("foreground phases distinguish initial, refresh, pagination and retained failure")
    func foregroundPhases() {
        #expect(LoadState.loading.foregroundPhase(hasContent: false) == .loading(.initial))
        #expect(LoadState.loading.foregroundPhase(hasContent: true) == .loading(.refresh))
        #expect(LoadState.loaded.foregroundPhase(hasContent: true, paging: true) == .loading(.pagination))
        #expect(LoadState.failed("offline").foregroundPhase(hasContent: true) == .failed(.refresh, "offline"))
    }

    @Test("Live TV typed capability distinguishes enabled, not configured and restricted")
    func liveTVAvailabilityStates() async throws {
        for availability in [LiveTVAvailability.enabled, .notConfigured, .restricted] {
            let provider = FakeMediaProviderSession(capabilities: .init())
            provider.liveTVAvailabilityHandler = { availability }
            var channelLoads = 0
            provider.liveTVChannelsHandler = { _, _ in channelLoads += 1; return .init(items: [], totalRecordCount: 0) }
            let store = try LiveTVStore(session: session(provider))
            await store.load()
            #expect(store.availability == availability)
            #expect(store.state == .loaded)
            #expect(channelLoads == (availability == .enabled ? 1 : 0))
        }
    }

    @Test("recording cancellation is confirmed by a fresh timer snapshot")
    func recordingCancellationOutcome() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.liveTVAvailabilityHandler = { .enabled }
        var canceled = false
        provider.liveTVTimersHandler = { canceled ? [] : [.init(id: "timer", name: "Show", channelName: nil, startDate: nil)] }
        provider.cancelLiveTVTimerHandler = { _ in canceled = true }
        let store = try LiveTVStore(session: session(provider))
        await store.load()
        await store.cancelTimer(id: "timer")
        #expect(store.timers.isEmpty)
        #expect(store.cancellationOutcomes["timer"] == .confirmed)
    }

    @Test("uncertain recording cancellation requires a read before another write")
    func uncertainRecordingCancellation() async throws {
        let provider = FakeMediaProviderSession(capabilities: .init())
        provider.liveTVAvailabilityHandler = { .enabled }
        provider.liveTVTimersHandler = { [.init(id: "timer", name: "Show", channelName: nil, startDate: nil)] }
        var writes = 0
        provider.cancelLiveTVTimerHandler = { _ in writes += 1; throw GusError.timeout }
        let store = try LiveTVStore(session: session(provider))
        await store.load()
        await store.cancelTimer(id: "timer")
        await store.cancelTimer(id: "timer")
        #expect(writes == 1)
        #expect(store.cancellationOutcomes["timer"] == .uncertain)
        #expect(!store.canCancelTimer("timer"))
        await store.reload(.scheduled)
        #expect(store.canCancelTimer("timer"))
    }

    private func session(_ provider: any MediaProviderSession) throws -> SessionStore {
        let url = try #require(URL(string: "https://example.com"))
        return SessionStore(client: JellyfinClientFactory.makeClient(url: url), user: .init(id: "user", name: "User", serverID: "server"), server: .init(id: "server", name: "Server", url: url), mediaProvider: provider)
    }
}
