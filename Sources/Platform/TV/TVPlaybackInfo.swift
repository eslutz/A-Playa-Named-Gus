import SwiftUI

extension PlaybackStore {
    func gusSetTVPresentationActive(_ active: Bool) {
        #if os(tvOS)
            setPresentationActive(active)
        #endif
    }
}

extension View {
    @ViewBuilder func gusTVVideoLifecycle(store: PlaybackStore?) -> some View {
        #if os(tvOS)
            modifier(TVVideoLifecycle(store: store))
        #else
            self
        #endif
    }
}

#if os(tvOS)
    /// Native AVKit info tab. Describes negotiated delivery separately from source metadata.
    struct TVPlaybackInfo: View {
        let store: PlaybackStore

        var body: some View {
            Form {
                Section("Playback") {
                    LabeledContent("Delivery", value: store.playbackDeliveryTitle)
                    Text(store.item.displayTitle).font(.headline)
                }
                if let video = store.sourceVideoStream {
                    Section("Source Video") {
                        if let codec = video.codec {
                            LabeledContent("Codec", value: codec.uppercased())
                        }
                        if let width = video.width, let height = video.height {
                            LabeledContent("Resolution", value: "\(width) × \(height)")
                        }
                        if let range = video.videoRange {
                            LabeledContent("Dynamic Range", value: range)
                        }
                        Text("Source metadata does not confirm the display or audio output format.").foregroundStyle(.secondary)
                    }
                }
                Section("Tracks") {
                    if let selected = store.audioOptions.first(where: { $0.id == store.selectedAudioStreamIndex }) {
                        LabeledContent("Audio", value: selected.title)
                    }
                    LabeledContent("Subtitles", value: store.subtitleOptions.first(where: { $0.id == store.selectedSubtitleStreamIndex })?.title ?? String(localized: "Off"))
                }
            }
        }
    }

    private struct TVVideoLifecycle: ViewModifier {
        @Environment(\.scenePhase) private var phase
        let store: PlaybackStore?
        func body(content: Content) -> some View {
            content.onChange(of: phase) { _, value in store?.setPresentationActive(value == .active) }
        }
    }
#endif
