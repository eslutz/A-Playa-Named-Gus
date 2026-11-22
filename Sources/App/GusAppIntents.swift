import AppIntents
import Foundation

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct PlayMediaIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Media"
    static let description = IntentDescription("Searches your Jellyfin library and starts playback.", categoryName: "Playback")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Title", description: "The movie, show, song, or audiobook to play")
    var title: String

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$title)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try await GusIntentRuntime.session()
        let page = try await GusIntentRuntime.search(title, in: session, includeOffline: true)
        let found = page.items.compactMap { GusIntentRuntime.entity($0, in: session) }
        // Ask even for one exact candidate when additional results remain on the server.
        let complete = (page.totalRecordCount ?? page.items.count) <= 50
        guard !found.isEmpty else { return .result(dialog: "I couldn't find \"\(title)\" in your library.") }
        let exact = found.filter { Self.matchesTitle($0.title, title) }
        let match: GusMediaEntity
        if exact.count == 1, complete {
            match = exact[0]
        } else if complete, found.count == 1 {
            let candidate = found[0]
            try await requestConfirmation(dialog: "Open \(candidate.title), \(candidate.subtitle)?")
            match = candidate
        } else {
            let choices = exact.isEmpty ? found : exact
            guard (2 ... 10).contains(choices.count) else {
                throw GusError.server(String(localized: "Try a more specific title, or choose a library item in Shortcuts."))
            }
            let labels = choices.map { "\($0.title) · \($0.subtitle)" }
            guard Set(labels).count == labels.count else {
                throw GusError.server(String(localized: "Several items have the same details. Choose the intended item in Gus."))
            }
            let chosen = try await $title.requestDisambiguation(among: labels, dialog: "Which library item did you mean?")
            guard let index = labels.firstIndex(of: chosen) else { throw GusError.cancelled }
            match = choices[index]
        }
        let item = try await GusIntentRuntime.resolveForPlayback(match, in: session)
        try GusIntentRuntime.open(item, in: session, play: true)
        return .result(dialog: "Opening \(item.displayTitle).")
    }

    static func matchesTitle(_ name: String, _ requested: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).compare(requested.trimmingCharacters(in: .whitespacesAndNewlines), options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct FindLibraryItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find in Library"
    static let description = IntentDescription("Find up to 50 matching items to use in another action.", categoryName: "Library")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Search") var search: String
    static var parameterSummary: some ParameterSummary {
        Summary("Find \(\.$search) in the library")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[GusMediaEntity]> & ProvidesDialog {
        let session = try await GusIntentRuntime.session()
        let results = try await GusIntentRuntime.search(search, in: session, includeOffline: true).items.compactMap { GusIntentRuntime.entity($0, in: session) }
        if let first = results.first {
            return .result(value: results, dialog: "First result: \(first.title).")
        }
        return .result(value: results, dialog: "No matching library items.")
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct PlayLibraryItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Library Item"
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "Library Item") var item: GusMediaEntity
    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$item)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let session = try await GusIntentRuntime.session()
        try await GusIntentRuntime.open(GusIntentRuntime.resolveForPlayback(item, in: session), in: session, play: true)
        return .result()
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct OpenLibraryItemIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Library Item"
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "Library Item") var target: GusMediaEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let session = try await GusIntentRuntime.session()
        try await GusIntentRuntime.open(GusIntentRuntime.resolve(target, in: session), in: session, play: false)
        return .result()
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct ContinueWatchingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Watching"
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try await GusIntentRuntime.session()
        let first: MediaItem?
        do {
            let items = try await session.mediaProvider.resumeItems(limit: 50)
            try GusIntentRuntime.validate(session)
            first = ContentRatingGate.filter(items).first(where: { $0.type == .movie || $0.type == .episode })
        } catch where GusIntentRuntime.canUseDownload(after: error) && DownloadsAvailability.isSupported {
            first = try GusIntentRuntime.downloadedResume(types: [.movie, .episode], in: session)
        }
        guard let first else {
            return .result(dialog: "There’s nothing to continue watching.")
        }
        try GusIntentRuntime.open(first, in: session, play: true)
        return .result(dialog: "Opening \(first.displayTitle).")
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct PlayNextEpisodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Next Episode"
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "Series", query: GusMediaQuery(type: .series)) var series: GusMediaEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try await GusIntentRuntime.session()
        var seriesID: String?
        if let series {
            let item = try await GusIntentRuntime.resolve(series, in: session)
            guard item.type == .series, let id = item.id else { throw GusError.notFound }
            seriesID = id
        }
        let items = try await session.mediaProvider.nextUpItems(seriesID: seriesID, limit: 50)
        try GusIntentRuntime.validate(session)
        guard let first = ContentRatingGate.filter(items).first(where: { $0.type == .episode && (seriesID == nil || $0.seriesID == seriesID) }) else {
            return .result(dialog: "There’s no next episode available.")
        }
        try GusIntentRuntime.open(first, in: session, play: true)
        return .result(dialog: "Opening \(first.displayTitle).")
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct ResumeAudiobookIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Audiobook"
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try await GusIntentRuntime.session()
        guard let item = try await GusIntentRuntime.inProgressBook(.audioBook, in: session) else {
            return .result(dialog: "There’s no audiobook in progress.")
        }
        try GusIntentRuntime.open(item, in: session, play: true)
        return .result(dialog: "Opening \(item.displayTitle).")
    }
}

#if os(iOS)
    #if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
        @AppIntent(.tool)
    #endif
    struct ContinueReadingIntent: AppIntent {
        static let title: LocalizedStringResource = "Continue Reading"
        static let supportedModes: IntentModes = .foreground

        @MainActor
        func perform() async throws -> some IntentResult & ProvidesDialog {
            let session = try await GusIntentRuntime.session()
            guard let item = try await GusIntentRuntime.inProgressBook(.book, in: session) else {
                return .result(dialog: "There’s no book in progress.")
            }
            try GusIntentRuntime.open(item, in: session, play: true)
            return .result(dialog: "Opening \(item.displayTitle).")
        }
    }
#endif

private extension GusIntentRuntime {
    static func inProgressBook(_ type: MediaItemType, in session: SessionStore) async throws -> MediaItem? {
        var query = MediaItemQuery(includeTypes: [type], startIndex: 0, limit: 50, isRecursive: true, statusFilter: .resumable)
        query.mostRecentlyPlayedFirst = true
        do {
            let page = try await session.mediaProvider.items(query: query)
            try validate(session)
            return ContentRatingGate.filter(page.items).first(where: { $0.id != nil && $0.type == type })
        } catch where canUseDownload(after: error) && DownloadsAvailability.isSupported {
            return try downloadedResume(types: [type], in: session)
        }
    }

    static func downloadedResume(types: [MediaItemType], in session: SessionStore) throws -> MediaItem? {
        try validate(session)
        let scope = session.references.scope
        let records = try completedDownloads(in: session)
        let activity = NextUpActivityStore.shared.snapshot(scope: scope)
        let policy = ContentRatingGate.storedPolicy()
        let candidates = records.compactMap { record -> (MediaItem, Date)? in
            let item = record.playbackItem
            guard let id = item.id, let type = item.type, types.contains(type), item.providerKind == session.server.providerKind,
                  record.isAdmitted(by: policy.admits), !NextUpActivityStore.shared.isDismissed(item, scope: scope) else { return nil }
            if type == .book {
                guard let fraction = BookDetailMetadata.epubFraction(locator: BookProgressStore.shared.locatorJSON(forItemID: id, scope: scope)),
                      fraction > 0, fraction < 1 else { return nil }
            } else {
                guard let ticks = PlaybackChoicePosition.ticks(for: record.playbackRequest, session: session, progress: .shared, downloads: .shared),
                      ticks > 0 else { return nil }
            }
            let played = [
                OfflinePlaybackProgressStore.shared.recordedAt(forItemID: id, scope: scope, mediaSourceID: record.mediaSourceID),
                NextUpBuilder.mediaID(item).flatMap { activity[$0] },
                item.userData?.lastPlayedAt,
            ].compactMap { $0 }.max()
            return (item, played ?? .distantPast)
        }.sorted { $0.1 > $1.1 }
        guard let first = candidates.first else {
            throw GusError.server(String(localized: "You’re offline. No matching download has a saved position."))
        }
        if candidates.count > 1, first.1 == candidates[1].1 {
            throw GusError.server(String(localized: "Several downloads are in progress. Choose a title in Downloads."))
        }
        return first.0
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What’s Next"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let description = IntentDescription("Get the first ten items from your Next Up list.", categoryName: "Library")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[GusMediaEntity]> {
        let session = try await GusIntentRuntime.session()
        let home = session.homeStore()
        await home.loadNextUpForSystem()
        try GusIntentRuntime.validate(session)
        let items = home.unifiedNextUp.compactMap { entry -> GusMediaEntity? in
            if let playlist = entry.playlist {
                return GusIntentRuntime.entity(MediaItem(id: ServerMediaListID.string(playlist.id), name: playlist.name, type: .playlist), in: session)
            }
            return entry.item.flatMap { GusIntentRuntime.entity($0, in: session) }
        }
        let results = Array(items.prefix(10))
        guard let first = results.first else {
            if let error = home.errorMessage {
                throw GusError.server(error)
            }
            return .result(value: results, dialog: "There’s nothing in Next Up.")
        }
        return .result(value: results, dialog: "Up next: \(first.title).")
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct PlayPlaylistIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Playlist"
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "Playlist", query: GusMediaQuery(type: .playlist)) var playlist: GusMediaEntity
    static var parameterSummary: some ParameterSummary {
        Summary("Play playlist \(\.$playlist)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try await GusIntentRuntime.session()
        let item = try await GusIntentRuntime.resolve(playlist, in: session)
        guard item.type == .playlist else { throw GusError.notFound }
        try GusIntentRuntime.open(item, in: session, play: true)
        return .result(dialog: "Opening \(item.displayTitle).")
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct WatchLiveTVIntent: AppIntent {
    static let title: LocalizedStringResource = "Watch Live TV"
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "Channel", query: GusMediaQuery(type: .liveChannel)) var channel: GusMediaEntity
    static var parameterSummary: some ParameterSummary {
        Summary("Watch \(\.$channel)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try await GusIntentRuntime.session()
        guard try await session.mediaProvider.liveTVAvailability() == .enabled else {
            throw GusError.server(String(localized: "Live TV isn’t available for this account."))
        }
        let item = try await GusIntentRuntime.resolve(channel, in: session)
        guard item.type == .liveChannel else { throw GusError.notFound }
        try GusIntentRuntime.open(item, in: session, play: true)
        return .result(dialog: "Opening \(item.displayTitle).")
    }
}

#if !os(tvOS)
    #if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
        @AppIntent(.tool)
    #endif
    struct OpenDownloadsIntent: AppIntent {
        static let title: LocalizedStringResource = "Open Downloads"
        static let supportedModes: IntentModes = .foreground

        @MainActor
        func perform() async throws -> some IntentResult {
            _ = try await GusIntentRuntime.session()
            AppNavigationModel.shared.open(.downloaded)
            return .result()
        }
    }
#endif

struct GusAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayMediaIntent(), phrases: ["Play something in \(.applicationName)"], shortTitle: "Play Media", systemImageName: "play.fill")
        AppShortcut(intent: ContinueWatchingIntent(), phrases: ["Continue watching in \(.applicationName)"], shortTitle: "Continue Watching", systemImageName: "play.rectangle")
        AppShortcut(intent: PlayNextEpisodeIntent(), phrases: ["Play the next episode in \(.applicationName)"], shortTitle: "Play Next Episode", systemImageName: "play.square.stack")
        AppShortcut(intent: ResumeAudiobookIntent(), phrases: ["Resume my audiobook in \(.applicationName)"], shortTitle: "Resume Audiobook", systemImageName: "headphones")
        AppShortcut(intent: FindLibraryItemsIntent(), phrases: ["Find a title in \(.applicationName)"], shortTitle: "Find in Library", systemImageName: "magnifyingglass")
        AppShortcut(intent: WhatsNextIntent(), phrases: ["What’s next in \(.applicationName)"], shortTitle: "What’s Next", systemImageName: "text.line.first.and.arrowtriangle.forward")
        AppShortcut(intent: PlayPlaylistIntent(), phrases: ["Play a playlist in \(.applicationName)", "Play \(\.$playlist) in \(.applicationName)"], shortTitle: "Play Playlist", systemImageName: "list.and.film")
        #if os(iOS)
            AppShortcut(intent: ContinueReadingIntent(), phrases: ["Continue reading in \(.applicationName)"], shortTitle: "Continue Reading", systemImageName: "book")
        #endif
        AppShortcut(intent: WatchLiveTVIntent(), phrases: ["Watch live TV in \(.applicationName)", "Watch \(\.$channel) in \(.applicationName)"], shortTitle: "Watch Live TV", systemImageName: "antenna.radiowaves.left.and.right")
        #if !os(tvOS)
            AppShortcut(intent: OpenDownloadsIntent(), phrases: ["Open downloads in \(.applicationName)"], shortTitle: "Open Downloads", systemImageName: "arrow.down.circle")
        #endif
    }
}
