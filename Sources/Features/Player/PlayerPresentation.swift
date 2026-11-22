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
            modifier(SessionPlayerRequest(item: item))
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
        @Environment(AudioPlaybackCoordinator.self) private var audio
        @Environment(AppNavigationModel.self) private var navigation
        @Environment(SessionStore.self) private var session
        @Environment(OfflineDownloadStore.self) private var downloads
        @Environment(\.openWindow) private var openWindow
        @Binding var item: ItemRef?

        /// Non-video refs flow through to the sheet; video refs are intercepted below.
        private var sheetItem: Binding<ItemRef?> {
            Binding(
                get: { item.flatMap { $0.item.opensInPlayerWindow || $0.item.isAudioPlayable ? nil : $0 } },
                set: { item = $0 }
            )
        }

        func body(content: Content) -> some View {
            content
                .sheet(item: sheetItem) { ref in
                    PresentedPlayer(item: ref.item, localOnly: ref.localOnly == true, playlistID: ref.playlistID, playlistEntryID: ref.playlistEntryID, playlistFromBeginning: ref.playlistFromBeginning == true, playlistShuffled: ref.playlistShuffled == true, playbackRequest: ref.resolvedPlaybackRequest)
                        .frame(minWidth: 640, minHeight: 360)
                }
                .onChange(of: item) { _, ref in
                    guard let ref else { return }
                    if ref.item.isAudioPlayable, ContentRatingGate.admitsStored(ref.item) {
                        audio.play(tracks: [ref.item], localOnly: ref.localOnly == true, request: ref.resolvedPlaybackRequest, session: session, downloads: downloads)
                        item = nil
                        return
                    }
                    guard ref.item.opensInPlayerWindow else { return }
                    audio.stop()
                    var request = ref
                    request.serverID = request.serverID ?? session.server.id
                    request.userID = request.userID ?? session.user.id
                    let window = navigation.playerWindows.request(request)
                    openWindow(id: GusPlayerWindow.sceneID, value: window)
                    item = nil
                }
        }
    }

    /// Root of the dedicated macOS player window. The window scene lives outside the
    /// signed-in tree, so the active session is re-derived from `AppModel` here.
    struct GusPlayerWindowContent: View {
        @Environment(AppModel.self) private var appModel
        @Environment(AppNavigationModel.self) private var navigation
        let window: PlayerWindowRef

        var body: some View {
            ZStack {
                let command = navigation.playerWindows.requests[window]
                let ref = command?.ref ?? window.fallback
                if let session = appModel.currentSession, session.isActive,
                   ref.serverID == nil || ref.serverID == session.server.id,
                   ref.userID == nil || ref.userID == session.user.id
                {
                    PresentedPlayer(item: ref.item, localOnly: ref.localOnly == true, playlistID: ref.playlistID, playlistEntryID: ref.playlistEntryID, playlistFromBeginning: ref.playlistFromBeginning == true, playlistShuffled: ref.playlistShuffled == true, playbackRequest: ref.resolvedPlaybackRequest, usesWindowClose: true)
                        .environment(session)
                        .gusArtworkTransport(session.artworkTransport)
                        .id(session.lease.generation)
                        .id(command?.id)
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
            .onAppear { navigation.playerWindows.activate(window) }
            .onDisappear { navigation.playerWindows.deactivate(window) }
        }
    }

#endif

struct PresentedPlayer: View {
    @StoredContentPolicy private var contentPolicy
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    let item: MediaItem
    var localOnly = false
    var playlistID: UUID? = nil
    var playlistEntryID: UUID? = nil
    var playlistFromBeginning = false
    var playlistShuffled = false
    var playbackRequest: PlaybackRequest? = nil
    var close: (() -> Void)?
    var usesWindowClose = false

    var body: some View {
        // Second-layer family-safety gate: list filtering hides restricted items, but
        // playback can be reached via downloads, deep links, or stale navigation.
        if contentPolicy.awaitingRequiredRange || (playlistID == nil && !contentPolicy.admits(item)) {
            NavigationStack {
                RestrictedContentView()
                    .toolbar {
                        if !usesWindowClose {
                            ToolbarItem(placement: .cancellationAction) {
                                GusCloseButton { dismiss() }
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
                PhotoViewerView(photo: item, slideshowAlbumID: playbackRequest?.slideshowAlbumID)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            GusCloseButton {
                                dismiss()
                            }
                        }
                    }
            }
        case .book:
            bookSurface
        default:
            if item.isAudioPlayable {
                AudioPlayerScreen(item: item, localOnly: localOnly, playbackRequest: playbackRequest)
            } else {
                VideoPlayerView(item: item, localOnly: localOnly, playlistID: playlistID, playlistEntryID: playlistEntryID, playlistFromBeginning: playlistFromBeginning, playlistShuffled: playlistShuffled, playbackRequest: playbackRequest)
                    .id(playlistID == nil ? nil : contentPolicy.revision)
                    .id(PlaybackPresentationIdentity(request: playbackRequest ?? PlaybackRequest(item: item), sessionGeneration: session.lease.generation, localOnly: localOnly, playlistID: playlistID, playlistEntryID: playlistEntryID, playlistFromBeginning: playlistFromBeginning, playlistShuffled: playlistShuffled))
            }
        }
    }

    /// Books never route into AVKit. Where Readium is linked the reader opens directly;
    /// elsewhere point at the detail page's share flow instead of failing playback.
    @ViewBuilder
    private var bookSurface: some View {
        if localOnly {
            DownloadedBookPlayerView(item: item, close: close)
        } else {
            #if canImport(ReadiumNavigator)
                BookReaderPresenter(item: item, close: close)
            #else
                NavigationStack {
                    ContentUnavailableView {
                        Label("Reading Isn't Available Here", systemImage: "book")
                    } description: {
                        Text("Open this book's detail page and use Share to read it in Apple Books.")
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            GusCloseButton {
                                dismiss()
                            }
                        }
                    }
                }
            #endif
        }
    }
}
