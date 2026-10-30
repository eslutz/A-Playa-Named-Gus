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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("How this video is being played").font(.title3.bold())
                    Text(store.item.displayTitle).font(.headline)
                    if let duration = store.item.runtimeText {
                        detail("Duration", duration)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        detail("Delivery", store.playbackDeliveryTitle)
                        Text(deliveryExplanation).foregroundStyle(.secondary)
                    }.focusable().accessibilityElement(children: .combine)
                    if let video = store.sourceVideoStream {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Source Video").font(.headline)
                            if let codec = video.codec {
                                detail("Codec", codec.uppercased())
                            }
                            if let width = video.width, let height = video.height {
                                detail("Resolution", "\(width) × \(height)")
                            }
                            if let range = video.videoRange {
                                detail("Dynamic Range", range)
                            }
                        }.focusable().accessibilityElement(children: .combine)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tracks").font(.headline)
                        detail("Audio", store.audioOptions.first(where: { $0.id == store.selectedAudioStreamIndex })?.title ?? String(localized: "Player default"))
                        detail("Subtitles", store.subtitleOptions.first(where: { $0.id == store.selectedSubtitleStreamIndex })?.title ?? String(localized: "Off"))
                        Text("Source metadata does not confirm the display or audio output format.").font(.caption).foregroundStyle(.secondary)
                    }.focusable().accessibilityElement(children: .combine)
                }
                .frame(maxWidth: 1400, alignment: .leading)
                .padding(48)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .preferredColorScheme(.dark)
        }

        private func detail(_ title: LocalizedStringKey, _ value: String) -> some View {
            HStack(alignment: .top, spacing: 32) {
                Text(title).foregroundStyle(.secondary).frame(width: 240, alignment: .leading)
                Text(value).frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private var deliveryExplanation: LocalizedStringKey {
            switch store.playbackDeliveryTitle {
            case String(localized: "Direct Play"): "Playing the original file without server conversion."
            case String(localized: "Original file"): "Playing the original file without server conversion."
            case String(localized: "Server stream"): "The server delivers a stream adapted for this device. It may repackage the media or convert unsupported tracks."
            case String(localized: "Downloaded"): "Playing a file saved on this device."
            default: "Preparing the playback session."
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
