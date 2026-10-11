import SwiftUI
#if canImport(PDFKit) && !os(tvOS)
    import PDFKit
#endif

/// PDF page indices share the account-scoped book locator store without relying on
/// Readium's EPUB locator format. A replaced PDF can safely have fewer pages.
struct OfflinePDFPagePosition: Codable, Equatable {
    let pdfPage: Int

    func boundedPage(pageCount: Int) -> Int {
        min(max(0, pdfPage), max(0, pageCount - 1))
    }

    static func decode(_ json: String?) -> OfflinePDFPagePosition? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    var json: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Native sharing is available on the reading platforms; tvOS can only explain the
/// limitation because it has neither ShareLink nor a book reader.
struct OfflineBookShareView: View {
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    let fileURL: URL

    var body: some View {
        NavigationStack {
            #if os(tvOS)
                ContentUnavailableView("Reading Isn't Available Here", systemImage: "book")
            #else
                ContentUnavailableView {
                    Label("Open in Another App", systemImage: "book")
                } description: {
                    Text("Share this downloaded book with a compatible reader.")
                } actions: {
                    ShareLink(item: fileURL, preview: SharePreview(item.displayTitle)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            #endif
        }
        .navigationTitle(item.displayTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        }
    }
}

/// Uses PDFKit for local PDFs; the file never enters the media streaming path.
struct OfflinePDFBookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    let item: MediaItem
    let fileURL: URL

    var body: some View {
        NavigationStack {
            #if canImport(PDFKit) && !os(tvOS)
                if PDFDocument(url: fileURL) != nil {
                    LocalPDFSurface(
                        fileURL: fileURL,
                        itemID: item.id,
                        scope: AccountScope(serverID: session.server.id, userID: session.user.id),
                        onCompletion: { [record = downloads.record(for: item, serverID: session.server.id, userID: session.user.id)] in
                            downloads.deleteAfterCompletion(record)
                        }
                    )
                    .navigationTitle(item.displayTitle)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                        ToolbarItem { ShareLink(item: fileURL) { Label("Share", systemImage: "square.and.arrow.up") } }
                    }
                } else {
                    ContentUnavailableView(
                        "Can't Open This Book",
                        systemImage: "book.closed",
                        description: Text("The downloaded PDF could not be opened.")
                    )
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                }
            #else
                ContentUnavailableView("Reading Isn't Available Here", systemImage: "book")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            #endif
        }
    }
}

#if canImport(PDFKit) && !os(tvOS)
    @MainActor
    private final class PDFReadingCoordinator: NSObject {
        private let itemID: String?
        private let scope: AccountScope
        private let writerToken: UUID
        private var pageObserver: NSObjectProtocol?
        private let onCompletion: () -> Void

        init(itemID: String?, scope: AccountScope, onCompletion: @escaping () -> Void) {
            self.onCompletion = onCompletion
            self.itemID = itemID
            self.scope = scope
            writerToken = OfflinePlaybackProgressStore.shared.writerToken(for: scope)
        }

        func install(on view: PDFView) {
            if let itemID, let document = view.document,
               let position = OfflinePDFPagePosition.decode(BookProgressStore.shared.locatorJSON(forItemID: itemID, scope: scope)),
               let page = document.page(at: position.boundedPage(pageCount: document.pageCount))
            {
                view.go(to: page)
            }
            pageObserver = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
                MainActor.assumeIsolated {
                    guard let self, let view else { return }
                    self.save(view)
                }
            }
        }

        func save(_ view: PDFView) {
            guard OfflinePlaybackProgressStore.shared.writerToken(for: scope) == writerToken,
                  let itemID, let document = view.document, let currentPage = view.currentPage,
                  document.pageCount > 0 else { return }
            let index = document.index(for: currentPage)
            guard index != NSNotFound else { return }
            let position = OfflinePDFPagePosition(pdfPage: index)
            if let json = position.json {
                BookProgressStore.shared.save(locatorJSON: json, forItemID: itemID, scope: scope)
            }
            let fraction = Double(index + 1) / Double(document.pageCount)
            OfflinePlaybackProgressStore.shared.checkpoint(
                itemID: itemID, positionTicks: JellyfinBookProgress.ticks(forFraction: fraction),
                scope: scope, writerToken: writerToken
            )
        }

        func dismantle(_ view: PDFView) {
            save(view)
            if OfflinePlaybackProgressStore.shared.writerToken(for: scope) == writerToken,
               let document = view.document, let page = view.currentPage,
               document.pageCount > 0, document.index(for: page) == document.pageCount - 1
            {
                view.document = nil
                onCompletion()
            }
            BookProgressStore.shared.flush()
            if let pageObserver {
                NotificationCenter.default.removeObserver(pageObserver)
            }
            pageObserver = nil
        }
    }
#endif

#if canImport(PDFKit) && os(macOS)
    private struct LocalPDFSurface: NSViewRepresentable {
        let fileURL: URL
        let itemID: String?
        let scope: AccountScope
        let onCompletion: () -> Void
        func makeCoordinator() -> PDFReadingCoordinator {
            PDFReadingCoordinator(itemID: itemID, scope: scope, onCompletion: onCompletion)
        }

        func makeNSView(context: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.document = PDFDocument(url: fileURL)
            context.coordinator.install(on: view)
            return view
        }

        func updateNSView(_ view: PDFView, context: Context) {}
        static func dismantleNSView(_ view: PDFView, coordinator: PDFReadingCoordinator) {
            coordinator.dismantle(view)
        }
    }
#elseif canImport(PDFKit) && !os(tvOS)
    private struct LocalPDFSurface: UIViewRepresentable {
        let fileURL: URL
        let itemID: String?
        let scope: AccountScope
        let onCompletion: () -> Void
        func makeCoordinator() -> PDFReadingCoordinator {
            PDFReadingCoordinator(itemID: itemID, scope: scope, onCompletion: onCompletion)
        }

        func makeUIView(context: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.document = PDFDocument(url: fileURL)
            context.coordinator.install(on: view)
            return view
        }

        func updateUIView(_ view: PDFView, context: Context) {}
        static func dismantleUIView(_ view: PDFView, coordinator: PDFReadingCoordinator) {
            coordinator.dismantle(view)
        }
    }
#endif
