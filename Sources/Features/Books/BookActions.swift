import SwiftUI

/// The reader and progress belong beside the book's synopsis.
struct BookActionButtons: View {
    let item: MediaItem
    var progress: BookDetailProgress? = nil

    #if canImport(ReadiumNavigator)
        @State private var readerItem: ItemRef?
    #endif

    var body: some View {
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
                .playerPresentation(item: $readerItem)
            #endif

            if let progress {
                BookDetailProgressBar(progress: progress)
            }
        }
    }
}

#if !os(tvOS)
    /// Use the actual local file URL so the system offers readers for its format.
    struct ExternalBookReaderSheet: View {
        @Environment(SessionStore.self) private var session
        @Environment(OfflineDownloadStore.self) private var downloads
        @Environment(\.dismiss) private var dismiss
        let item: MediaItem
        @State private var fileURL: URL?
        @State private var errorMessage: String?
        @State private var attempt = 0

        var body: some View {
            Group {
                if let fileURL {
                    OfflineBookShareView(item: item, fileURL: fileURL)
                } else {
                    NavigationStack {
                        Group {
                            if let errorMessage {
                                ContentUnavailableView {
                                    Label("Couldn't Prepare Book", systemImage: "book.closed")
                                } description: {
                                    Text(errorMessage)
                                } actions: {
                                    Button("Try Again") { self.errorMessage = nil; attempt += 1 }
                                }
                            } else {
                                ProgressView("Preparing Book…")
                            }
                        }
                        .padding()
                        .navigationTitle("Open in Another App")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { GusCloseButton { dismiss() } }
                        }
                    }
                }
            }
            .task(id: attempt) {
                let provider = BookFileProvider(session: session, downloads: downloads)
                do {
                    let url: URL
                    if let cached = provider.existingLocalFile(for: item) {
                        url = cached
                    } else {
                        url = try await provider.localFile(for: item)
                    }
                    try Task.checkCancellation()
                    guard session.isActive else { return }
                    fileURL = url
                } catch {
                    let failure = GusError(from: error)
                    if !Task.isCancelled, !failure.isCancellation {
                        errorMessage = failure.localizedDescription
                    }
                }
            }
        }
    }
#endif

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
            if ticks == 0, locator == nil {
                return data?.isWatched == true ? .fraction(1) : nil
            }
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
