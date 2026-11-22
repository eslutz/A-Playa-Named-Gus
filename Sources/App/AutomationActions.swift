import AppIntents
import Foundation

/// A shortcut can branch on the actual outcome of a write. Acknowledgement from a
/// server and independent readback are separate states throughout Gus.
enum GusActionStatus: String, AppEnum {
    case queued, inProgress, accepted, confirmed, uncertain, paused

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Action Status"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .queued: "Queued", .inProgress: "In Progress", .accepted: "Accepted",
        .confirmed: "Confirmed", .uncertain: "Not Confirmed", .paused: "Paused",
    ]

    init(_ outcome: ActionOutcome?, failure: String? = nil) throws {
        switch outcome {
        case .queued: self = .queued
        case .pending: self = .inProgress
        case .accepted: self = .accepted
        case .confirmed: self = .confirmed
        case .uncertain: self = .uncertain
        case let .failed(error): throw error
        case nil: throw GusError.server(failure ?? String(localized: "The action could not be completed."))
        }
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct SetGusFavoriteIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Favorite Status"
    static let description = IntentDescription("Adds or removes a favorite for the active Jellyfin profile.", categoryName: "Library")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Library Item") var item: GusMediaEntity
    @Parameter(title: "Favorite", default: true) var favorite: Bool

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<GusActionStatus> {
        let session = try await GusIntentRuntime.session()
        let current = try await GusIntentRuntime.resolve(item, in: session)
        guard current.userData?.isFavorite != favorite else { return .result(value: .confirmed) }
        let detail = ItemDetailStore(item: current, session: session)
        await detail.setFavorite(favorite)
        try GusIntentRuntime.validate(session)
        return try .result(value: GusActionStatus(detail.actionOutcome, failure: detail.actionError))
    }
}

struct SetGusCompletionIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Completion Status"
    static let description = IntentDescription("Marks an item finished or unfinished for this profile. Changing completion resets its saved position.", categoryName: "Library")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Library Item") var item: GusMediaEntity
    @Parameter(title: "Finished", default: true) var finished: Bool

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<GusActionStatus> {
        let session = try await GusIntentRuntime.session()
        let current = try await GusIntentRuntime.resolve(item, in: session)
        switch current.type {
        case .movie, .episode, .video, .trailer, .audio, .audioBook, .book, .recording: break
        default: throw GusError.server(String(localized: "Choose an item with a playback or reading position."))
        }
        guard current.userData?.isWatched != finished else { return .result(value: .confirmed) }
        let detail = ItemDetailStore(item: current, session: session)
        await detail.setWatched(finished)
        try GusIntentRuntime.validate(session)
        return try .result(value: GusActionStatus(detail.actionOutcome, failure: detail.actionError))
    }
}

struct FindGusRelatedIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Similar Library Items"
    static let description = IntentDescription("Returns titles related to a library item from the current server.", categoryName: "Library")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Library Item") var item: GusMediaEntity

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[GusMediaEntity]> {
        let session = try await GusIntentRuntime.session()
        let current = try await GusIntentRuntime.resolve(item, in: session)
        guard let id = current.id else { throw GusError.notFound }
        let similar = try await session.mediaProvider.similarItems(itemID: id, limit: 25)
        try GusIntentRuntime.validate(session)
        return .result(value: ContentRatingGate.filter(similar).compactMap { GusIntentRuntime.entity($0, in: session) })
    }
}

#if !os(tvOS)
    enum GusDownloadOperation: String, AppEnum {
        case download, pause, resume, status

        static let typeDisplayRepresentation: TypeDisplayRepresentation = "Download Action"
        static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
            .download: "Download", .pause: "Pause", .resume: "Resume", .status: "Get Status",
        ]
    }

    #if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
        @AppIntent(.tool)
    #endif
    struct ManageGusDownloadIntent: AppIntent {
        static let title: LocalizedStringResource = "Manage Download"
        static let description = IntentDescription("Downloads an item, controls a transfer, or returns its current state on this device.", categoryName: "Downloads")
        static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

        @Parameter(title: "Library Item") var item: GusMediaEntity
        @Parameter(title: "Action", default: .download) var action: GusDownloadOperation

        @MainActor func perform() async throws -> some IntentResult & ReturnsValue<GusActionStatus> {
            let session = try await GusIntentRuntime.session()
            let downloads = OfflineDownloadStore.shared
            let scope = session.references.scope
            downloads.load(serverID: scope.serverID, userID: scope.userID)
            if let failure = downloads.loadErrorMessage {
                throw GusError.server(failure)
            }
            // Status and pause also work when the server is unreachable. The saved
            // record must belong to this profile and pass today's content policy.
            let record = downloads.records.first { record in
                record.serverID == scope.serverID && record.userID == scope.userID &&
                    record.isAdmitted(by: ContentRatingGate.storedPolicy().admits) &&
                    GusIntentRuntime.entity(record.item, in: session)?.id == item.id
            }
            switch action {
            case .download:
                let current = try await GusIntentRuntime.resolve(item, in: session)
                guard session.mediaProvider.capabilities.supportsDownloads, OfflineDownloadEligibility.canDownload(current) else {
                    throw GusError.server(String(localized: "This item is not available for download."))
                }
                await downloads.download(PlaybackRequest(item: current), session: session)
            case .pause:
                guard let record, let id = record.item.id else { throw GusError.notFound }
                if record.status.isActive {
                    await downloads.pause(itemID: id)
                }
            case .resume:
                guard let record else { throw GusError.notFound }
                if record.status == .paused {
                    await downloads.resume(record, session: session)
                }
            case .status: break
            }
            try GusIntentRuntime.validate(session)
            guard let snapshot = downloads.records.first(where: { record in
                record.serverID == scope.serverID && record.userID == scope.userID &&
                    record.isAdmitted(by: ContentRatingGate.storedPolicy().admits) &&
                    GusIntentRuntime.entity(record.item, in: session)?.id == item.id
            }) else { throw GusError.server(downloads.errorMessage ?? String(localized: "No download was found for this item.")) }
            if snapshot.status.isComplete, downloads.localFileURL(for: snapshot.item, serverID: scope.serverID, userID: scope.userID) == nil {
                throw GusError.server(String(localized: "The downloaded file is missing."))
            }
            return try .result(value: snapshot.status == .paused ? .paused : GusActionStatus(snapshot.status.actionOutcome))
        }
    }
#endif

#if os(iOS)
    enum GusAudioCommand: String, AppEnum {
        case play, pause, next, previous, skipForward, skipBack, restart
        static let typeDisplayRepresentation: TypeDisplayRepresentation = "Audio Command"
        static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
            .play: "Play", .pause: "Pause", .next: "Next Track", .previous: "Previous Track",
            .skipForward: "Skip Forward 30 Seconds", .skipBack: "Skip Back 15 Seconds", .restart: "Start Over",
        ]
    }

    struct ControlGusAudioIntent: AppIntent {
        static let title: LocalizedStringResource = "Control Current Audio"
        static let description = IntentDescription("Controls the music or audiobook playing in Gus on this device.", categoryName: "Playback")
        static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
        @Parameter(title: "Command") var command: GusAudioCommand

        @MainActor func perform() async throws -> some IntentResult {
            let session = try await GusIntentRuntime.session()
            let coordinator = AppModel.shared.audioPlayback
            guard let store = coordinator.store, store.state == .loaded, let current = store.currentTrack,
                  ContentRatingGate.admitsStored(current) else { throw GusError.server(String(localized: "No audio player is ready on this device.")) }
            switch command {
            case .play:
                if !store.isPlaybackRequested {
                    store.playPause()
                }
            case .pause:
                if store.isPlaybackRequested {
                    store.playPause()
                }
            case .next:
                guard store.hasNext else { throw GusError.server(String(localized: "The queue has no next track.")) }
                await store.next()
            case .previous: await store.previous()
            case .skipForward: await store.seek(to: min(store.duration > 0 ? store.duration : .greatestFiniteMagnitude, store.currentTime + 30))
            case .skipBack: await store.seek(to: max(0, store.currentTime - 15))
            case .restart: await store.seek(to: 0)
            }
            try GusIntentRuntime.validate(session)
            guard coordinator.store === store else { throw GusError.cancelled }
            if case let .failed(message) = store.state {
                throw GusError.server(message)
            }
            if let failure = store.queueErrorMessage, command == .next {
                throw GusError.server(failure)
            }
            return .result()
        }
    }

    struct SetGusAudioSpeedIntent: AppIntent {
        static let title: LocalizedStringResource = "Set Audio Playback Speed"
        static let description = IntentDescription("Sets the speed of the current music or audiobook player.", categoryName: "Playback")
        static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
        @Parameter(title: "Speed", default: 1) var speed: Double

        @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Double> {
            _ = try await GusIntentRuntime.session()
            guard let player = AppModel.shared.audioPlayback.store, player.state == .loaded,
                  let current = player.currentTrack, ContentRatingGate.admitsStored(current)
            else {
                throw GusError.server(String(localized: "No audio player is ready on this device."))
            }
            guard speed.isFinite, (0.5 ... 2).contains(speed) else {
                throw GusError.server(String(localized: "Choose a playback speed between 0.5 and 2."))
            }
            player.playbackRate = speed
            return .result(value: player.playbackRate)
        }
    }
#endif

enum GusChapterAction: String, AppEnum {
    case next, previous, numbered
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Chapter Action"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.next: "Next Chapter", .previous: "Previous Chapter", .numbered: "Chapter Number"]

    func target(in chapters: [PlaybackChapter], at seconds: Double, number: Int?) -> PlaybackChapter? {
        switch self {
        case .next: chapters.first { $0.seconds > seconds + 0.25 }
        case .previous: chapters.last { $0.seconds < seconds - 1 }
        case .numbered:
            if let number, number > 0, number <= chapters.count {
                chapters[number - 1]
            } else {
                nil
            }
        }
    }
}

struct GetGusChaptersIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Library Item Chapters"
    static let description = IntentDescription("Returns chapter titles in playback order for a movie, episode, or audiobook.", categoryName: "Playback")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Library Item") var item: GusMediaEntity

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let session = try await GusIntentRuntime.session()
        let current = try await GusIntentRuntime.resolve(item, in: session)
        return .result(value: PlaybackChapter.seekTargets(for: current).map(\.title))
    }
}

struct PlayGusChapterIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Library Item from Chapter"
    static let description = IntentDescription("Opens a library item at the start of its numbered chapter.", categoryName: "Playback")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "Library Item") var item: GusMediaEntity
    @Parameter(title: "Chapter Number", default: 1) var number: Int

    @MainActor func perform() async throws -> some IntentResult {
        let session = try await GusIntentRuntime.session()
        let current = try await GusIntentRuntime.resolve(item, in: session)
        let request = try Self.request(for: current, number: number)
        try GusIntentRuntime.open(current, in: session, play: true, request: request)
        return .result()
    }

    static func request(for item: MediaItem, number: Int) throws -> PlaybackRequest {
        guard item.id != nil, item.isAudioPlayable || [.movie, .episode, .recording, .video, .trailer].contains(item.type),
              let source = item.mediaSources.first, let sourceID = source.id,
              let chapter = GusChapterAction.numbered.target(in: GusPlaybackChoices.chapters(item, source: source), at: 0, number: number) else { throw GusError.notFound }
        return PlaybackRequest(
            item: item, streamSelection: .init(audioStreamIndex: nil, subtitleStreamIndex: nil, mediaSourceID: sourceID),
            startPositionTicks: chapter.startPositionTicks
        )
    }
}

struct SeekGusCurrentChapterIntent: AppIntent {
    static let title: LocalizedStringResource = "Change Current Chapter"
    static let description = IntentDescription("Seeks within the audiobook or video currently owning playback on this device.", categoryName: "Playback")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Action", default: .next) var action: GusChapterAction
    @Parameter(title: "Chapter Number") var number: Int?

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let session = try await GusIntentRuntime.session()
        let (audio, video) = NowPlayingController.chapterPlayers(for: session)
        let chapter: PlaybackChapter?
        if let audio, audio.state == .loaded, let track = audio.currentTrack, ContentRatingGate.admitsStored(track) {
            chapter = action.target(in: audio.chapterTargets, at: audio.currentTime, number: number)
            if let chapter {
                guard let nativeItem = audio.nativePlayer?.currentItem, await audio.seek(to: chapter) else { throw GusError.cancelled }
                try GusIntentRuntime.validate(session)
                guard NowPlayingController.chapterPlayers(for: session).0 === audio, audio.state == .loaded,
                      audio.nativePlayer?.currentItem === nativeItem, audio.currentTrack?.id == track.id,
                      abs(audio.currentTime - chapter.seconds) <= 2, ContentRatingGate.admitsStored(track) else { throw GusError.cancelled }
            }
        } else if let video, video.state == .ready, ContentRatingGate.admitsStored(video.item) {
            let itemID = video.item.id
            chapter = action.target(in: video.chapterTargets, at: PlaybackTime.seconds(fromTicks: video.positionTicks), number: number)
            if let chapter {
                guard let nativeItem = video.player?.currentItem, await video.seek(to: chapter) else { throw GusError.cancelled }
                try GusIntentRuntime.validate(session)
                guard NowPlayingController.chapterPlayers(for: session).1 === video, video.state == .ready,
                      video.player?.currentItem === nativeItem, video.item.id == itemID,
                      abs(PlaybackTime.seconds(fromTicks: video.positionTicks) - chapter.seconds) <= 2,
                      ContentRatingGate.admitsStored(video.item) else { throw GusError.cancelled }
            }
        } else {
            throw GusError.server(String(localized: "No chaptered player is ready on this device."))
        }
        guard let chapter else { throw GusError.server(String(localized: "That chapter is unavailable.")) }
        return .result(value: chapter.title)
    }
}

struct StartGusSlideshowIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Photo Slideshow"
    static let description = IntentDescription("Starts Gus’s photo viewer at a selected photo or the first accessible photo in an album.", categoryName: "Photos")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "Photo or Album") var item: GusMediaEntity

    @MainActor func perform() async throws -> some IntentResult {
        let session = try await GusIntentRuntime.session()
        let current = try await GusIntentRuntime.resolve(item, in: session)
        let photo: MediaItem
        if current.type == .photo {
            photo = current
        } else if current.type == .photoAlbum, let id = current.id {
            let children = try await session.mediaProvider.allItems(query: .init(parentID: id, includeTypes: [.photo], startIndex: 0, limit: 200, sort: .name))
            try GusIntentRuntime.validate(session)
            guard ContentRatingGate.admitsStored(current), let first = children.first(where: {
                $0.type == .photo && $0.id != nil && $0.parentID == id && ContentRatingGate.admitsStored($0)
            }) else { throw GusError.server(String(localized: "No accessible photos were found in this album.")) }
            photo = first
        } else {
            throw GusError.server(String(localized: "Choose a photo or photo album."))
        }
        guard let id = photo.id, let parent = photo.parentID, !parent.isEmpty else { throw GusError.notFound }
        var request = PlaybackRequest(item: photo)
        request.slideshowAlbumID = parent
        AppNavigationModel.shared.open(.play(id: id, serverID: session.server.id, provider: session.server.providerKind, request: request), for: session)
        return .result()
    }
}
