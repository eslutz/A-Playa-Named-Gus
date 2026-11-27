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
            ToolbarItem(placement: .cancellationAction) { GusCloseButton { dismiss() } }
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
    var close: (() -> Void)?
    @State private var controlsVisible = true
    @State private var progress = ReaderProgress()

    var body: some View {
        NavigationStack {
            #if canImport(PDFKit) && !os(tvOS)
                if PDFDocument(url: fileURL) != nil {
                    LocalPDFSurface(
                        fileURL: fileURL,
                        itemID: item.id,
                        mediaItem: item,
                        scope: AccountScope(serverID: session.server.id, userID: session.user.id),
                        onProgress: { progress = $0 },
                        toggleControls: { controlsVisible.toggle() },
                        onCompletion: { [record = downloads.record(for: item, serverID: session.server.id, userID: session.user.id)] in
                            downloads.deleteAfterCompletion(record)
                        }
                    )
                    .overlay(alignment: .bottom) {
                        if controlsVisible {
                            ReaderProgressFooter(progress: progress)
                        }
                    }
                    .accessibilityAction(named: controlsVisible ? Text("Hide Reading Controls") : Text("Show Reading Controls")) {
                        controlsVisible.toggle()
                    }
                    .navigationTitle(item.displayTitle)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { GusCloseButton { closeReader() } }
                        ToolbarItem { ShareLink(item: fileURL) { Label("Share", systemImage: "square.and.arrow.up") } }
                    }
                    #if os(macOS)
                    .toolbarVisibility(controlsVisible ? .visible : .hidden, for: .windowToolbar)
                    #else
                    .toolbarVisibility(controlsVisible ? .visible : .hidden, for: .navigationBar)
                    .ignoresSafeArea(.container, edges: controlsVisible ? [] : [.top, .bottom])
                    #endif
                    #if os(iOS)
                    .statusBarHidden(!controlsVisible)
                    #endif
                } else {
                    ContentUnavailableView(
                        "Can't Open This Book",
                        systemImage: "book.closed",
                        description: Text("The downloaded PDF could not be opened.")
                    )
                    .toolbar { ToolbarItem(placement: .cancellationAction) { GusCloseButton { closeReader() } } }
                }
            #else
                ContentUnavailableView("Reading Isn't Available Here", systemImage: "book")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { GusCloseButton { closeReader() } } }
            #endif
        }
    }

    private func closeReader() {
        if let close {
            close()
        } else {
            dismiss()
        }
    }
}

#if canImport(PDFKit) && !os(tvOS)
    @MainActor
    private final class PDFReadingCoordinator: NSObject {
        private let itemID: String?
        private let mediaItem: MediaItem?
        private let scope: AccountScope
        private let writerToken: UUID
        private var pageObserver: NSObjectProtocol?
        private let onProgress: (ReaderProgress) -> Void
        private let toggleControls: () -> Void
        private let onCompletion: () -> Void

        init(
            itemID: String?, scope: AccountScope, item: MediaItem,
            onProgress: @escaping (ReaderProgress) -> Void, toggleControls: @escaping () -> Void,
            onCompletion: @escaping () -> Void
        ) {
            self.onProgress = onProgress
            self.toggleControls = toggleControls
            self.onCompletion = onCompletion
            self.itemID = itemID
            self.mediaItem = item
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
            #if os(macOS)
                let click = NSClickGestureRecognizer(target: self, action: #selector(toggleFromInput(_:)))
                click.delegate = self
                view.addGestureRecognizer(click)
            #else
                let tap = UITapGestureRecognizer(target: self, action: #selector(toggleFromInput(_:)))
                tap.cancelsTouchesInView = false
                tap.delegate = self
                view.addGestureRecognizer(tap)
            #endif
            (view as? ReaderPDFView)?.toggleControls = toggleControls
            Task { @MainActor [weak self, weak view] in
                if let view {
                    self?.publishProgress(view)
                }
            }
            pageObserver = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
                MainActor.assumeIsolated {
                    guard let self, let view else { return }
                    self.publishProgress(view)
                    self.save(view)
                }
            }
        }

        private func publishProgress(_ view: PDFView) {
            guard let document = view.document, let page = view.currentPage, document.pageCount > 0 else { return }
            let index = document.index(for: page)
            guard index != NSNotFound else { return }
            let current = index + 1
            onProgress(ReaderProgress(
                fraction: Double(current) / Double(document.pageCount),
                current: current,
                total: document.pageCount,
                atEnd: current == document.pageCount
            ))
        }

        #if os(macOS)
            @objc private func toggleFromInput(_ input: NSClickGestureRecognizer) {
                guard input.state == .ended, let view = input.view as? PDFView else { return }
                toggle(at: input.location(in: view), in: view)
            }
        #else
            @objc private func toggleFromInput(_ input: UITapGestureRecognizer) {
                guard input.state == .ended, let view = input.view as? PDFView else { return }
                toggle(at: input.location(in: view), in: view)
            }
        #endif

        private func toggle(at point: CGPoint, in view: PDFView) {
            guard view.bounds.insetBy(dx: view.bounds.width * 0.2, dy: 0).contains(point),
                  view.currentSelection?.string?.isEmpty != false else { return }
            if let page = view.page(for: point, nearest: false),
               page.annotation(at: view.convert(point, to: page)) != nil
            {
                return
            }
            toggleControls()
        }

        func save(_ view: PDFView) {
            guard OfflinePlaybackProgressStore.shared.writerToken(for: scope) == writerToken,
                  let itemID, OfflinePlaybackProgressStore.shared.acceptsCheckpoint(itemID: itemID, scope: scope),
                  let document = view.document, let currentPage = view.currentPage,
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
                scope: scope, writerToken: writerToken, item: mediaItem
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

    #if os(macOS)
        extension PDFReadingCoordinator: NSGestureRecognizerDelegate {
            func gestureRecognizer(_: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith _: NSGestureRecognizer) -> Bool {
                true
            }
        }

        private final class ReaderPDFView: PDFView {
            var toggleControls: (() -> Void)?

            override func cancelOperation(_ sender: Any?) {
                if let toggleControls {
                    toggleControls()
                } else {
                    super.cancelOperation(sender)
                }
            }
        }
    #else
        extension PDFReadingCoordinator: UIGestureRecognizerDelegate {
            func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
                true
            }

            func gestureRecognizer(_: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
                (other as? UITapGestureRecognizer)?.numberOfTapsRequired == 2
            }
        }

        private final class ReaderPDFView: PDFView {
            var toggleControls: (() -> Void)?

            override var keyCommands: [UIKeyCommand]? {
                (super.keyCommands ?? []) + [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(toggleReaderControls))]
            }

            @objc private func toggleReaderControls() {
                toggleControls?()
            }
        }
    #endif

#endif

#if canImport(PDFKit) && os(macOS)
    private struct LocalPDFSurface: NSViewRepresentable {
        let fileURL: URL
        let itemID: String?
        let mediaItem: MediaItem
        let scope: AccountScope
        let onProgress: (ReaderProgress) -> Void
        let toggleControls: () -> Void
        let onCompletion: () -> Void
        func makeCoordinator() -> PDFReadingCoordinator {
            PDFReadingCoordinator(itemID: itemID, scope: scope, item: mediaItem, onProgress: onProgress, toggleControls: toggleControls, onCompletion: onCompletion)
        }

        func makeNSView(context: Context) -> PDFView {
            let view = ReaderPDFView()
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
        let mediaItem: MediaItem
        let scope: AccountScope
        let onProgress: (ReaderProgress) -> Void
        let toggleControls: () -> Void
        let onCompletion: () -> Void
        func makeCoordinator() -> PDFReadingCoordinator {
            PDFReadingCoordinator(itemID: itemID, scope: scope, item: mediaItem, onProgress: onProgress, toggleControls: toggleControls, onCompletion: onCompletion)
        }

        func makeUIView(context: Context) -> PDFView {
            let view = ReaderPDFView()
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

#if os(macOS)
    import AppKit

    /// Presents the macOS sharing picker once its anchor has entered the sheet window.
    struct NativeBookShareSheet: NSViewRepresentable {
        let fileURL: URL
        let close: () -> Void

        func makeNSView(context _: Context) -> Anchor {
            Anchor(fileURL: fileURL, close: close)
        }

        func updateNSView(_: Anchor, context _: Context) {}

        final class Anchor: NSView, @MainActor NSSharingServicePickerDelegate {
            let picker: NSSharingServicePicker
            let close: () -> Void
            private var presented = false

            init(fileURL: URL, close: @escaping () -> Void) {
                picker = NSSharingServicePicker(items: [fileURL])
                self.close = close
                super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 64))
                picker.delegate = self
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError()
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard window != nil, !presented else { return }
                presented = true
                Task { @MainActor in
                    guard self.window != nil else { return }
                    self.picker.show(relativeTo: self.bounds, of: self, preferredEdge: .minY)
                }
            }

            func sharingServicePicker(_: NSSharingServicePicker, didChoose _: NSSharingService?) {
                close()
            }
        }
    }
#elseif os(iOS) || os(visionOS)
    import UIKit

    /// Receives a prepared local file so the system discovers compatible reader extensions.
    struct NativeBookShareSheet: UIViewControllerRepresentable {
        let fileURL: URL
        let close: () -> Void

        func makeUIViewController(context _: Context) -> UIActivityViewController {
            let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            controller.completionWithItemsHandler = { _, _, _, _ in close() }
            return controller
        }

        func updateUIViewController(_: UIActivityViewController, context _: Context) {}
    }
#endif
