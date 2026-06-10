import Foundation
import JellyfinAPI

@MainActor
final class JellyfinMediaProviderSession: MediaProviderSession {
    let providerKind: MediaProviderKind = .jellyfin
    let capabilities = ProviderCapabilities()

    private let client: JellyfinClient
    private let userID: String
    private let imageBuilder: ImageURLBuilder
    private let streamBuilder: StreamURLBuilder

    init(client: JellyfinClient, userID: String) {
        self.client = client
        self.userID = userID
        imageBuilder = ImageURLBuilder(client: client)
        streamBuilder = StreamURLBuilder(client: client, userID: userID)
    }

    func userViews() async throws -> [MediaItem] {
        let parameters = Paths.GetUserViewsParameters(userID: userID)
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getUserViews(parameters: parameters))
        }
        return JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? [])
    }

    func resumeItems(limit: Int) async throws -> [MediaItem] {
        let parameters = Paths.GetResumeItemsParameters(
            userID: userID,
            limit: limit,
            fields: Self.metadataFields,
            enableUserData: true,
            includeItemTypes: [.movie, .episode],
            enableImages: true
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getResumeItems(parameters: parameters))
        }
        return JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? [])
    }

    func nextUpItems(seriesID: String? = nil, limit: Int) async throws -> [MediaItem] {
        let parameters = Paths.GetNextUpParameters(
            userID: userID,
            startIndex: 0,
            limit: limit,
            fields: Self.playbackMetadataFields,
            seriesID: seriesID,
            enableImages: true,
            enableUserData: true,
            enableTotalRecordCount: true,
            enableResumable: true
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getNextUp(parameters: parameters))
        }
        return JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? [])
    }

    func latestMedia(in library: MediaItem, limit: Int) async throws -> [MediaItem] {
        let parameters = Paths.GetLatestMediaParameters(
            userID: userID,
            parentID: library.id,
            fields: [.primaryImageAspectRatio],
            enableImages: true,
            enableUserData: true,
            limit: limit,
            isGroupItems: library.collectionType == .tvshows
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getLatestMedia(parameters: parameters))
        }
        return JellyfinMediaItemMapper.mediaItems(from: response.value)
    }

    func items(query: MediaItemQuery) async throws -> MediaItemPage {
        let parameters = Paths.GetItemsParameters(
            userID: userID,
            startIndex: query.startIndex,
            limit: query.limit,
            isRecursive: query.artistID != nil || query.includeTypes != nil ? true : query.isRecursive,
            searchTerm: query.searchTerm,
            sortOrder: sortOrder(for: query.sort),
            parentID: query.parentID,
            fields: Self.playbackMetadataFields,
            includeItemTypes: includeItemKinds(for: query),
            filters: filters(for: query.statusFilter),
            sortBy: sortBy(for: query.sort),
            enableUserData: true,
            artistIDs: query.artistID.map { [$0] },
            enableTotalRecordCount: true,
            enableImages: true
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getItems(parameters: parameters))
        }
        return MediaItemPage(
            items: JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? []),
            totalRecordCount: response.value.totalRecordCount
        )
    }

    func item(id: String) async throws -> MediaItem {
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getItem(itemID: id, userID: userID))
        }
        return JellyfinMediaItemMapper.mediaItem(from: response.value)
    }

    func similarItems(itemID: String, limit: Int) async throws -> [MediaItem] {
        let parameters = Paths.GetSimilarItemsParameters(
            userID: userID,
            limit: limit,
            fields: Self.metadataFields
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getSimilarItems(itemID: itemID, parameters: parameters))
        }
        return JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? [])
    }

    func specialFeatures(itemID: String) async throws -> [MediaItem] {
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getSpecialFeatures(itemID: itemID, userID: userID))
        }
        return JellyfinMediaItemMapper.mediaItems(from: response.value)
    }

    func seasons(seriesID: String) async throws -> [MediaItem] {
        let parameters = Paths.GetSeasonsParameters(
            userID: userID,
            fields: Self.metadataFields,
            enableImages: true,
            enableUserData: true
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getSeasons(seriesID: seriesID, parameters: parameters))
        }
        return JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? [])
    }

    func episodes(seriesID: String, seasonID: String, limit: Int) async throws -> [MediaItem] {
        let parameters = Paths.GetEpisodesParameters(
            userID: userID,
            fields: Self.metadataFields,
            seasonID: seasonID,
            startIndex: 0,
            limit: limit,
            enableImages: true,
            enableUserData: true,
            sortBy: .indexNumber
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters))
        }
        return JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? [])
    }

    func primaryImageURL(for item: MediaItem, context: ImageURLBuilder.ImageContext) -> URL? {
        imageBuilder.primaryImageURL(for: item, context: context)
    }

    func primaryImageURL(for item: MediaItem, maxWidth: Int) -> URL? {
        imageBuilder.primaryImageURL(for: item, maxWidth: maxWidth)
    }

    func backdropImageURL(for item: MediaItem, context: ImageURLBuilder.ImageContext) -> URL? {
        imageBuilder.backdropImageURL(for: item, context: context)
    }

    func backdropImageURL(for item: MediaItem, maxWidth: Int) -> URL? {
        imageBuilder.backdropImageURL(for: item, maxWidth: maxWidth)
    }

    func personImageURL(for person: MediaPerson, maxWidth: Int) -> URL? {
        imageBuilder.personImageURL(for: person, maxWidth: maxWidth)
    }

    func resolvePlayback(
        for itemID: String,
        maxStreamingBitrate: Int,
        streamSelection: PlaybackStreamSelection,
        startTimeTicks: Int?,
        stereoLayout: Stereo3DLayout
    ) async throws -> PlaybackSourceResolution {
        let resolution = try await streamBuilder.resolvePlayback(
            for: itemID,
            maxStreamingBitrate: maxStreamingBitrate,
            streamSelection: streamSelection,
            startTimeTicks: startTimeTicks,
            stereoLayout: stereoLayout
        )
        return PlaybackSourceResolution(
            url: resolution.url,
            playSessionID: resolution.playSessionID,
            mediaSourceID: resolution.mediaSourceID,
            playMethod: resolution.isTranscoding ? .transcode : .directStream,
            stereoLayout: resolution.stereoLayout,
            stereoFallbackReason: resolution.stereoFallbackReason
        )
    }

    func resolveAudioPlayback(for itemID: String) async throws -> PlaybackSourceResolution {
        let url = try streamBuilder.universalAudioURL(for: itemID)
        return PlaybackSourceResolution(
            url: url,
            playSessionID: nil,
            mediaSourceID: nil,
            playMethod: .directStream,
            stereoLayout: .none,
            stereoFallbackReason: nil
        )
    }

    func downloadSource(for item: MediaItem) async throws -> DownloadSourceResolution {
        let source = try await DownloadSourceResolver(client: client, userID: userID).resolve(for: item)
        guard let url = client.url(with: source.request, queryAPIKey: true) else {
            throw DownloadSourceResolver.ResolverError.noMediaSource
        }
        return DownloadSourceResolution(
            url: url,
            fileExtension: source.fileExtension,
            requiresTranscoding: source.kind == .transcoded
        )
    }

    // MARK: - Live TV

    func liveTVIsEnabled() async -> Bool {
        guard let info = try? await client.send(Paths.getLiveTvInfo).value else { return false }
        guard info.isEnabled == true else { return false }
        if let enabledUsers = info.enabledUsers, !enabledUsers.isEmpty {
            return enabledUsers.contains(userID)
        }
        return true
    }

    func liveTVChannels(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        let parameters = Paths.GetLiveTvChannelsParameters(
            userID: userID,
            startIndex: startIndex,
            limit: limit,
            isAddCurrentProgram: true
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getLiveTvChannels(parameters: parameters))
        }
        return MediaItemPage(
            items: JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? []),
            totalRecordCount: response.value.totalRecordCount
        )
    }

    func liveTVRecordings(limit: Int) async throws -> [MediaItem] {
        let parameters = Paths.GetRecordingsParameters(
            userID: userID,
            limit: limit,
            fields: Self.playbackMetadataFields
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getRecordings(parameters: parameters))
        }
        return JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? [])
    }

    func liveTVTimers() async throws -> [LiveTVTimer] {
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getTimers())
        }
        return (response.value.items ?? []).compactMap { timer in
            guard let id = timer.id else { return nil }
            return LiveTVTimer(
                id: id,
                name: timer.name ?? String(localized: "Recording", comment: "Fallback scheduled recording name"),
                channelName: timer.channelName,
                startDate: timer.startDate
            )
        }
    }

    func cancelLiveTVTimer(id: String) async throws {
        try await client.send(Paths.cancelTimer(timerID: id))
    }

    func reportPlaybackStart(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws {
        try await client.send(
            Paths.reportPlaybackStart(
                playbackStateInfo(for: context, positionTicks: positionTicks, isPaused: isPaused)
            )
        )
    }

    func reportPlaybackProgress(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws {
        try await client.send(
            Paths.reportPlaybackProgress(
                playbackStateInfo(for: context, positionTicks: positionTicks, isPaused: isPaused)
            )
        )
    }

    func reportPlaybackStopped(context: PlaybackReportContext, positionTicks: Int) async throws {
        try await client.send(
            Paths.reportPlaybackStopped(
                PlaybackStopInfo(
                    isFailed: false,
                    itemID: context.itemID,
                    mediaSourceID: context.mediaSourceID,
                    playSessionID: context.playSessionID,
                    positionTicks: positionTicks
                )
            )
        )
    }

    // MARK: - Book reading progress

    func reportBookProgress(itemID: String, fraction: Double) async throws {
        try await client.send(
            Paths.updateItemUserData(
                itemID: itemID,
                userID: userID,
                UpdateUserItemDataDto(playbackPositionTicks: JellyfinBookProgress.ticks(forFraction: fraction))
            )
        )
    }

    func bookProgress(itemID: String) async throws -> Double? {
        let data = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getItemUserData(itemID: itemID, userID: userID))
        }.value
        // PlayedPercentage is the server-derived scalar (runtime-independent); fall back
        // to the raw ticks if an older server omits it.
        if let percentage = data.playedPercentage {
            return percentage / 100
        }
        if let ticks = data.playbackPositionTicks, ticks > 0 {
            return JellyfinBookProgress.fraction(forTicks: ticks)
        }
        return nil
    }

    private static let metadataFields: [ItemFields] = [
        .primaryImageAspectRatio,
        .overview,
        .genres,
        .people,
        .studios,
        .taglines,
    ]

    private static let playbackMetadataFields: [ItemFields] = metadataFields + [
        .canDownload,
        .mediaStreams,
        .chapters,
    ]

    private func sortBy(for sort: MediaItemSort?) -> [ItemSortBy]? {
        guard let sort else { return nil }

        switch sort {
        case .name:
            return [.sortName]
        case .recentlyAdded:
            return [.dateCreated]
        case .releaseDate:
            return [.premiereDate]
        case .rating:
            return [.communityRating]
        case .random:
            return [.random]
        case .trackOrder:
            return [.parentIndexNumber, .indexNumber, .sortName]
        }
    }

    private func sortOrder(for sort: MediaItemSort?) -> [JellyfinAPI.SortOrder]? {
        guard let sort else { return nil }

        switch sort {
        case .name, .trackOrder:
            return [.ascending]
        case .recentlyAdded, .releaseDate, .rating:
            return [.descending]
        case .random:
            return nil
        }
    }

    private func includeItemKinds(for query: MediaItemQuery) -> [BaseItemKind]? {
        if let includeTypes = query.includeTypes {
            let kinds = includeTypes.compactMap(Self.baseItemKind(for:))
            return kinds.isEmpty ? nil : kinds
        }
        // Artist queries return that artist's albums unless the caller asked otherwise.
        return query.artistID != nil ? [.musicAlbum] : nil
    }

    private static func baseItemKind(for type: MediaItemType) -> BaseItemKind? {
        switch type {
        case .movie: return .movie
        case .episode: return .episode
        case .series: return .series
        case .season: return .season
        case .collectionFolder: return .collectionFolder
        case .folder: return .folder
        case .trailer: return .trailer
        case .video: return .video
        case .audio: return .audio
        case .musicArtist: return .musicArtist
        case .musicAlbum: return .musicAlbum
        case .playlist: return .playlist
        case .book: return .book
        case .audioBook: return .audioBook
        case .photo: return .photo
        case .liveChannel: return .tvChannel
        case .liveProgram: return .tvProgram
        case .recording: return .recording
        case .unknown: return nil
        }
    }

    private func filters(for status: MediaItemStatusFilter) -> [ItemFilter]? {
        switch status {
        case .all:
            return nil
        case .unplayed:
            return [.isUnplayed]
        case .played:
            return [.isPlayed]
        case .resumable:
            return [.isResumable]
        }
    }

    private func playbackStateInfo(
        for context: PlaybackReportContext,
        positionTicks: Int,
        isPaused: Bool
    ) -> PlaybackStateInfo {
        PlaybackStateInfo(
            audioStreamIndex: context.streamSelection.audioStreamIndex,
            canSeek: true,
            isMuted: false,
            isPaused: isPaused,
            itemID: context.itemID,
            mediaSourceID: context.mediaSourceID,
            playMethod: playMethod(for: context.playMethod),
            playSessionID: context.playSessionID,
            positionTicks: positionTicks,
            subtitleStreamIndex: context.streamSelection.subtitleStreamIndex
        )
    }

    private func playMethod(for method: MediaPlaybackMethod) -> PlayMethod {
        switch method {
        case .directPlay:
            return .directPlay
        case .directStream:
            return .directStream
        case .transcode:
            return .transcode
        }
    }
}
