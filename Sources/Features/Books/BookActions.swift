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
    var progress: BookDetailProgress? = nil

    @State private var shareFileURL: URL?
    @State private var isPreparingShare = false
    @State private var shareErrorMessage: String?
    @State private var readerItem: ItemRef?

    var body: some View {
        #if os(tvOS)
            if let progress {
                BookDetailProgressBar(progress: progress)
            }
        #else
            VStack(alignment: .leading, spacing: 10) {
                #if canImport(ReadiumNavigator)
                    Button {
                        readerItem = ItemRef(item: item)
                    } label: {
                        Label(progress?.isInProgress == true ? "Continue Reading" : "Read", systemImage: "book")
                            .gusProminentActionForeground()
                    }
                    .gusProminentGlassButtonStyle()
                    .controlSize(.large)
                    .gusProminentActionTint()
                    .visionHoverEffect(cornerRadius: 10)
                #endif

                if let progress {
                    BookDetailProgressBar(progress: progress)
                }
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

enum BookDetailProgress: Equatable {
    case fraction(Double)
    case unknown

    var isInProgress: Bool {
        self != .fraction(1)
    }

    static func reading(locator: String?, localTicks: Int?, data: MediaUserData?) -> Self? {
        if let fraction = BookDetailMetadata.epubFraction(locator: locator), fraction.isFinite {
            return .fraction(min(max(fraction, 0), 1))
        }
        if let ticks = localTicks {
            return .fraction(JellyfinBookProgress.fraction(forTicks: ticks))
        }
        if let percentage = data?.playedPercentage, percentage > 0, percentage.isFinite {
            return .fraction(min(percentage / 100, 1))
        }
        if let ticks = data?.playbackPositionTicks, ticks > 0 {
            return .fraction(JellyfinBookProgress.fraction(forTicks: ticks))
        }
        if locator != nil {
            return .unknown
        }
        if data?.isWatched == true {
            return .fraction(1)
        }
        return data?.lastPlayedAt != nil ? .unknown : nil
    }

    static func listening(ticks: Int?, duration: Int?, percent: Double?, started: Bool = false, completed: Bool = false) -> Self? {
        if let ticks, ticks > 0 || (started && !completed), let duration, duration > 0 {
            return .fraction(min(max(Double(ticks) / Double(duration), 0), 1))
        }
        if let percent, percent > 0, percent.isFinite {
            return .fraction(min(percent / 100, 1))
        }
        if (ticks ?? 0) > 0 {
            return .unknown
        }
        if completed {
            return .fraction(1)
        }
        return started ? .unknown : nil
    }
}

struct BookDetailProgressBar: View {
    let progress: BookDetailProgress

    var body: some View {
        Group {
            switch progress {
            case let .fraction(value):
                ProgressView(value: value) {
                    Text(value.formatted(.percent.precision(.fractionLength(0))))
                }
                .accessibilityLabel("Progress")
            case .unknown:
                VStack(alignment: .leading, spacing: 4) {
                    Text("In progress · percentage unavailable").font(.caption)
                    Capsule().fill(.quaternary).frame(height: 4).accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .accessibilityIdentifier("Detail.bookProgress")
    }
}
