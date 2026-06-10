import Foundation
@testable import Gus
import JellyfinAPI
import Testing

@Suite("Audio playback")
struct AudioPlaybackTests {
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private static func tracks(_ count: Int) -> [MediaItem] {
        (0 ..< count).map { MediaItem(id: "track-\($0)", name: "Track \($0)", type: .audio) }
    }

    @Test("queue advances forward and stops at the end without repeat")
    func queueAdvancesAndStops() {
        var queue = AudioQueue(tracks: Self.tracks(3))

        #expect(queue.currentTrack?.id == "track-0")
        #expect(queue.advance(automatic: true)?.id == "track-1")
        #expect(queue.advance(automatic: true)?.id == "track-2")
        #expect(queue.advance(automatic: true) == nil)
    }

    @Test("repeat one loops on automatic completion but not on user skip")
    func repeatOneLoopsOnlyAutomatically() {
        var queue = AudioQueue(tracks: Self.tracks(3))
        queue.repeatMode = .one

        #expect(queue.advance(automatic: true)?.id == "track-0")
        #expect(queue.advance(automatic: false)?.id == "track-1")
        #expect(queue.advance(automatic: true)?.id == "track-1")
    }

    @Test("repeat all wraps to the first track")
    func repeatAllWraps() {
        var queue = AudioQueue(tracks: Self.tracks(2), startIndex: 1)
        queue.repeatMode = .all

        #expect(queue.currentTrack?.id == "track-1")
        #expect(queue.advance(automatic: true)?.id == "track-0")
    }

    @Test("go back steps to the previous track and floors at the head")
    func goBackFloorsAtHead() {
        var queue = AudioQueue(tracks: Self.tracks(3), startIndex: 1)

        #expect(queue.goBack()?.id == "track-0")
        #expect(queue.goBack()?.id == "track-0")
    }

    @Test("jump selects a track by id")
    func jumpSelectsTrack() {
        var queue = AudioQueue(tracks: Self.tracks(4))

        #expect(queue.jump(toTrackID: "track-2")?.id == "track-2")
        #expect(queue.advance(automatic: true)?.id == "track-3")
        #expect(queue.jump(toTrackID: "missing") == nil)
    }

    @Test("shuffle keeps the current track first and unshuffle restores order")
    func shuffleKeepsCurrentFirst() {
        var queue = AudioQueue(tracks: Self.tracks(6), startIndex: 2)
        var generator = SeededGenerator(state: 42)
        queue.shuffle(using: &generator)

        #expect(queue.isShuffled)
        #expect(queue.currentTrack?.id == "track-2")
        #expect(Set(queue.order) == Set(0 ..< 6))

        queue.unshuffle()
        #expect(!queue.isShuffled)
        #expect(queue.currentTrack?.id == "track-2")
        #expect(queue.order == Array(0 ..< 6))
    }

    @Test("Jellyfin mapper preserves music types and artist fields")
    func mapperPreservesMusicFields() {
        let album = BaseItemDto(
            albumArtist: "HoliznaCC0",
            artists: ["HoliznaCC0"],
            id: "album-1",
            name: "Public Domain Lofi",
            type: .musicAlbum
        )
        let song = BaseItemDto(
            album: "Public Domain Lofi",
            albumArtist: "HoliznaCC0",
            artists: ["HoliznaCC0", "Guest"],
            id: "song-1",
            name: "Tranquil Mindscape",
            type: .audio
        )
        let artist = BaseItemDto(id: "artist-1", name: "HoliznaCC0", type: .musicArtist)
        let book = BaseItemDto(id: "book-1", name: "Dracula", type: .book)
        let audiobook = BaseItemDto(id: "ab-1", name: "Dracula (Audio)", type: .audioBook)

        #expect(JellyfinMediaItemMapper.mediaItem(from: album).type == .musicAlbum)
        #expect(JellyfinMediaItemMapper.mediaItem(from: artist).type == .musicArtist)
        #expect(JellyfinMediaItemMapper.mediaItem(from: book).type == .book)
        #expect(JellyfinMediaItemMapper.mediaItem(from: audiobook).type == .audioBook)

        let mappedSong = JellyfinMediaItemMapper.mediaItem(from: song)
        #expect(mappedSong.type == .audio)
        #expect(mappedSong.album == "Public Domain Lofi")
        #expect(mappedSong.albumArtist == "HoliznaCC0")
        #expect(mappedSong.artists == ["HoliznaCC0", "Guest"])
        #expect(mappedSong.isAudioPlayable)
        #expect(!JellyfinMediaItemMapper.mediaItem(from: book).isAudioPlayable)
    }

    @Test("audio-only originals with playable containers qualify for original download")
    func audioOriginalsAreDownloadable() {
        let mp3Source = MediaSource(
            container: "mp3",
            id: "source-1",
            mediaStreams: [MediaStreamInfo(codec: "mp3", index: 0, type: .audio)]
        )
        let oggSource = MediaSource(
            container: "ogg",
            id: "source-2",
            mediaStreams: [MediaStreamInfo(codec: "vorbis", index: 0, type: .audio)]
        )

        #expect(OfflineDownloadEligibility.isAVPlayerPlayable(mp3Source))
        #expect(!OfflineDownloadEligibility.isAVPlayerPlayable(oggSource))
    }

    @Test("non-native audio falls back to the universal audio transcode source")
    func audioTranscodeFallback() throws {
        let item = MediaItem(
            canDownload: true,
            id: "song-9",
            mediaSources: [
                MediaSource(
                    container: "ogg",
                    id: "source-9",
                    mediaStreams: [MediaStreamInfo(codec: "vorbis", index: 0, type: .audio)]
                ),
            ],
            type: .audio
        )

        let source = try DownloadSourceResolver.localSource(for: item)
        #expect(source.kind == .transcoded)
        #expect(source.fileExtension == "mp3")
        #expect(source.request.url?.path.contains("/Audio/song-9/universal") == true)
    }

    @Test("books download the original file, never a transcode")
    func booksDownloadOriginalFile() throws {
        let epub = MediaItem(
            canDownload: true,
            id: "book-1",
            mediaSources: [MediaSource(container: "epub", id: "source-1")],
            name: "Dracula",
            type: .book
        )
        let unknownContainer = MediaItem(canDownload: true, id: "book-2", type: .book)

        let source = try DownloadSourceResolver.localSource(for: epub)
        #expect(source.kind == .original)
        #expect(source.fileExtension == "epub")
        #expect(source.request.url?.path.contains("/Items/book-1/Download") == true)

        let fallback = try DownloadSourceResolver.localSource(for: unknownContainer)
        #expect(fallback.kind == .original)
        #expect(fallback.fileExtension == "epub")
    }

    @Test("universal audio URL is authenticated and targets the universal endpoint")
    func universalAudioURLBuilds() throws {
        let client = try JellyfinClientFactory.makeClient(
            url: #require(URL(string: "https://demo.example.com")),
            accessToken: "token-123"
        )
        let builder = StreamURLBuilder(client: client, userID: "user-1")

        let url = try builder.universalAudioURL(for: "song-1")
        #expect(url.path.contains("/Audio/song-1/universal"))
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems?.contains { $0.name == "api_key" && $0.value == "token-123" } == true)
    }
}
