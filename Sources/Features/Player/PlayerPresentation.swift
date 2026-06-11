import SwiftUI

extension View {
    /// Presents the appropriate media surface full-screen where supported. Audio items
    /// (songs, audiobooks) open the audio player; photos open the viewer; books open the
    /// reader (or a share pointer where Readium isn't linked); everything else opens the
    /// video player. On macOS (no `fullScreenCover`) video opens in the dedicated
    /// cinematic player window, while audio/photos/books keep an in-window sheet so
    /// their state stays with the browsing window. The presented content inherits the
    /// environment, so `SessionStore` is available inside.
    @ViewBuilder
    func playerPresentation(item: Binding<ItemRef?>) -> some View {
        #if os(macOS)
            modifier(MacPlayerPresentation(item: item))
        #else
            fullScreenCover(item: item) { ref in
                PresentedPlayer(item: ref.item)
            }
        #endif
    }
}

#if os(macOS)
    enum GusPlayerWindow {
        static let sceneID = "gus-player"
    }

    extension MediaItem {
        /// Video gets the dedicated window; everything else stays a sheet.
        var opensInPlayerWindow: Bool {
            type != .photo && type != .book && !isAudioPlayable
        }
    }

    private struct MacPlayerPresentation: ViewModifier {
        @Environment(\.openWindow) private var openWindow
        @Binding var item: ItemRef?

        /// Non-video refs flow through to the sheet; video refs are intercepted below.
        private var sheetItem: Binding<ItemRef?> {
            Binding(
                get: { item.flatMap { $0.item.opensInPlayerWindow ? nil : $0 } },
                set: { item = $0 }
            )
        }

        func body(content: Content) -> some View {
            content
                .sheet(item: sheetItem) { ref in
                    PresentedPlayer(item: ref.item)
                        .frame(minWidth: 640, minHeight: 360)
                }
                .onChange(of: item) { _, ref in
                    guard let ref, ref.item.opensInPlayerWindow else { return }
                    openWindow(id: GusPlayerWindow.sceneID, value: ref)
                    item = nil
                }
        }
    }

    /// Root of the dedicated macOS player window. The window scene lives outside the
    /// signed-in tree, so the active session is re-derived from `AppModel` here.
    struct GusPlayerWindowContent: View {
        @Environment(AppModel.self) private var appModel
        let ref: ItemRef

        var body: some View {
            if let session = appModel.currentSession {
                PresentedPlayer(item: ref.item)
                    .environment(session)
                    .frame(minWidth: 640, minHeight: 360)
            } else {
                ContentUnavailableView(
                    "Not Signed In",
                    systemImage: "play.slash",
                    description: Text("Sign in to play media.")
                )
                .frame(minWidth: 640, minHeight: 360)
            }
        }
    }
#endif

struct PresentedPlayer: View {
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
