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
    private var bookSeriesEditingEnabled = false
    private var editingBookIDs = Set<UUID>()

    init(client: JellyfinClient, userID: String) {
        self.client = client
        self.userID = userID
        imageBuilder = ImageURLBuilder(client: client)
        streamBuilder = StreamURLBuilder(client: client, userID: userID)
    }

    func userViews() async throws -> [MediaItem] {
        let parameters = Paths.GetUserViewsParameters(userID: userID)
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getUserViews(parameters: parameters).withResponse(JellyfinLibraryViews.self))
        }
        return response.value.items.map(\.item)
    }

    func resumeItems(limit: Int) async throws -> [MediaItem] {
        try await resumeItemsPage(startIndex: 0, limit: limit).items
    }

    func resumeItemsPage(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        let parameters = Paths.GetResumeItemsParameters(
            userID: userID,
            startIndex: startIndex,
            limit: limit,
            fields: Self.playbackMetadataFields,
            mediaTypes: [.video],
            enableUserData: true,
            includeItemTypes: [.movie, .episode],
            enableTotalRecordCount: true,
            enableImages: true
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.browse(Paths.getResumeItems(parameters: parameters))
        }
        return MediaItemPage(items: JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? []), totalRecordCount: response.value.totalRecordCount)
    }

    func nextUpItemsPage(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        try await nextUpPage(seriesID: nil, startIndex: startIndex, limit: limit)
    }

    func nextUpItems(seriesID: String? = nil, limit: Int) async throws -> [MediaItem] {
        try await nextUpPage(seriesID: seriesID, startIndex: 0, limit: limit).items
    }

    private func nextUpPage(seriesID: String?, startIndex: Int, limit: Int) async throws -> MediaItemPage {
        let parameters = Paths.GetNextUpParameters(
            userID: userID,
            startIndex: startIndex,
            limit: limit,
            fields: Self.playbackMetadataFields,
            seriesID: seriesID,
            enableImages: true,
            enableUserData: true,
            enableTotalRecordCount: true,
            enableResumable: true
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.browse(Paths.getNextUp(parameters: parameters))
        }
        return MediaItemPage(items: JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? []), totalRecordCount: response.value.totalRecordCount)
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
            try await client.browse(Paths.getLatestMedia(parameters: parameters))
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
            sortOrder: query.mostRecentlyPlayedFirst ? [.descending] : sortOrder(for: query.sort),
            parentID: query.parentID,
            fields: query.metadataOnly ? Self.metadataFields : Self.playbackMetadataFields,
            includeItemTypes: includeItemKinds(for: query),
            filters: filters(for: query.statusFilter),
            isFavorite: query.favoritesOnly ? true : nil,
            sortBy: query.mostRecentlyPlayedFirst ? [.datePlayed] : sortBy(for: query.sort),
            enableUserData: true,
            personIDs: query.personID.map { [$0] },
            artistIDs: query.artistID.map { [$0] },
            ids: query.itemIDs,
            isCollapseBoxSetItems: query.hasRelatedFilter ? false : nil,
            studioIDs: query.studioID.map { [$0] },
            genreIDs: query.genreID.map { [$0] },
            enableTotalRecordCount: true,
            enableImages: true
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.browse(Paths.getItems(parameters: parameters))
        }
        return MediaItemPage(
            items: JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? []),
            totalRecordCount: response.value.totalRecordCount
        )
    }

    /// A legacy name-only tag may match several similarly named entities.
    /// Use the typed, account-filtered catalog and accept one distinct exact match.
    func resolveRelatedSearch(_ target: RelatedSearch) async throws -> RelatedSearch? {
        if target.id?.isEmpty == false {
            return target
        }
        let name = RelatedSearch.normalizedName(target.name)
        guard !name.isEmpty, target.kind != .person else { return nil }
        let studio = target.kind == .studio
        let expectedKind: BaseItemKind = studio ? .studio : .genre
        let candidates = try await MediaPageLoader.collect { offset, limit in
            let request = studio
                ? Paths.getStudios(parameters: .init(startIndex: offset, limit: limit, searchTerm: target.name, userID: userID, enableImages: false, enableTotalRecordCount: true))
                : Paths.getGenres(parameters: .init(startIndex: offset, limit: limit, searchTerm: target.name, userID: userID, enableImages: false, enableTotalRecordCount: true))
            let response = try await NetworkRetryPolicy.idempotent.run { try await client.browse(request) }
            // Count the whole server page for pagination, retaining names only for the requested kind.
            let items = (response.value.items ?? []).map { dto in
                MediaItem(id: dto.id, name: dto.type == expectedKind ? dto.name : nil)
            }
            return MediaItemPage(items: items, totalRecordCount: response.value.totalRecordCount)
        }
        let ids = Set(candidates.compactMap { candidate -> String? in
            guard let candidateName = candidate.name, RelatedSearch.normalizedName(candidateName) == name else { return nil }
            return candidate.id
        })
        guard ids.count == 1, let id = ids.first, !id.isEmpty else { return nil }
        return RelatedSearch(kind: target.kind, id: id, name: target.name)
    }

    func item(id: String) async throws -> MediaItem {
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.browse(Paths.getItem(itemID: id, userID: userID))
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
            try await client.browse(Paths.getSimilarItems(itemID: itemID, parameters: parameters))
        }
        return JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? [])
    }

    func specialFeatures(itemID: String) async throws -> [MediaItem] {
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.browse(Paths.getSpecialFeatures(itemID: itemID, userID: userID))
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
            try await client.browse(Paths.getSeasons(seriesID: seriesID, parameters: parameters))
        }
        return JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? [])
    }

    func episodesPage(seriesID: String, seasonID: String, startIndex: Int, limit: Int) async throws -> MediaItemPage {
        let parameters = Paths.GetEpisodesParameters(
            userID: userID,
            fields: Self.metadataFields,
            seasonID: seasonID,
            startIndex: startIndex,
            limit: limit,
            enableImages: true,
            enableUserData: true,
            sortBy: .indexNumber
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.browse(Paths.getEpisodes(seriesID: seriesID, parameters: parameters))
        }
        return MediaItemPage(
            items: JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? []),
            totalRecordCount: response.value.totalRecordCount
        )
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

    func artworkURLs(for item: MediaItem, request: MediaArtworkRequest) -> [URL] {
        imageBuilder.artworkURLs(for: item, request: request)
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
            playMethod: resolution.isTranscoding ? .transcode : resolution.isDirectPlay ? .directPlay : .directStream,
            stereoLayout: resolution.stereoLayout,
            stereoFallbackReason: resolution.stereoFallbackReason,
            mediaSource: resolution.mediaSource.map(JellyfinMediaItemMapper.mediaSource),
            resource: resolution.resource,
            isLive: resolution.mediaSource?.liveStreamID != nil
        )
    }

    func releasePlaybackResource(_ resource: PlaybackResource) async throws {
        try await streamBuilder.release(resource: resource)
    }

    func resolveAudioPlayback(for itemID: String, streamSelection: PlaybackStreamSelection) async throws -> PlaybackSourceResolution {
        let resolution = try await streamBuilder.resolveAudioPlayback(for: itemID, streamSelection: streamSelection)
        return PlaybackSourceResolution(
            url: resolution.url,
            playSessionID: resolution.playSessionID,
            mediaSourceID: resolution.mediaSourceID,
            playMethod: resolution.isTranscoding ? .transcode : .directStream,
            stereoLayout: .none,
            stereoFallbackReason: nil,
            mediaSource: resolution.mediaSource.map(JellyfinMediaItemMapper.mediaSource),
            resource: resolution.resource,
            isLive: resolution.mediaSource?.liveStreamID != nil
        )
    }

    func downloadBook(for item: MediaItem) async throws -> (file: URL, filename: String) {
        guard item.type == .book, let id = item.id else { throw GusError.notFound }
        guard item.canDownload == true else { throw GusError.forbidden }
        let source = DownloadSourceResolver.bookOriginalSource(itemID: id, item: item)
        let response = try await client.download(for: source.request)
        // Without a disposition filename URLSession may manufacture "Download.pdf"
        // from the endpoint path and MIME type. Prefer the media's basename in that case.
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
        let suggested = disposition?.localizedCaseInsensitiveContains("filename") == true ? response.response.suggestedFilename : nil
        let knownName = suggested ?? item.originalBookFilename
        let filename: String
        if let knownName, !URL(fileURLWithPath: knownName).pathExtension.isEmpty {
            filename = URL(fileURLWithPath: knownName).lastPathComponent
        } else {
            let ext = response.response.mimeType == "application/pdf" ? "pdf" : source.fileExtension
            filename = item.displayTitle + "." + ext
        }
        return (response.value, filename)
    }

    func downloadSource(for item: MediaItem, streamSelection: PlaybackStreamSelection) async throws -> DownloadSourceResolution {
        let source = try await DownloadSourceResolver(client: client, userID: userID).resolve(for: item, streamSelection: streamSelection)
        guard let url = client.url(with: source.request, queryAPIKey: true) else {
            throw DownloadSourceResolver.ResolverError.noMediaSource
        }
        return DownloadSourceResolution(
            url: url,
            fileExtension: source.fileExtension,
            requiresTranscoding: source.kind == .transcoded,
            operation: DownloadActivity.SourceOperation(rawValue: source.kind.rawValue),
            mediaSourceID: source.mediaSourceID,
            estimatedByteCount: source.kind == .original ? item.mediaSources.first { $0.id == source.mediaSourceID }?.sizeBytes : nil
        )
    }

    // MARK: - Live TV

    func liveTVAvailability() async throws -> LiveTVAvailability {
        let incomplete = GusError.server(String(
            localized: "Live TV availability could not be checked. Try again.",
            comment: "Incomplete Live TV permission or capability response"
        ))
        do {
            // IsEnabled reports service registration, not configured tuners.
            // Account permission distinguishes an empty EnabledUsers list from
            // a server whose users are all denied Live TV access.
            let availability: LiveTVAvailability = try await PlaybackDeadline.run(for: .seconds(30)) { [client, userID] in
                try Task.checkCancellation()
                let user = try await client.send(Paths.getUserByID(userID: userID)).value
                try Task.checkCancellation()
                guard user.id == userID, let allowed = user.policy?.enableLiveTvAccess else { throw incomplete }
                guard allowed else { return .restricted }
                let info = try await client.send(Paths.getLiveTvInfo).value
                try Task.checkCancellation()
                guard let enabled = info.isEnabled else { throw incomplete }
                guard enabled else { return .notConfigured }
                guard let users = info.enabledUsers else { throw incomplete }
                if users.contains(userID) {
                    return .enabled
                }
                return users.isEmpty ? .notConfigured : .restricted
            }
            try Task.checkCancellation()
            return availability
        } catch {
            try Task.checkCancellation()
            if error is PlaybackDeadline.Timeout {
                throw GusError.timeout
            }
            let failure = GusError(from: error)
            if failure == .forbidden {
                return .restricted
            }
            throw failure
        }
    }

    func liveTVChannels(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        let parameters = Paths.GetLiveTvChannelsParameters(
            userID: userID,
            startIndex: startIndex,
            limit: limit,
            isAddCurrentProgram: true
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.browse(Paths.getLiveTvChannels(parameters: parameters))
        }
        return MediaItemPage(
            items: JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? []),
            totalRecordCount: response.value.totalRecordCount
        )
    }

    func liveTVRecordingsPage(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        let parameters = Paths.GetRecordingsParameters(
            userID: userID,
            startIndex: startIndex,
            limit: limit,
            fields: Self.playbackMetadataFields,
            enableTotalRecordCount: true
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.browse(Paths.getRecordings(parameters: parameters))
        }
        return MediaItemPage(items: JellyfinMediaItemMapper.mediaItems(from: response.value.items ?? []), totalRecordCount: response.value.totalRecordCount)
    }

    func liveTVTimers() async throws -> [LiveTVTimer] {
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getTimers())
        }
        guard let timers = response.value.items, response.value.totalRecordCount.map({ $0 <= timers.count }) ?? true,
              timers.allSatisfy({ $0.id != nil })
        else {
            throw GusError.server(String(localized: "The server returned an incomplete recording schedule."))
        }
        return timers.compactMap { timer in
            guard let id = timer.id else { return nil }
            return LiveTVTimer(
                id: id,
                name: timer.name ?? String(localized: "Recording", comment: "Fallback scheduled recording name"),
                channelName: timer.channelName,
                startDate: timer.startDate,
                programID: timer.programID ?? timer.programInfo?.id,
                activeRecording: timer.status.map { [.new, .inProgress, .conflictedOk].contains($0) }
            )
        }
    }

    func cancelLiveTVTimer(id: String) async throws {
        _ = try await client.send(Paths.cancelTimer(timerID: id))
    }

    func toggleWatched(itemID: String, currentlyWatched: Bool) async throws {
        if currentlyWatched {
            _ = try await client.send(Paths.markUnplayedItem(itemID: itemID, userID: userID))
        } else {
            _ = try await client.send(Paths.markPlayedItem(itemID: itemID, userID: userID))
        }
    }

    func toggleFavorite(itemID: String, currentlyFavorite: Bool) async throws {
        if currentlyFavorite {
            _ = try await client.send(Paths.unmarkFavoriteItem(itemID: itemID, userID: userID))
        } else {
            _ = try await client.send(Paths.markFavoriteItem(itemID: itemID, userID: userID))
        }
    }

    func reportPlaybackStart(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws {
        _ = try await client.send(
            Paths.reportPlaybackStart(
                playbackStateInfo(for: context, positionTicks: positionTicks, isPaused: isPaused)
            )
        )
    }

    func reportPlaybackProgress(context: PlaybackReportContext, positionTicks: Int, isPaused: Bool) async throws {
        _ = try await client.send(
            Paths.reportPlaybackProgress(
                playbackStateInfo(for: context, positionTicks: positionTicks, isPaused: isPaused)
            )
        )
    }

    func reportPlaybackStopped(context: PlaybackReportContext, positionTicks: Int) async throws {
        _ = try await client.send(
            Paths.reportPlaybackStopped(
                PlaybackStopInfo(
                    isFailed: context.isFailed,
                    itemID: context.itemID,
                    liveStreamID: context.liveStreamID,
                    mediaSourceID: context.mediaSourceID,
                    playSessionID: context.playSessionID,
                    positionTicks: positionTicks
                )
            )
        )
    }

    func updatePlaybackPosition(itemID: String, positionTicks: Int) async throws {
        _ = try await client.send(
            Paths.updateItemUserData(
                itemID: itemID,
                userID: userID,
                UpdateUserItemDataDto(playbackPositionTicks: max(0, positionTicks))
            ),
            configure: { @Sendable request in request.timeoutInterval = 10 }
        )
    }

    // MARK: - Native server lists

    func mediaLists(kind: ServerMediaListKind) async throws -> [ServerMediaList] {
        do {
            let headers = try await allListItems(kind: kind, parentID: nil)
            var lists: [ServerMediaList] = []
            for header in headers {
                let id = try nativeListID(header.id)
                let canEdit = await canEditPlaylist(id: id)
                lists.append(ServerMediaList(id: id, name: header.name ?? String(localized: "Untitled", comment: "Fallback item title"), kind: kind, entries: [], canEdit: canEdit, entriesLoaded: false, primaryImageTag: header.imageTags?["Primary"], overview: header.overview))
            }
            return lists
        } catch {
            throw mediaListError(error)
        }
    }

    func mediaList(id: UUID, kind: ServerMediaListKind) async throws -> ServerMediaList {
        do {
            let header = try await listHeader(id: id, kind: kind)
            let canEdit = await canEditPlaylist(id: id)
            let members: [BaseItemDto]
            if kind == .playlist {
                var results: [BaseItemDto] = []
                var startIndex = 0
                while true {
                    try Task.checkCancellation()
                    let parameters = Paths.GetPlaylistItemsParameters(userID: userID, startIndex: startIndex, limit: Self.listPageSize, fields: Self.playbackMetadataFields, enableImages: true, enableUserData: true)
                    let page = try await NetworkRetryPolicy.idempotent.run {
                        try await client.browse(Paths.getPlaylistItems(playlistID: ServerMediaListID.string(id), parameters: parameters))
                    }.value
                    let items = page.items ?? []
                    results.append(contentsOf: items)
                    startIndex += items.count
                    if items.isEmpty || page.totalRecordCount.map({ startIndex >= $0 }) == true {
                        break
                    }
                    // A server may cap each response below our requested size. Continue
                    // until the advertised total or an empty page, rather than truncate.
                }
                members = results
            } else {
                members = []
            }
            return try ServerMediaList(id: id, name: header.name ?? String(localized: "Untitled", comment: "Fallback item title"), kind: kind, entries: JellyfinMediaItemMapper.mediaListEntries(from: members, kind: kind), canEdit: canEdit, entriesLoaded: true, primaryImageTag: header.imageTags?["Primary"], overview: header.overview)
        } catch {
            throw mediaListError(error)
        }
    }

    func createMediaList(name: String, kind: ServerMediaListKind, itemIDs: [String]) async throws -> UUID {
        do {
            if kind == .playlist {
                try validateUniquePlaylistItems(itemIDs)
            }
            let rawID: String?
            switch kind {
            case .playlist:
                // An explicit video type keeps empty Gus playlists usable for movies and
                // episodes. Existing mixed server playlists are read without filtering.
                rawID = try await client.send(Paths.createPlaylist(CreatePlaylistDto(ids: itemIDs, isPublic: false, mediaType: .video, name: name, userID: userID))).value.id
            }
            return try nativeListID(rawID)
        } catch {
            throw mediaListError(error)
        }
    }

    func renameMediaList(id: UUID, kind: ServerMediaListKind, name: String) async throws {
        do {
            switch kind {
            case .playlist:
                _ = try await client.send(Paths.updatePlaylist(playlistID: ServerMediaListID.string(id), UpdatePlaylistDto(name: name)))
            }
        } catch {
            throw mediaListError(error)
        }
    }

    func deleteMediaList(id: UUID, kind: ServerMediaListKind) async throws {
        do {
            // DeleteItem is also a media deletion endpoint. Verify the list type before
            // sending it, so a mismatched identifier cannot delete a movie or episode.
            _ = try await listHeader(id: id, kind: kind)
            _ = try await client.send(Paths.deleteItem(itemID: ServerMediaListID.string(id)))
        } catch {
            throw mediaListError(error)
        }
    }

    func addToMediaList(id: UUID, kind: ServerMediaListKind, itemIDs: [String]) async throws {
        do {
            guard !itemIDs.isEmpty else { return }
            switch kind {
            case .playlist:
                try validateUniquePlaylistItems(itemIDs)
                // The store checks its snapshot before journaling. Re-read here to
                // catch another client's edit before Jellyfin silently ignores an add.
                let current = try await mediaList(id: id, kind: kind)
                let existing = Set(current.entries.compactMap(\.item.id).map(normalizedMediaID))
                guard existing.isDisjoint(with: itemIDs.map(normalizedMediaID)) else { throw repeatedPlaylistItemsError() }
                _ = try await client.send(Paths.addItemToPlaylist(playlistID: ServerMediaListID.string(id), ids: itemIDs, userID: userID))
            }
        } catch {
            throw mediaListError(error)
        }
    }

    func removeFromMediaList(id: UUID, kind: ServerMediaListKind, entryIDs: [UUID]) async throws {
        do {
            guard !entryIDs.isEmpty else { return }
            let ids = entryIDs.map(ServerMediaListID.string)
            switch kind {
            case .playlist:
                _ = try await client.send(Paths.removeItemFromPlaylist(playlistID: ServerMediaListID.string(id), entryIDs: ids))
            }
        } catch {
            throw mediaListError(error)
        }
    }

    func moveMediaListEntry(id: UUID, entryID: UUID, to index: Int) async throws {
        do {
            guard index >= 0 else { throw GusError.server(String(localized: "The playlist position is invalid.", comment: "Invalid native playlist move position")) }
            _ = try await client.send(Paths.moveItem(playlistID: ServerMediaListID.string(id), itemID: ServerMediaListID.string(entryID), newIndex: index))
        } catch {
            throw mediaListError(error)
        }
    }

    private func normalizedMediaID(_ id: String) -> String {
        ServerMediaListID.uuid(id).map(ServerMediaListID.string) ?? id.lowercased()
    }

    private func validateUniquePlaylistItems(_ itemIDs: [String]) throws {
        guard Set(itemIDs.map(normalizedMediaID)).count == itemIDs.count else { throw repeatedPlaylistItemsError() }
    }

    private func repeatedPlaylistItemsError() -> GusError {
        GusError.server(String(localized: "Jellyfin playlists require unique items. Repeated items have not been sent to the server.", comment: "Jellyfin native playlist duplicate limitation"))
    }

    /// A list ACL rejection is not an expired session. Keep this mapping scoped
    /// to native lists so read-only sharing never signs a valid user out.
    private func mediaListError(_ error: any Error) -> any Error {
        if GusError(from: error) == .forbidden {
            return GusError.server(String(localized: "You do not have permission to edit this server list.", comment: "Native server media list permission denied"))
        }
        return error
    }

    private static let listPageSize = 200

    private func allListItems(kind: ServerMediaListKind, parentID: String?) async throws -> [BaseItemDto] {
        var results: [BaseItemDto] = []
        var startIndex = 0
        while true {
            try Task.checkCancellation()
            let parameters = Paths.GetItemsParameters(userID: userID, startIndex: startIndex, limit: Self.listPageSize, isRecursive: parentID == nil, parentID: parentID, fields: Self.playbackMetadataFields, includeItemTypes: parentID == nil ? [.playlist] : nil, sortBy: parentID == nil ? [.sortName] : nil, enableUserData: true, enableTotalRecordCount: true, enableImages: true)
            let page = try await NetworkRetryPolicy.idempotent.run {
                try await client.browse(Paths.getItems(parameters: parameters))
            }.value
            let items = page.items ?? []
            results.append(contentsOf: items)
            startIndex += items.count
            if items.isEmpty || page.totalRecordCount.map({ startIndex >= $0 }) == true {
                break
            }
        }
        return results
    }

    private func listHeader(id: UUID, kind: ServerMediaListKind) async throws -> BaseItemDto {
        let header = try await NetworkRetryPolicy.idempotent.run {
            try await client.browse(Paths.getItem(itemID: ServerMediaListID.string(id), userID: userID))
        }.value
        guard header.type == .playlist,
              try nativeListID(header.id) == id
        else { throw GusError.notFound }
        return header
    }

    func ownsPrivatePlaylist(id: UUID) async throws -> Bool {
        let nativeID = ServerMediaListID.string(id)
        do {
            // Jellyfin's /Users endpoint on a playlist is owner-only. An editor's
            // personal share can grant edits, but never establishes ownership.
            let shares = try await client.send(Paths.getPlaylistUsers(playlistID: nativeID)).value
            guard shares.isEmpty else { return false }
            let list = try await client.send(Paths.getPlaylist(playlistID: nativeID)).value
            return list.isOpenAccess == false && list.shares?.isEmpty == true
        } catch {
            let failure = GusError(from: error)
            if failure == .forbidden || failure == .notFound {
                return false
            }
            throw failure
        }
    }

    private func canEditPlaylist(id: UUID) async -> Bool {
        // Publicly readable playlists can have no current-user share (a null body).
        // Unknown permissions are conservative; mutation endpoints remain authoritative.
        let permission = try? await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getPlaylistUser(playlistID: ServerMediaListID.string(id), userID: userID))
        }.value
        return permission?.canEdit == true
    }

    func canEditMediaListMetadata(_ list: EditableMediaList) async throws -> Bool {
        guard try await collectionCapabilities(id: nil).editMetadata else { return false }
        if case let .playlist(id) = list {
            return await canEditPlaylist(id: id)
        }
        return true
    }

    func canEditMediaListCover(_: EditableMediaList) async throws -> Bool {
        // Jellyfin authorizes Primary image uploads with RequiresElevation.
        // Playlist membership permissions apply only to the playlist editor APIs.
        try await collectionCapabilities(id: nil).editArtwork
    }

    func editMediaListMetadata(_ list: EditableMediaList, name: String?, expectedName: String, overview: String?, expectedOverview: String) async throws {
        guard name != nil || overview != nil else { return }
        guard try await canEditMediaListMetadata(list) else { throw GusError.forbidden }
        var header = try await editableListHeader(list)
        let currentName = header["Name"] as? String ?? ""
        let currentOverview = header["Overview"] as? String ?? ""
        func matches(_ header: [String: Any]) -> Bool {
            (name == nil || header["Name"] as? String == name) &&
                (overview == nil || (header["Overview"] as? String ?? "") == overview)
        }
        if matches(header) {
            return
        }
        guard name == nil || currentName == expectedName || currentName == name,
              overview == nil || currentOverview == expectedOverview || currentOverview == overview
        else { throw GusError.server(String(localized: "The list details changed in Jellyfin. Reopen Edit to review them.")) }
        if let name {
            header["Name"] = name
        }
        if let overview {
            header["Overview"] = overview
        }
        // Jellyfin's generic editor accepts the full DTO. Keep fields the SDK
        // doesn't model and never send a synthesized partial item.
        let body = try JSONSerialization.data(withJSONObject: header)
        try Task.checkCancellation()
        do {
            _ = try await client.send(Paths.updateItem(itemID: list.itemID, BaseItemDto()), configure: { @Sendable request in
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            })
        } catch {
            if let observed = try? await editableListHeader(list), matches(observed) {
                return
            }
            throw error
        }
        guard try matches(await editableListHeader(list)) else {
            throw GusError.server(String(localized: "Jellyfin did not confirm the updated list details."))
        }
    }

    func editMediaListCover(_ list: EditableMediaList, change: MediaListCoverEdit, expectedTag: String?) async throws {
        guard change != .unchanged else { return }
        guard try await canEditMediaListCover(list) else { throw GusError.forbidden }
        let tag = try await primaryImageTag(list)
        if change == .remove, tag == nil {
            return
        }
        if case let .replace(jpeg) = change, let tag, (try? await listCoverMatches(list, tag: tag, jpeg: jpeg)) == true {
            return
        }
        guard tag == expectedTag else {
            throw GusError.server(String(localized: "The cover changed in Jellyfin. Reopen Edit to review it."))
        }
        try Task.checkCancellation()
        do {
            switch change {
            case .unchanged: return
            case let .replace(jpeg): try await uploadPrimaryImage(id: list.itemID, jpeg: jpeg)
            case .remove: _ = try await client.send(Paths.deleteItemImage(itemID: list.itemID, imageType: "Primary"))
            }
        } catch {
            if (try? await confirmedCover(list, change: change)) == true {
                return
            }
            throw error
        }
        guard try await confirmedCover(list, change: change) else {
            throw GusError.server(String(localized: "Jellyfin did not confirm the cover change."))
        }
    }

    private func confirmedCover(_ list: EditableMediaList, change: MediaListCoverEdit) async throws -> Bool {
        let tag = try await primaryImageTag(list)
        switch change {
        case .unchanged: return true
        case .remove: return tag == nil
        case let .replace(jpeg):
            guard let tag else { return false }
            return try await listCoverMatches(list, tag: tag, jpeg: jpeg)
        }
    }

    private func editableListHeader(_ list: EditableMediaList) async throws -> [String: Any] {
        let data = try await NetworkRetryPolicy.idempotent.run {
            try await client.data(for: Paths.getItem(itemID: list.itemID, userID: userID)).value
        }
        let type: String
        switch list {
        case .playlist: type = "Playlist"
        case .collection: type = "BoxSet"
        }
        guard let header = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = header["Id"] as? String, let uuid = ServerMediaListID.uuid(id),
              ServerMediaListID.uuid(list.itemID) == uuid, header["Type"] as? String == type
        else { throw GusError.notFound }
        return header
    }

    private func primaryImageTag(_ list: EditableMediaList) async throws -> String? {
        let header = try await editableListHeader(list)
        return (header["ImageTags"] as? [String: String])?["Primary"]
    }

    private func listCoverMatches(_ list: EditableMediaList, tag: String, jpeg: Data) async throws -> Bool {
        let request = Paths.getItemImage(itemID: list.itemID, imageType: "Primary", parameters: .init(tag: tag))
        return try await client.data(for: request).value == jpeg
    }

    // MARK: Library collections (independent of playlist occurrence APIs)

    func collectionCapabilities(id: String?) async throws -> CollectionCapabilities {
        let user = try await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getUserByID(userID: userID))
        }.value
        let admin = user.policy?.isAdministrator == true
        let management = admin || user.policy?.enableCollectionManagement == true
        var result = CollectionCapabilities(create: management, editMetadata: admin, editArtwork: admin, addMembers: management, removeMembers: management)
        if let id {
            let header = try await collectionHeader(id)
            result.delete = header.canDelete == true
        }
        return result
    }

    func collectionPage(startIndex: Int, limit: Int) async throws -> MediaItemPage {
        try await collectionQuery(parentID: nil, startIndex: startIndex, limit: limit)
    }

    func collectionItem(id: String) async throws -> MediaItem {
        guard let uuid = ServerMediaListID.uuid(id) else { throw GusError.notFound }
        let header = try await item(id: ServerMediaListID.string(uuid))
        guard header.type == .boxSet, header.id.flatMap(ServerMediaListID.uuid) == uuid else { throw GusError.notFound }
        return header
    }

    func collectionMembers(id: String, startIndex: Int, limit: Int) async throws -> MediaItemPage {
        try await collectionQuery(parentID: id, startIndex: startIndex, limit: limit)
    }

    private func collectionQuery(parentID: String?, startIndex: Int, limit: Int) async throws -> MediaItemPage {
        let parameters = Paths.GetItemsParameters(userID: userID, startIndex: startIndex, limit: limit, isRecursive: parentID == nil, parentID: parentID, fields: parentID == nil ? Self.metadataFields : Self.playbackMetadataFields, includeItemTypes: parentID == nil ? [.boxSet] : nil, sortBy: parentID == nil ? [.sortName] : nil, enableUserData: true, enableTotalRecordCount: true, enableImages: true)
        let page = try await NetworkRetryPolicy.idempotent.run { try await client.browse(Paths.getItems(parameters: parameters)) }.value
        guard page.items != nil || page.totalRecordCount == 0 else {
            throw GusError.server(String(localized: "The server returned an incomplete collection. Try again."))
        }
        return MediaItemPage(items: JellyfinMediaItemMapper.mediaItems(from: page.items ?? []), totalRecordCount: page.totalRecordCount)
    }

    private func collectionHeader(_ id: String) async throws -> BaseItemDto {
        guard let uuid = ServerMediaListID.uuid(id) else { throw GusError.notFound }
        let header = try await NetworkRetryPolicy.idempotent.run { try await client.send(Paths.getItem(itemID: ServerMediaListID.string(uuid), userID: userID)) }.value
        guard header.type == .boxSet, header.id.flatMap(ServerMediaListID.uuid) == uuid else { throw GusError.notFound }
        return header
    }

    func createCollection(name: String, itemIDs: [String]) async throws -> String {
        do {
            let result = try await client.send(Paths.createCollection(parameters: .init(name: name, ids: itemIDs))).value
            // The server may already have created the collection. An unusable
            // response requires readback and review before another creation.
            guard let id = result.id, ServerMediaListID.uuid(id) != nil else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing or invalid created collection ID"))
            }
            return id
        } catch { throw collectionMutationError(error) }
    }

    func deleteCollection(id: String) async throws {
        do {
            let header = try await collectionHeader(id)
            guard header.canDelete == true else { throw GusError.server(String(localized: "You do not have permission to delete this collection.")) }
            _ = try await client.send(Paths.deleteItem(itemID: id))
        } catch { throw collectionMutationError(error) }
    }

    func addCollectionMembers(id: String, itemIDs: [String]) async throws {
        do {
            _ = try await collectionHeader(id)
            let unique = Set(itemIDs.compactMap(ServerMediaListID.uuid)).map(ServerMediaListID.string).sorted()
            guard unique.count == Set(itemIDs).count else { throw GusError.notFound }
            guard !unique.isEmpty else { return }
            _ = try await client.send(Paths.addToCollection(collectionID: id, ids: unique))
        } catch { throw collectionMutationError(error) }
    }

    func removeCollectionMembers(id: String, itemIDs: [String]) async throws {
        do {
            _ = try await collectionHeader(id)
            guard !itemIDs.isEmpty else { return }
            _ = try await client.send(Paths.removeFromCollection(collectionID: id, ids: itemIDs))
        } catch { throw collectionMutationError(error) }
    }

    private func uploadPrimaryImage(id: String, jpeg: Data) async throws {
        // Jellyfin decodes the body from base64 despite the image content type.
        let body = jpeg.base64EncodedData()
        _ = try await client.send(Paths.setItemImage(itemID: id, imageType: "Primary"), configure: { @Sendable request in
            request.httpBody = body
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        })
    }

    /// The authenticated transport owns the DeleteItem 401 policy probe; this
    /// adapter only supplies the contextual collection permission message.
    private func collectionMutationError(_ error: any Error) -> any Error {
        if GusError(from: error) == .forbidden {
            return GusError.server(String(localized: "You do not have permission to edit this collection."))
        }
        return error
    }

    private func nativeListID(_ rawID: String?) throws -> UUID {
        guard let rawID, let id = ServerMediaListID.uuid(rawID) else {
            throw GusError.server(String(localized: "The server returned an invalid list identifier.", comment: "Invalid native media list identifier"))
        }
        return id
    }

    // MARK: - Book series metadata

    func canEditBookSeries() async throws -> Bool {
        // 10.x accepts an item update but ignores SeriesName. Verify support on
        // each editor opening/save so a downgrade or role change takes effect.
        do {
            let info = try await client.send(Paths.getPublicSystemInfo).value
            guard let version = info.version?.split(separator: ".", omittingEmptySubsequences: false),
                  version.count >= 2, version.first == "12",
                  version.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
            else {
                bookSeriesEditingEnabled = false
                return false
            }
            bookSeriesEditingEnabled = try await collectionCapabilities(id: nil).editMetadata
            return bookSeriesEditingEnabled
        } catch {
            bookSeriesEditingEnabled = false
            throw error
        }
    }

    func setBookSeries(itemID: String, from expectedName: String?, to newName: String?) async throws {
        guard bookSeriesEditingEnabled else { throw GusError.forbidden }
        guard let uuid = ServerMediaListID.uuid(itemID) else { throw GusError.notFound }
        guard editingBookIDs.insert(uuid).inserted else {
            throw GusError.server(String(localized: "This book already has a series update in progress."))
        }
        defer { editingBookIDs.remove(uuid) }

        let id = ServerMediaListID.string(uuid)
        var header = try await bookSeriesHeader(uuid)
        let current = Self.seriesName(in: header)
        let desired = newName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard desired != "" else {
            throw GusError.server(String(localized: "Enter a series name."))
        }
        if current == desired {
            return
        }
        guard current == expectedName else {
            throw GusError.server(String(localized: "The series for this book changed. Refresh the library and review it again."))
        }

        // The endpoint updates the full item. Preserve fields the SDK does not
        // model, including server-specific person kinds, dates and metadata locks.
        header["SeriesName"] = desired ?? ""
        let body = try JSONSerialization.data(withJSONObject: header)
        let configure: @Sendable (inout URLRequest) -> Void = { request in
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        try Task.checkCancellation()
        do {
            _ = try await client.send(Paths.updateItem(itemID: id, BaseItemDto()), configure: configure)
        } catch {
            let failure = GusError(from: error)
            switch failure {
            case .offline, .network, .timeout, .server:
                // A response can be lost after commit. Reconcile before any retry.
                if let observed = try? await bookSeriesHeader(uuid), Self.seriesName(in: observed) == desired {
                    return
                }
            default: break
            }
            throw error
        }
        guard try await Self.seriesName(in: bookSeriesHeader(uuid)) == desired else {
            throw GusError.server(String(localized: "Jellyfin did not confirm the new series for this book."))
        }
    }

    private func bookSeriesHeader(_ uuid: UUID) async throws -> [String: Any] {
        let id = ServerMediaListID.string(uuid)
        let data = try await NetworkRetryPolicy.idempotent.run {
            try await client.data(for: Paths.getItem(itemID: id, userID: userID)).value
        }
        guard let header = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let itemID = header["Id"] as? String, ServerMediaListID.uuid(itemID) == uuid,
              header["Type"] as? String == "Book", header["Name"] is String,
              header["SeriesName"] == nil || header["SeriesName"] is NSNull || header["SeriesName"] is String,
              header["OfficialRating"] == nil || header["OfficialRating"] is NSNull || header["OfficialRating"] is String,
              ContentRatingGate.admitsStored(MediaItem(officialRating: header["OfficialRating"] as? String, type: .book))
        else { throw GusError.notFound }
        // This route accepts a name but cannot reassign or detach a real
        // series ID. Check both the fresh header and the post-write readback.
        if let value = header["SeriesId"], !(value is NSNull) {
            guard let id = value as? String, BookSeriesKey.explicitID(id) == nil else {
                throw GusError.server(String(localized: "Jellyfin manages this book’s series by ID. Refresh the library to see its membership."))
            }
        }
        return header
    }

    private static func seriesName(in header: [String: Any]) -> String? {
        guard let value = header["SeriesName"] as? String, !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Book reading progress

    func reportBookProgress(itemID: String, fraction: Double) async throws {
        _ = try await client.send(
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
        .providerIDs,
        .primaryImageAspectRatio,
        .overview,
        .genres,
        .people,
        .studios,
        .taglines,
        .tags,
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
            var kinds = includeTypes.compactMap(Self.baseItemKind(for:))
            if query.hasRelatedFilter, kinds.contains(.video) {
                kinds.append(.musicVideo)
            }
            return kinds.isEmpty ? nil : kinds
        }
        // Artist queries return that artist's albums unless the caller asked otherwise.
        return query.artistID != nil ? [.musicAlbum] : nil
    }

    private static func baseItemKind(for type: MediaItemType) -> BaseItemKind? {
        switch type {
        case .genre: return .genre
        case .movie: return .movie
        case .episode: return .episode
        case .series: return .series
        case .season: return .season
        case .boxSet: return .boxSet
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
        case .photoAlbum: return .photoAlbum
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
            canSeek: context.canSeek,
            isMuted: false,
            isPaused: isPaused,
            itemID: context.itemID,
            liveStreamID: context.liveStreamID,
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

extension JellyfinMediaProviderSession: LiveTVGuideProviding {
    func liveTVPrograms(from: Date, until: Date, channelID: String?, offset: Int, limit: Int) async throws -> LiveTVGuidePage {
        let parameters = Paths.GetLiveTvProgramsParameters(
            channelIDs: channelID.map { [$0] }, userID: userID, maxStartDate: until, minEndDate: from,
            startIndex: offset, limit: limit, sortBy: [.startDate], sortOrder: [.ascending],
            enableImages: false, enableUserData: false, enableTotalRecordCount: true
        )
        let response = try await NetworkRetryPolicy.idempotent.run {
            try await client.browse(Paths.getLiveTvPrograms(parameters: parameters))
        }.value
        guard let raw = response.items else { throw GusError.server(String(localized: "The server returned an incomplete program guide.")) }
        return LiveTVGuidePage(programs: raw.compactMap(Self.guideProgram), rawCount: raw.count, total: response.totalRecordCount)
    }

    func liveTVProgram(id: String) async throws -> LiveTVGuideProgram {
        let dto = try await client.browse(Paths.getProgram(programID: id, userID: userID)).value
        guard dto.id == id, let program = Self.guideProgram(dto) else { throw GusError.notFound }
        return program
    }

    private static func guideProgram(_ dto: BaseItemDto) -> LiveTVGuideProgram? {
        guard dto.type == .program || dto.type == .tvProgram || dto.type == .liveTvProgram, let id = dto.id, !id.isEmpty,
              let channel = dto.channelID, !channel.isEmpty, let title = dto.name, !title.isEmpty,
              let start = dto.startDate, let end = dto.endDate, end > start else { return nil }
        return LiveTVGuideProgram(
            id: id,
            channelID: channel,
            channelName: dto.channelName,
            name: title,
            rating: dto.officialRating,
            start: start,
            end: end,
            timerID: dto.timerID
        )
    }

    func canManageRecordings() async throws -> Bool {
        let user = try await client.send(Paths.getUserByID(userID: userID)).value
        return user.id == userID && user.policy?.enableLiveTvAccess == true && user.policy?.enableLiveTvManagement == true
    }

    func scheduleLiveTVProgram(_ program: LiveTVGuideProgram, beforeSend: @MainActor () throws -> Void) async throws {
        guard try await canManageRecordings() else { throw GusError.forbidden }
        let defaults = try await client.send(Paths.getDefaultTimer(programID: program.id)).value
        guard defaults.programID == nil || defaults.programID == program.id,
              defaults.channelID == nil || defaults.channelID == program.channelID,
              defaults.startDate == nil || defaults.startDate == program.start,
              defaults.endDate == nil || defaults.endDate == program.end,
              program.end > .now, program.admitted else { throw GusError.notFound }
        let timer = TimerInfoDto(
            channelID: program.channelID,
            channelName: program.channelName,
            endDate: program.end,
            externalChannelID: defaults.externalChannelID,
            externalProgramID: defaults.externalProgramID,
            isPostPaddingRequired: defaults.isPostPaddingRequired,
            isPrePaddingRequired: defaults.isPrePaddingRequired,
            keepUntil: defaults.keepUntil,
            name: program.name,
            overview: defaults.overview,
            postPaddingSeconds: defaults.postPaddingSeconds,
            prePaddingSeconds: defaults.prePaddingSeconds,
            priority: defaults.priority,
            programID: program.id,
            serviceName: defaults.serviceName,
            startDate: program.start
        )
        try beforeSend()
        _ = try await client.send(Paths.createTimer(timer))
    }
}
