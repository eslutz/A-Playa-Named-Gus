import SwiftUI

/// Read / share actions for a book on the detail screen.
///
/// Reading is available where the Readium navigator exists (iOS/iPadOS);
/// the share sheet — whose primary job is "Open in Books" — everywhere except tvOS.
/// tvOS browses book details only. The book file is fetched lazily on first use:
/// only an already-downloaded/cached copy is offered up front, so opening a detail
/// page never downloads the whole book speculatively.
struct BookActionButtons: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    let item: MediaItem

    @State private var shareFileURL: URL?
    @State private var isPreparingShare = false
    @State private var shareErrorMessage: String?
    @State private var readerItem: ItemRef?

    var body: some View {
        #if os(tvOS)
            EmptyView()
        #else
            VStack(alignment: .leading, spacing: 10) {
                #if canImport(ReadiumNavigator)
                    Button {
                        readerItem = ItemRef(item: item)
                    } label: {
                        Label("Read", systemImage: "book")
                            .gusProminentActionForeground()
                    }
                    .gusProminentGlassButtonStyle()
                    .controlSize(.large)
                    .gusProminentActionTint()
                    .visionHoverEffect(cornerRadius: 10)
                #endif

                shareControl
            }
            .task(id: item.id) {
                // Cheap, local-only probe so Share is a single tap when the file is
                // already on device; otherwise the button fetches on demand.
                shareFileURL = BookFileProvider(session: session, downloads: downloads).existingLocalFile(for: item)
            }
            #if canImport(ReadiumNavigator)
            .playerPresentation(item: $readerItem)
            #endif
            .alert(
                "Couldn't Prepare Book",
                isPresented: Binding(
                    get: { shareErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            shareErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    shareErrorMessage = nil
                }
            } message: {
                Text(shareErrorMessage ?? "")
            }
        #endif
    }

    #if !os(tvOS)
        @ViewBuilder
        private var shareControl: some View {
            if let shareFileURL {
                ShareLink(item: shareFileURL, preview: SharePreview(item.displayTitle)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .gusGlassButtonStyle()
                .controlSize(.large)
                .visionHoverEffect(cornerRadius: 10)
                .accessibilityHint("Opens the share sheet — use it to open this book in Apple Books.")
            } else {
                Button {
                    prepareShare()
                } label: {
                    if isPreparingShare {
                        Label {
                            Text("Preparing…")
                        } icon: {
                            ProgressView()
                                .controlSize(.small)
                        }
                    } else {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                .gusGlassButtonStyle()
                .controlSize(.large)
                .disabled(isPreparingShare)
                .visionHoverEffect(cornerRadius: 10)
                .accessibilityHint("Downloads the book, then offers the share sheet — use it to open this book in Apple Books.")
            }
        }

        private func prepareShare() {
            guard !isPreparingShare else { return }
            isPreparingShare = true
            Task {
                defer { isPreparingShare = false }
                do {
                    shareFileURL = try await BookFileProvider(session: session, downloads: downloads).localFile(for: item)
                } catch {
                    let gusError = GusError(from: error)
                    guard !gusError.isCancellation else { return }
                    shareErrorMessage = gusError.localizedDescription
                }
            }
        }
    #endif
}

#if canImport(ReadiumNavigator)
    /// Fetches the book file (preferring an offline download), then presents the reader.
    /// Shared by the detail screen's Read button and the Downloads list, so the fetch +
    /// error handling live in one place and the file is only downloaded on intent.
    struct BookReaderPresenter: View {
        @Environment(SessionStore.self) private var session
        @Environment(OfflineDownloadStore.self) private var downloads
        @Environment(\.dismiss) private var dismiss
        let item: MediaItem
        var close: (() -> Void)?

        @State private var fileURL: URL?
        @State private var errorMessage: String?
        @State private var retryGeneration = 0
        @State private var preparation: Task<Void, Never>?

        var body: some View {
            Group {
                if let fileURL {
                    BookReaderScreen(
                        item: item,
                        fileURL: fileURL,
                        provider: session.mediaProvider,
                        accountScope: AccountScope(serverID: session.server.id, userID: session.user.id),
                        close: close
                    )
                } else {
                    NavigationStack {
                        Group {
                            if let errorMessage {
                                ContentUnavailableView {
                                    Label("Can't Open This Book", systemImage: "book.closed")
                                } description: { Text(errorMessage) } actions: {
                                    Button("Try Again") { self.errorMessage = nil; retryGeneration += 1 }
                                }
                            } else {
                                ProgressView("Preparing Book…").frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                GusCloseButton {
                                    preparation?.cancel()
                                    if let close {
                                        close()
                                    } else {
                                        dismiss()
                                    }
                                }
                                .accessibilityIdentifier("BookReader.done")
                            }
                        }
                    }
                }
            }
            .task(id: retryGeneration) {
                guard fileURL == nil else { return }
                let task = Task {
                    do {
                        let url = try await BookFileProvider(session: session, downloads: downloads).localFile(for: item)
                        try Task.checkCancellation()
                        fileURL = url
                    } catch {
                        let failure = GusError(from: error)
                        if !failure.isCancellation && !Task.isCancelled {
                            errorMessage = failure.localizedDescription
                        }
                    }
                }
                preparation = task
                await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            }
            .onDisappear { preparation?.cancel() }
        }
    }
#endif
