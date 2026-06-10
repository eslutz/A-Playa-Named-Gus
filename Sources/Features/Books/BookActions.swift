import SwiftUI

/// Read / share actions for a book on the detail screen.
///
/// Reading is available where the Readium navigator exists (iOS/iPadOS/visionOS);
/// the share sheet — whose primary job is "Open in Books" — everywhere except tvOS.
/// tvOS browses book details only.
struct BookActionButtons: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    let item: MediaItem

    @State private var fileURL: URL?
    @State private var fetchErrorMessage: String?
    @State private var isReaderPresented = false

    var body: some View {
        #if os(tvOS)
            EmptyView()
        #else
            HStack(spacing: 10) {
                #if canImport(ReadiumNavigator)
                    Button {
                        isReaderPresented = true
                    } label: {
                        Label("Read", systemImage: "book")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.accentColor)
                    .disabled(fileURL == nil)
                    .visionHoverEffect(cornerRadius: 10)
                #endif

                if let fileURL {
                    ShareLink(item: fileURL, preview: SharePreview(item.displayTitle)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .visionHoverEffect(cornerRadius: 10)
                    .accessibilityHint("Opens the share sheet — use it to open this book in Apple Books.")
                } else if fetchErrorMessage == nil {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Preparing book")
                }
            }
            .task(id: item.id) {
                await fetchFile()
            }
            #if canImport(ReadiumNavigator)
            .fullScreenCover(isPresented: $isReaderPresented) {
                if let fileURL {
                    BookReaderScreen(item: item, fileURL: fileURL, provider: session.mediaProvider)
                }
            }
            #endif
        #endif
    }

    private func fetchFile() async {
        guard fileURL == nil else { return }
        do {
            fileURL = try await BookFileProvider(session: session, downloads: downloads).localFile(for: item)
            fetchErrorMessage = nil
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            fetchErrorMessage = gusError.localizedDescription
        }
    }
}
