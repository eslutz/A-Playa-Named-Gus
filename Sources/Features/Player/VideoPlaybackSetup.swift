#if os(iOS)
    import SwiftUI

    struct VideoPlaybackChoices {
        var audio: MediaStreamInfo?
        var subtitle: MediaStreamInfo?
        var subtitleIntent: PlaybackRequest.SubtitleIntent = .automatic

        func applying(to request: PlaybackRequest) -> PlaybackRequest {
            var request = request
            request.audioTrack = audio
            request.streamSelection.audioStreamIndex = audio?.index
            request.subtitleTrack = subtitle
            request.subtitleIntent = subtitleIntent
            request.streamSelection.subtitleStreamIndex = subtitleIntent == .off ? -1 : subtitle?.index
            return request
        }
    }

    /// Jellyfin can expose tracks in item metadata that require server-side selection.
    /// Keep these choices before playback and let AVKit handle tracks exposed by the stream.
    struct VideoPlaybackSetupButton: View {
        let item: MediaItem
        var sourceID: String? = nil
        var showsDefaultPlay = false
        let play: (VideoPlaybackChoices) -> Void

        @State private var audio: MediaStreamInfo?
        @State private var subtitle: SubtitleChoice = .automatic

        private enum SubtitleChoice: Hashable {
            case automatic, off, track(MediaStreamInfo)
        }

        private var source: MediaSource? {
            guard let sourceID else { return item.mediaSources.first }
            return item.mediaSources.first { $0.id == sourceID }
        }

        var body: some View {
            if [.movie, .episode, .video, .recording, .liveChannel, .trailer].contains(item.type), let source {
                let audioTracks = tracks(.audio, source)
                let subtitles = tracks(.subtitle, source)
                if audioTracks.count > 1 || !subtitles.isEmpty {
                    Menu("Playback Options", systemImage: "slider.horizontal.3") {
                        if audioTracks.count > 1 {
                            Picker("Audio", selection: $audio) {
                                Text("Automatic").tag(nil as MediaStreamInfo?)
                                ForEach(audioTracks, id: \.index) { track in
                                    Text(trackName(track)).tag(Optional(track))
                                }
                            }
                            .menuActionDismissBehavior(.disabled)
                        }
                        if !subtitles.isEmpty {
                            Picker("Subtitles", selection: $subtitle) {
                                Text("Automatic").tag(SubtitleChoice.automatic)
                                Text("Off").tag(SubtitleChoice.off)
                                ForEach(subtitles, id: \.index) { track in
                                    Text(trackName(track)).tag(SubtitleChoice.track(track))
                                }
                            }
                            .menuActionDismissBehavior(.disabled)
                        }
                        Button("Play", systemImage: "play.fill") { play(choices) }
                            .accessibilityIdentifier("VideoPlayback.setup.play")
                    }
                    .accessibilityIdentifier("VideoPlayback.setup")
                    .onChange(of: source) { _, _ in
                        audio = nil
                        subtitle = .automatic
                    }
                } else if showsDefaultPlay {
                    defaultPlay
                }
            } else if showsDefaultPlay {
                defaultPlay
            }
        }

        private var defaultPlay: some View {
            Button("Play", systemImage: "play.fill") { play(.init()) }
                .accessibilityIdentifier("VideoPlayback.setup.play")
        }

        private var choices: VideoPlaybackChoices {
            switch subtitle {
            case .automatic: VideoPlaybackChoices(audio: audio)
            case .off: VideoPlaybackChoices(audio: audio, subtitleIntent: .off)
            case let .track(track): VideoPlaybackChoices(audio: audio, subtitle: track, subtitleIntent: .explicit)
            }
        }

        private func tracks(_ kind: MediaStreamKind, _ source: MediaSource) -> [MediaStreamInfo] {
            var seen = Set<Int>()
            return source.mediaStreams.filter { track in
                guard track.type == kind, let index = track.index, index >= 0 else { return false }
                return seen.insert(index).inserted
            }
        }

        private func trackName(_ track: MediaStreamInfo) -> String {
            track.displayTitle ?? track.title ?? track.language ?? String(localized: "Track \((track.index ?? 0) + 1)")
        }
    }
#endif
