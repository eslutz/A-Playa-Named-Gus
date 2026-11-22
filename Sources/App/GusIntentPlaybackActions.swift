import AppIntents
import Foundation

enum GusPlaybackOption: String, AppEnum {
    case version, audioTrack, subtitleTrack, chapter
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Playback Option"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .version: "Version", .audioTrack: "Audio Track", .subtitleTrack: "Subtitle Track", .chapter: "Chapter",
    ]
}

/// Match a spoken selection against live, source-specific metadata. Persist media choices by name;
/// a stream number from another cut cannot identify the track when the action is run again.
enum GusPlaybackChoices {
    static func versions(_ item: MediaItem) -> [(String, MediaSource)] {
        item.mediaSources.enumerated().compactMap { offset, source in
            guard source.id != nil else { return nil }
            return (source.name ?? String(localized: "Version \(offset + 1)"), source)
        }
    }

    static func tracks(_ source: MediaSource?, type: MediaStreamKind) -> [(String, MediaStreamInfo)] {
        (source?.mediaStreams ?? []).compactMap { stream in
            guard stream.type == type, let index = stream.index, index >= 0 else { return nil }
            let title = stream.displayTitle ?? stream.title ?? stream.language ?? String(localized: "Track \(index)")
            return (title, stream)
        }
    }

    static func chapters(_ item: MediaItem, source: MediaSource?) -> [(String, Int)] {
        // Jellyfin publishes one chapter list for the item, without per-version markers.
        guard source?.id == item.mediaSources.first?.id else { return [] }
        return PlaybackChapter.seekTargets(for: item).map { ($0.title, $0.startPositionTicks) }
    }

    static func select<T>(_ name: String, from choices: [(String, T)]) throws -> T {
        let matches = choices.filter { PlayMediaIntent.matchesTitle($0.0, name) }
        guard matches.count == 1 else {
            throw GusError.server(String(localized: "That playback option is unavailable or ambiguous. Get the current playback options for this title."))
        }
        return matches[0].1
    }

    static func source(named version: String?, item: MediaItem) throws -> MediaSource? {
        if let version {
            return try select(version, from: versions(item))
        }
        return item.mediaSources.first
    }

    static func request(item: MediaItem, version: String?, audio: String?, subtitle: String?, subtitlesOff: Bool, chapter: String?, startOver: Bool, position: Int?) throws -> PlaybackRequest {
        guard [.movie, .episode, .video, .trailer, .recording, .audio, .audioBook].contains(item.type) else {
            throw GusError.server(String(localized: "Choose a playable video, song, or audiobook."))
        }
        guard !subtitlesOff || subtitle == nil, [chapter != nil, startOver, position != nil].filter({ $0 }).count <= 1 else {
            throw GusError.server(String(localized: "Choose one starting position and one subtitle option."))
        }
        let source = try source(named: version, item: item)
        let audioTrack = try audio.map { try select($0, from: tracks(source, type: .audio)) }
        let subtitleTrack = try subtitle.map { try select($0, from: tracks(source, type: .subtitle)) }
        var ticks = try chapter.map { try select($0, from: chapters(item, source: source)) }
        if let position {
            let conversion = position.multipliedReportingOverflow(by: PlaybackTime.ticksPerSecond)
            guard position >= 0, !conversion.overflow else { throw GusError.server(String(localized: "Choose a valid playback position.")) }
            ticks = conversion.partialValue
        }
        if let ticks, let runtime = source?.runTimeTicks ?? item.runTimeTicks, runtime > 0, ticks >= runtime {
            throw GusError.server(String(localized: "This position is beyond the selected version’s runtime."))
        }
        let selection = PlaybackStreamSelection(
            audioStreamIndex: audioTrack?.index,
            subtitleStreamIndex: subtitlesOff ? -1 : subtitleTrack?.index,
            mediaSourceID: version != nil || audio != nil || subtitle != nil || chapter != nil ? source?.id : nil
        )
        return PlaybackRequest(
            item: item,
            streamSelection: selection,
            audioTrack: audioTrack,
            subtitleTrack: subtitleTrack,
            start: startOver ? .fromBeginning : .automatic,
            startPositionTicks: ticks
        )
    }
}

struct GetGusPlaybackOptionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Playback Options"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Library Item") var item: GusMediaEntity
    @Parameter(title: "Option") var option: GusPlaybackOption
    @Parameter(title: "Version") var version: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let session = try await GusIntentRuntime.session()
        let current = try await GusIntentRuntime.resolveForPlayback(item, in: session)
        let values: [String]
        switch option {
        case .version: values = GusPlaybackChoices.versions(current).map(\.0)
        case .chapter:
            let source = try GusPlaybackChoices.source(named: version, item: current)
            values = GusPlaybackChoices.chapters(current, source: source).map(\.0)
        case .audioTrack, .subtitleTrack:
            let source = try GusPlaybackChoices.source(named: version, item: current)
            values = GusPlaybackChoices.tracks(source, type: option == .audioTrack ? .audio : .subtitle).map(\.0)
        }
        return .result(value: values)
    }
}

struct PlayGusWithOptionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Play with Options"
    static let description = IntentDescription("Play a video or audio title with a specific cut, track, subtitle, chapter, or starting position. Use Get Playback Options to retrieve supported names.", categoryName: "Playback")
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "Library Item") var item: GusMediaEntity
    @Parameter(title: "Version") var version: String?
    @Parameter(title: "Audio Track") var audioTrack: String?
    @Parameter(title: "Subtitle Track") var subtitleTrack: String?
    @Parameter(title: "Turn Off Subtitles", default: false) var subtitlesOff: Bool
    @Parameter(title: "Starting Chapter") var chapter: String?
    @Parameter(title: "Start Over", default: false) var startOver: Bool
    @Parameter(title: "Start at Second") var position: Int?

    @MainActor
    func perform() async throws -> some IntentResult {
        let session = try await GusIntentRuntime.session()
        let current = try await GusIntentRuntime.resolveForPlayback(item, in: session)
        let request = try GusPlaybackChoices.request(
            item: current,
            version: version,
            audio: audioTrack,
            subtitle: subtitleTrack,
            subtitlesOff: subtitlesOff,
            chapter: chapter,
            startOver: startOver,
            position: position
        )
        try GusIntentRuntime.open(current, in: session, play: true, request: request)
        return .result()
    }
}

struct GetGusProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Completion Percentage"
    static let description = IntentDescription("Return the active profile’s progress from 0 to 100 for a video, book, song, or audiobook.", categoryName: "Library")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Library Item") var item: GusMediaEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        let session = try await GusIntentRuntime.session()
        let current = try await GusIntentRuntime.resolveForPlayback(item, in: session)
        guard [.movie, .episode, .video, .trailer, .recording, .audio, .audioBook, .book].contains(current.type) else {
            throw GusError.server(String(localized: "Choose an item with a playback or reading position."))
        }
        if current.type == .book, let id = current.id,
           let fraction = BookDetailMetadata.epubFraction(locator: BookProgressStore.shared.locatorJSON(forItemID: id, scope: session.references.scope)), fraction.isFinite
        {
            return .result(value: min(100, max(0, fraction * 100)))
        }
        let request = PlaybackRequest(item: current)
        let ticks = PlaybackChoicePosition.ticks(for: request, session: session, progress: .shared, downloads: .shared)
        if let ticks, let runtime = current.runTimeTicks, runtime > 0 {
            return .result(value: min(100, 100 * Double(ticks) / Double(runtime)))
        }
        if current.userData?.isWatched == true {
            return .result(value: 100)
        }
        return .result(value: 100 * (current.playbackProgress ?? 0))
    }
}

#if !os(tvOS)
    struct PrepareGusSharePlayIntent: AppIntent {
        static let title: LocalizedStringResource = "Prepare SharePlay"
        static let description = IntentDescription("Open the system SharePlay sheet for this title so you can choose participants.", categoryName: "Playback")
        static let supportedModes: IntentModes = .foreground
        @Parameter(title: "Library Item") var item: GusMediaEntity

        @MainActor
        func perform() async throws -> some IntentResult {
            let session = try await GusIntentRuntime.session()
            let current = try await GusIntentRuntime.resolve(item, in: session)
            guard SharePlayCoordinator.canShare(current), let id = current.id else {
                throw GusError.server(String(localized: "This item can't be shared with SharePlay."))
            }
            AppNavigationModel.shared.prepareSharePlay(itemID: id, for: session)
            return .result()
        }
    }
#endif

#if os(visionOS)
    struct PlayGusSpatialVideoIntent: AppIntent {
        static let title: LocalizedStringResource = "Play Spatial Video"
        static let description = IntentDescription("Open a supported stereoscopic video in Gus on Apple Vision Pro.", categoryName: "Playback")
        static let supportedModes: IntentModes = .foreground
        @Parameter(title: "Library Item") var item: GusMediaEntity

        @MainActor
        func perform() async throws -> some IntentResult {
            let session = try await GusIntentRuntime.session()
            let current = try await GusIntentRuntime.resolveForPlayback(item, in: session)
            let presentation = Media3DDetector.presentation(for: current)
            guard presentation.showsSpatialBadge || presentation.usesImmersiveFramePackedRenderer else {
                throw GusError.server(String(localized: "This video doesn’t have a supported spatial format."))
            }
            try GusIntentRuntime.open(current, in: session, play: true)
            return .result()
        }
    }
#endif
