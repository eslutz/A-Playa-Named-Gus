import AVFoundation
import JellyfinAPI
import Observation
import OSLog

/// Owns the `AVPlayer` for a playback session and tears it down on dismiss.
///
/// Pure AVKit: resolves a URL via `StreamURLBuilder` (server transcode), drives an
/// `AVPlayer`, configures the audio session for background audio (iOS/tvOS/visionOS),
/// and feeds the system Now Playing transport via `NowPlayingController`.
@MainActor
@Observable
final class PlaybackStore {

    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var player: AVPlayer?

    let item: BaseItemDto
    private let session: SessionStore
    private let nowPlaying = NowPlayingController()
    private let logger = Logger(subsystem: "dev.ericslutz.gus", category: "Playback")

    init(item: BaseItemDto, session: SessionStore) {
        self.item = item
        self.session = session
    }

    func prepare() async {
        guard player == nil else { return }
        state = .loading
        configureAudioSession()

        guard let itemID = item.id else {
            state = .failed("This item can't be played.")
            return
        }

        do {
            let resolution = try await session.streamBuilder.resolvePlayback(for: itemID)
            logger.info("Playing \(self.item.name ?? "item", privacy: .public) (transcoding: \(resolution.isTranscoding, privacy: .public))")

            let player = AVPlayer(url: resolution.url)
            #if !os(visionOS)
            player.allowsExternalPlayback = true // AirPlay; not available on visionOS
            #endif
            player.automaticallyWaitsToMinimizeStalling = true
            self.player = player

            nowPlaying.start(player: player, item: item)
            state = .ready
            player.play()
        } catch {
            logger.error("Playback prepare failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    func teardown() {
        player?.pause()
        nowPlaying.stop()
        player = nil
        state = .idle
        deactivateAudioSession()
    }

    // MARK: - Audio session (no-op on macOS, which has no AVAudioSession)

    private func configureAudioSession() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
