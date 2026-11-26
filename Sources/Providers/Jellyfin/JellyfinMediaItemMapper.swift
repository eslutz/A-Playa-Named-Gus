import Foundation
import JellyfinAPI

enum JellyfinMediaItemMapper {
    static func mediaItem(from item: BaseItemDto) -> MediaItem {
        var mapped = MediaItem(
            providerKind: .jellyfin,
            album: item.album,
            albumArtist: item.albumArtist,
            albumID: item.albumID,
            albumPrimaryImageTag: item.albumPrimaryImageTag,
            artists: item.artists ?? [],
            backdropImageTags: item.backdropImageTags ?? [],
            canDownload: item.canDownload,
            chapters: (item.chapters ?? []).map(mediaChapter),
            collectionType: mediaCollectionType(from: item.collectionType),
            communityRating: item.communityRating.map { Double($0) },
            container: item.container,
            criticRating: item.criticRating.map { Double($0) },
            currentProgramName: item.currentProgram?.name,
            genres: bookGenres(from: item),
            genreItems: (item.genreItems ?? []).map(mediaNamedItem),
            id: item.id,
            imageTags: item.imageTags ?? [:],
            indexNumber: item.indexNumber,
            mediaSources: mediaSources(from: item),
            name: item.name,
            officialRating: item.officialRating,
            overview: item.overview,
            parentBackdropImageTags: item.parentBackdropImageTags ?? [],
            parentBackdropItemID: item.parentBackdropItemID,
            parentID: item.parentID,
            parentIndexNumber: item.parentIndexNumber,
            people: (item.people ?? []).map(mediaPerson),
            primaryImageAspectRatio: item.primaryImageAspectRatio.map { Double($0) },
            premiereDate: item.premiereDate,
            productionYear: item.productionYear,
            runTimeTicks: item.runTimeTicks,
            seriesID: item.seriesID,
            seriesName: item.seriesName,
            seriesPrimaryImageTag: item.seriesPrimaryImageTag,
            studios: (item.studios ?? []).map(mediaNamedItem),
            taglines: item.taglines ?? [],
            tags: item.tags ?? [],
            type: mediaItemType(from: item.type),
            userData: item.userData.map(mediaUserData),
            video3DFormat: media3DFormat(from: item.video3DFormat)
        )
        if item.type == .book, let path = item.path ?? item.mediaSources?.first?.path {
            mapped.originalBookFilename = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init)
        }
        mapped.externalIDs = item.providerIDs ?? [:]
        mapped.artistCredits = (item.artistItems ?? item.albumArtists)?.map { MediaNamedItem(id: $0.id, name: $0.name) }
        return mapped
    }

    static func mediaItems(from items: [BaseItemDto]) -> [MediaItem] {
        items.map(mediaItem)
    }

    /// Preserve the server's entry identity. Jellyfin 10.11 uses the member GUID;
    /// older servers may supply a separate occurrence GUID. Collisions cannot be
    /// safely edited or resumed, so never substitute a random UUID to hide them.
    static func mediaListEntries(from items: [BaseItemDto], kind: ServerMediaListKind) throws -> [ServerMediaListEntry] {
        var seen: Set<UUID> = []
        return try items.map { item in
            let rawID = item.playlistItemID
            guard let rawID, let id = ServerMediaListID.uuid(rawID) else {
                throw GusError.server(String(localized: "The server returned an invalid list entry identifier.", comment: "Invalid native media list entry"))
            }
            guard seen.insert(id).inserted else {
                throw GusError.server(String(localized: "The server returned repeated list entry identifiers. Gus cannot safely edit or resume this list.", comment: "Ambiguous native media list membership"))
            }
            return ServerMediaListEntry(id: id, item: mediaItem(from: item))
        }
    }

    private static func mediaItemType(from type: BaseItemKind?) -> MediaItemType? {
        guard let type else { return nil }
        switch type {
        case .genre:
            return .genre
        case .movie:
            return .movie
        case .episode:
            return .episode
        case .series:
            return .series
        case .season:
            return .season
        case .boxSet:
            return .boxSet
        case .collectionFolder:
            return .collectionFolder
        case .folder:
            return .folder
        case .trailer:
            return .trailer
        case .video, .musicVideo:
            return .video
        case .audio:
            return .audio
        case .musicArtist:
            return .musicArtist
        case .musicAlbum:
            return .musicAlbum
        case .playlist:
            return .playlist
        case .book:
            return .book
        case .audioBook:
            return .audioBook
        case .photo:
            return .photo
        case .photoAlbum:
            return .photoAlbum
        case .tvChannel, .liveTvChannel:
            return .liveChannel
        case .program, .tvProgram, .liveTvProgram:
            return .liveProgram
        case .recording:
            return .recording
        default:
            return .unknown
        }
    }

    private static func mediaCollectionType(from type: CollectionType?) -> MediaCollectionType? {
        guard let type else { return nil }
        switch type {
        case .movies:
            return .movies
        case .tvshows:
            return .tvshows
        case .music:
            return .music
        case .books:
            return .books
        case .photos:
            return .photos
        case .boxsets:
            return .boxsets
        case .livetv:
            return .livetv
        case .homevideos:
            return .homevideos
        default:
            return .unknown
        }
    }

    private static func bookGenres(from item: BaseItemDto) -> [String] {
        let genres = item.genres ?? []
        let structured = item.genreItems?.compactMap(\.name).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
        guard item.type == .book || item.type == .audioBook else { return genres.isEmpty ? structured : genres }
        if structured.count > 1 {
            return structured
        }
        if genres.count > 1 {
            return genres
        }
        return BookDetailMetadata.genres(structured.isEmpty ? genres : structured)
    }

    private static func mediaPerson(from person: BaseItemPerson) -> MediaPerson {
        MediaPerson(
            id: person.id,
            name: person.name,
            primaryImageTag: person.primaryImageTag,
            role: person.role,
            creditType: person.type == .unknown ? nil : person.type?.rawValue
        )
    }

    private static func mediaNamedItem(from pair: NameIDPair) -> MediaNamedItem {
        MediaNamedItem(id: pair.id, name: pair.name)
    }

    private static func mediaUserData(from userData: UserItemDataDto) -> MediaUserData {
        MediaUserData(
            playbackPositionTicks: userData.playbackPositionTicks,
            playedPercentage: userData.playedPercentage,
            isWatched: userData.isPlayed,
            isFavorite: userData.isFavorite,
            lastPlayedAt: userData.lastPlayedDate
        )
    }

    static func mediaSource(from source: JellyfinAPI.MediaSourceInfo) -> MediaSource {
        MediaSource(
            container: source.container,
            id: source.id,
            mediaStreams: (source.mediaStreams ?? []).map(mediaStream),
            supportsDirectPlay: source.isSupportsDirectPlay,
            transcodingURL: source.transcodingURL,
            video3DFormat: media3DFormat(from: source.video3DFormat),
            videoType: mediaVideoType(from: source.videoType),
            name: source.name,
            liveStreamID: source.liveStreamID,
            defaultAudioStreamIndex: source.defaultAudioStreamIndex,
            defaultSubtitleStreamIndex: source.defaultSubtitleStreamIndex,
            runTimeTicks: source.runTimeTicks,
            sizeBytes: source.size.map(Int64.init)
        )
    }

    private static func mediaSources(from item: BaseItemDto) -> [MediaSource] {
        let sources = (item.mediaSources ?? []).map(mediaSource)
        guard sources.isEmpty, let streams = item.mediaStreams, !streams.isEmpty else {
            return sources
        }

        return [
            MediaSource(
                container: item.container,
                mediaStreams: streams.map(mediaStream),
                video3DFormat: media3DFormat(from: item.video3DFormat)
            ),
        ]
    }

    private static func mediaStream(from stream: JellyfinAPI.MediaStream) -> MediaStreamInfo {
        MediaStreamInfo(
            codec: stream.codec,
            codecTag: stream.codecTag,
            displayTitle: stream.displayTitle,
            index: stream.index,
            isDefault: stream.isDefault,
            language: stream.language,
            profile: stream.profile,
            title: stream.title,
            type: mediaStreamKind(from: stream.type),
            bitDepth: stream.bitDepth,
            channels: stream.channels,
            width: stream.width,
            height: stream.height,
            videoRange: stream.videoRange?.rawValue,
            isForced: stream.isForced,
            isHearingImpaired: stream.isHearingImpaired,
            isExternal: stream.isExternal
        )
    }

    private static func mediaStreamKind(from type: MediaStreamType?) -> MediaStreamKind? {
        guard let type else { return nil }
        switch type {
        case .audio:
            return .audio
        case .subtitle:
            return .subtitle
        case .video:
            return .video
        default:
            return .unknown
        }
    }

    private static func mediaVideoType(from type: VideoType?) -> MediaVideoType? {
        guard let type else { return nil }
        switch type {
        case .videoFile:
            return .videoFile
        default:
            return .unknown
        }
    }

    private static func media3DFormat(from format: Video3DFormat?) -> Media3DFormat? {
        guard let format else { return nil }
        switch format {
        case .halfSideBySide:
            return .halfSideBySide
        case .fullSideBySide:
            return .fullSideBySide
        case .halfTopAndBottom:
            return .halfTopAndBottom
        case .fullTopAndBottom:
            return .fullTopAndBottom
        case .mvc:
            return .mvc
        }
    }

    private static func mediaChapter(from chapter: ChapterInfo) -> MediaChapterInfo {
        MediaChapterInfo(
            name: chapter.name,
            startPositionTicks: chapter.startPositionTicks,
            imageTag: chapter.imageTag
        )
    }
}
