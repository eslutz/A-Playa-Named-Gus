import SwiftUI

extension View {
    /// Presents the appropriate media surface full-screen where supported, falling back
    /// to a sheet on macOS (which has no `fullScreenCover`). Audio items (songs,
    /// audiobooks) open the audio player; photos open the viewer; books open the reader
    /// (or a share pointer where Readium isn't linked); everything else opens the video
    /// player. The presented content inherits the environment, so `SessionStore` is
    /// available inside.
    @ViewBuilder
    func playerPresentation(item: Binding<ItemRef?>) -> some View {
        #if os(macOS)
            sheet(item: item) { ref in
                PresentedPlayer(item: ref.item)
                    .frame(minWidth: 640, minHeight: 360)
            }
        #else
            fullScreenCover(item: item) { ref in
                PresentedPlayer(item: ref.item)
            }
        #endif
    }
}

private struct PresentedPlayer: View {
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem

    var body: some View {
        // Second-layer family-safety gate: list filtering hides restricted items, but
        // playback can be reached via downloads, deep links, or stale navigation.
        if !ContentRatingGate.admitsStored(item) {
            NavigationStack {
                RestrictedContentView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
            }
        } else {
            mediaSurface
        }
    }

    @ViewBuilder
    private var mediaSurface: some View {
        switch item.type {
        case .photo:
            NavigationStack {
                PhotoViewerView(photo: item)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
            }
        case .book:
            bookSurface
        default:
            if item.isAudioPlayable {
                AudioPlayerScreen(item: item)
            } else {
                VideoPlayerView(item: item)
            }
        }
    }

    /// Books never route into AVKit. Where Readium is linked the reader opens directly;
    /// elsewhere point at the detail page's share flow instead of failing playback.
    @ViewBuilder
    private var bookSurface: some View {
        #if canImport(ReadiumNavigator)
            BookReaderPresenter(item: item)
        #else
            NavigationStack {
                ContentUnavailableView {
                    Label("Reading Isn't Available Here", systemImage: "book")
                } description: {
                    Text("Open this book's detail page and use Share to read it in Apple Books.")
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        #endif
    }
}
