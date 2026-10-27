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
            try await client.send(Paths.getResumeItems(parameters: parameters))
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
            try await client.send(Paths.getNextUp(parameters: parameters))
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

    func episodes(seriesID: String, seasonID: String, limit: Int) async throws -> MediaItemPage {
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

    func artworkURLs(for item: MediaItem, maxWidth: Int) -> [URL] {
        imageBuilder.artworkURLs(for: item, maxWidth: maxWidth)
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
            stereoFallbackReason: resolution.stereoFallbackReason,
            mediaSource: resolution.mediaSource.map(JellyfinMediaItemMapper.mediaSource)
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
            requiresTranscoding: source.kind == .transcoded,
            operation: DownloadActivity.SourceOperation(rawValue: source.kind.rawValue)
        )
    }

    // MARK: - Live TV

    func liveTVIsEnabled() async -> Bool {
        guard let info = try? await client.send(Paths.getLiveTvInfo).value, info.isEnabled == true else { return false }
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
                    isFailed: false,
                    itemID: context.itemID,
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
                lists.append(ServerMediaList(id: id, name: header.name ?? String(localized: "Untitled", comment: "Fallback item title"), kind: kind, entries: [], canEdit: canEdit, entriesLoaded: false))
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
                        try await client.send(Paths.getPlaylistItems(playlistID: ServerMediaListID.string(id), parameters: parameters))
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
            return try ServerMediaList(id: id, name: header.name ?? String(localized: "Untitled", comment: "Fallback item title"), kind: kind, entries: JellyfinMediaItemMapper.mediaListEntries(from: members, kind: kind), canEdit: canEdit, entriesLoaded: true)
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
        if String(reflecting: type(of: error)) == "Get.APIError",
           Mirror(reflecting: error).children.compactMap({ $0.value as? Int }).first == 403
        {
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
                try await client.send(Paths.getItems(parameters: parameters))
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
            try await client.send(Paths.getItem(itemID: ServerMediaListID.string(id), userID: userID))
        }.value
        guard header.type == .playlist,
              try nativeListID(header.id) == id
        else { throw GusError.notFound }
        return header
    }

    private func canEditPlaylist(id: UUID) async -> Bool {
        // Publicly readable playlists can have no current-user share (a null body).
        // Unknown permissions are conservative; mutation endpoints remain authoritative.
        let permission = try? await NetworkRetryPolicy.idempotent.run {
            try await client.send(Paths.getPlaylistUser(playlistID: ServerMediaListID.string(id), userID: userID))
        }.value
        return permission?.canEdit == true
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
        try JellyfinMediaItemMapper.mediaItem(from: await collectionHeader(id))
    }

    func collectionMembers(id: String, startIndex: Int, limit: Int) async throws -> MediaItemPage {
        try await collectionQuery(parentID: id, startIndex: startIndex, limit: limit)
    }

    private func collectionQuery(parentID: String?, startIndex: Int, limit: Int) async throws -> MediaItemPage {
        let parameters = Paths.GetItemsParameters(userID: userID, startIndex: startIndex, limit: limit, isRecursive: parentID == nil, parentID: parentID, fields: Self.playbackMetadataFields, includeItemTypes: parentID == nil ? [.boxSet] : nil, sortBy: parentID == nil ? [.sortName] : nil, enableUserData: true, enableTotalRecordCount: true, enableImages: true)
        let page = try await NetworkRetryPolicy.idempotent.run { try await client.send(Paths.getItems(parameters: parameters)) }.value
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
            guard let id = result.id else { throw GusError.notFound }
            return id
        } catch { throw await collectionMutationError(error) }
    }

    func updateCollection(id: String, name: String, overview: String) async throws {
        do {
            var header = try await collectionHeader(id)
            header.name = name; header.overview = overview
            _ = try await client.send(Paths.updateItem(itemID: id, header))
        } catch { throw await collectionMutationError(error) }
    }

    func deleteCollection(id: String) async throws {
        do {
            let header = try await collectionHeader(id)
            guard header.canDelete == true else { throw GusError.server(String(localized: "You do not have permission to delete this collection.")) }
            _ = try await client.send(Paths.deleteItem(itemID: id))
        } catch { throw await collectionMutationError(error) }
    }

    func addCollectionMembers(id: String, itemIDs: [String]) async throws {
        do {
            _ = try await collectionHeader(id)
            let unique = Set(itemIDs.compactMap(ServerMediaListID.uuid)).map(ServerMediaListID.string).sorted()
            guard unique.count == Set(itemIDs).count else { throw GusError.notFound }
            guard !unique.isEmpty else { return }
            _ = try await client.send(Paths.addToCollection(collectionID: id, ids: unique))
        } catch { throw await collectionMutationError(error) }
    }

    func removeCollectionMembers(id: String, itemIDs: [String]) async throws {
        do {
            _ = try await collectionHeader(id)
            guard !itemIDs.isEmpty else { return }
            _ = try await client.send(Paths.removeFromCollection(collectionID: id, ids: itemIDs))
        } catch { throw await collectionMutationError(error) }
    }

    func setCollectionArtwork(id: String, jpeg: Data) async throws {
        do {
            _ = try await collectionHeader(id)
            // Jellyfin decodes the request body from base64, despite its image content type.
            let body = jpeg.base64EncodedData()
            let configure: @Sendable (inout URLRequest) -> Void = { request in
                request.httpBody = body
                request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            }
            _ = try await client.send(Paths.setItemImage(itemID: id, imageType: "Primary"), configure: configure)
        } catch { throw await collectionMutationError(error) }
    }

    /// DeleteItem can return 401 for a policy rejection. Confirm auth separately so
    /// a valid user is not signed out by a revoked collection permission.
    private func collectionMutationError(_ error: any Error) async -> any Error {
        if String(reflecting: type(of: error)) == "Get.APIError",
           let status = Mirror(reflecting: error).children.compactMap({ $0.value as? Int }).first
        {
            if status == 403 {
                return GusError.server(String(localized: "You do not have permission to edit this collection."))
            }
            if status == 401, (try? await client.send(Paths.getUserByID(userID: userID))) != nil {
                return GusError.server(String(localized: "You do not have permission to edit this collection."))
            }
        }
        return error
    }

    private func nativeListID(_ rawID: String?) throws -> UUID {
        guard let rawID, let id = ServerMediaListID.uuid(rawID) else {
            throw GusError.server(String(localized: "The server returned an invalid list identifier.", comment: "Invalid native media list identifier"))
        }
        return id
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
