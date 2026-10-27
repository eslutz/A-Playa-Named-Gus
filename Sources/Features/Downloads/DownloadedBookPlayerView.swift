import SwiftUI

/// Opens the confirmed local file using the existing EPUB reader or native document
/// surface. Unsupported reader platforms can share the file directly to Apple Books.
struct DownloadedBookPlayerView: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    var close: (() -> Void)?

    var body: some View {
        if let url = downloads.localFileURL(for: item, serverID: session.server.id, userID: session.user.id) {
            switch DownloadedBookFormat(fileExtension: url.pathExtension) {
            case .pdf:
                OfflinePDFBookView(item: item, fileURL: url)
            case .epub:
                epubSurface(fileURL: url)
            case .externalReader:
                OfflineBookShareView(item: item, fileURL: url)
            }
        } else {
            NavigationStack {
                ContentUnavailableView("Download Unavailable", systemImage: "book.closed", description: Text("The downloaded file is missing. Manage Downloads to download it again."))
                    .toolbar { ToolbarItem(placement: .cancellationAction) { GusCloseButton { dismiss() } } }
            }
        }
    }

    @ViewBuilder
    private func epubSurface(fileURL: URL) -> some View {
        #if canImport(ReadiumNavigator)
            BookReaderScreen(
                item: item, fileURL: fileURL, provider: nil,
                accountScope: AccountScope(serverID: session.server.id, userID: session.user.id),
                close: close
            )
        #else
            OfflineBookShareView(item: item, fileURL: fileURL)
        #endif
    }
}
