import Foundation
import JellyfinAPI

enum JellyfinMediaItemMapper {
    static func mediaItem(from item: BaseItemDto) -> MediaItem {
        MediaItem(
            providerKind: .jellyfin,
            album: item.album,
            albumArtist: item.albumArtist,
            artists: item.artists ?? [],
            backdropImageTags: item.backdropImageTags ?? [],
            canDownload: item.canDownload,
            chapters: (item.chapters ?? []).map(mediaChapter),
            collectionType: mediaCollectionType(from: item.collectionType),
            communityRating: item.communityRating.map { Double($0) },
            container: item.container,
            criticRating: item.criticRating.map { Double($0) },
            currentProgramName: item.currentProgram?.name,
            genres: item.genres ?? [],
            id: item.id,
            imageTags: item.imageTags ?? [:],
            indexNumber: item.indexNumber,
            mediaSources: mediaSources(from: item),
            name: item.name,
            officialRating: item.officialRating,
            overview: item.overview,
            parentBackdropImageTags: item.parentBackdropImageTags ?? [],
            parentID: item.parentID,
            parentIndexNumber: item.parentIndexNumber,
            people: (item.people ?? []).map(mediaPerson),
            primaryImageAspectRatio: item.primaryImageAspectRatio.map { Double($0) },
            productionYear: item.productionYear,
            runTimeTicks: item.runTimeTicks,
            seriesID: item.seriesID,
            seriesName: item.seriesName,
            seriesPrimaryImageTag: item.seriesPrimaryImageTag,
            studios: (item.studios ?? []).map(mediaStudio),
            taglines: item.taglines ?? [],
            type: mediaItemType(from: item.type),
            userData: item.userData.map(mediaUserData),
            video3DFormat: media3DFormat(from: item.video3DFormat)
        )
    }

    static func mediaItems(from items: [BaseItemDto]) -> [MediaItem] {
        items.map(mediaItem)
    }

    private static func mediaItemType(from type: BaseItemKind?) -> MediaItemType? {
        guard let type else { return nil }
        switch type {
        case .movie:
            return .movie
        case .episode:
            return .episode
        case .series:
            return .series
        case .season:
            return .season
        case .collectionFolder:
            return .collectionFolder
        case .folder:
            return .folder
        case .trailer:
            return .trailer
        case .video:
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
        case .tvChannel, .liveTvChannel:
            return .liveChannel
        case .tvProgram, .liveTvProgram:
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
        case .livetv:
            return .livetv
        default:
            return .unknown
        }
    }

    private static func mediaPerson(from person: BaseItemPerson) -> MediaPerson {
        MediaPerson(
            id: person.id,
            name: person.name,
            primaryImageTag: person.primaryImageTag,
            role: person.role
        )
    }

    private static func mediaStudio(from studio: NameIDPair) -> MediaStudio {
        MediaStudio(id: studio.id, name: studio.name)
    }

    private static func mediaUserData(from userData: UserItemDataDto) -> MediaUserData {
        MediaUserData(
            playbackPositionTicks: userData.playbackPositionTicks,
            playedPercentage: userData.playedPercentage,
            isWatched: userData.isPlayed,
            isFavorite: userData.isFavorite
        )
    }

    private static func mediaSource(from source: JellyfinAPI.MediaSourceInfo) -> MediaSource {
        MediaSource(
            container: source.container,
            id: source.id,
            mediaStreams: (source.mediaStreams ?? []).map(mediaStream),
            supportsDirectPlay: source.isSupportsDirectPlay,
            transcodingURL: source.transcodingURL,
            video3DFormat: media3DFormat(from: source.video3DFormat),
            videoType: mediaVideoType(from: source.videoType)
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
            type: mediaStreamKind(from: stream.type)
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
            startPositionTicks: chapter.startPositionTicks
        )
    }
}
