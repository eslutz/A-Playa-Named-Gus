#if canImport(ReadiumNavigator)
    import ReadiumAdapterGCDWebServer
    import ReadiumNavigator
    import ReadiumShared
    import ReadiumStreamer
    import SwiftUI

    /// Readium-based EPUB reader for iOS/iPadOS, with chapter navigation and local
    /// resume. ADR 0009 records the dependency exception; tvOS/macOS don't link Readium
    /// and use book details / "Open in Books" instead, and visionOS joins once
    /// readium/swift-toolkit compiles for the native xrOS SDK (see the ADR).
    struct BookReaderScreen: View {
        @Environment(\.dismiss) private var dismiss
        let item: MediaItem
        let fileURL: URL
        let provider: (any MediaProviderSession)?

        @State private var model: BookReaderModel?

        var body: some View {
            NavigationStack {
                Group {
                    if let model {
                        content(model)
                    } else {
                        ProgressView()
                    }
                }
                .navigationTitle(item.displayTitle)
                #if !os(visionOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                        ToolbarItem {
                            if let model, !model.tableOfContents.isEmpty {
                                chaptersMenu(model)
                            }
                        }
                    }
            }
            .task {
                if model == nil {
                    let model = BookReaderModel(item: item, fileURL: fileURL, provider: provider)
                    self.model = model
                    await model.open()
                }
            }
            .onDisappear {
                model?.flushProgress()
            }
        }

        @ViewBuilder
        private func content(_ model: BookReaderModel) -> some View {
            switch model.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Can't Open This Book", systemImage: "book.closed")
                } description: {
                    Text(message)
                }
            case .loaded:
                EPUBNavigatorRepresentable(model: model)
                    .ignoresSafeArea(edges: .bottom)
            }
        }

        private func chaptersMenu(_ model: BookReaderModel) -> some View {
            Menu {
                ForEach(Array(model.tableOfContents.enumerated()), id: \.offset) { _, link in
                    Button(link.title ?? link.href.description) {
                        model.go(to: link)
                    }
                }
            } label: {
                Label("Chapters", systemImage: "list.bullet")
            }
            .accessibilityLabel("Chapters")
        }
    }

    /// Opens the publication, owns the navigator, and persists reading position.
    @MainActor
    @Observable
    final class BookReaderModel {
        private(set) var state: LoadState = .idle
        private(set) var tableOfContents: [ReadiumShared.Link] = []
        private(set) var publication: Publication?
        private(set) var initialLocation: Locator?

        let item: MediaItem
        let fileURL: URL
        private let provider: (any MediaProviderSession)?
        private let progressStore = BookProgressStore.shared
        weak var navigator: EPUBNavigatorViewController?

        // Server sync is best-effort and debounced so a page-turn burst is one write.
        private var pendingFraction: Double?
        private var reportTask: Task<Void, Never>?

        // Shared Readium plumbing: the navigator serves resources over a loopback server.
        private static let httpClient = DefaultHTTPClient()
        private static let assetRetriever = AssetRetriever(httpClient: httpClient)
        static let httpServer = GCDHTTPServer(assetRetriever: assetRetriever)

        init(item: MediaItem, fileURL: URL, provider: (any MediaProviderSession)?) {
            self.item = item
            self.fileURL = fileURL
            self.provider = provider
        }

        private var syncEnabled: Bool {
            provider?.capabilities.supportsBookProgressSync == true
        }

        func open() async {
            guard state == .idle else { return }
            state = .loading

            guard let url = FileURL(url: fileURL) else {
                state = .failed(String(localized: "The book file is missing.", comment: "Book reader error"))
                return
            }

            let opener = PublicationOpener(
                parser: DefaultPublicationParser(
                    httpClient: Self.httpClient,
                    assetRetriever: Self.assetRetriever,
                    pdfFactory: DefaultPDFDocumentFactory()
                ),
                contentProtections: []
            )

            switch await Self.assetRetriever.retrieve(url: url) {
            case let .success(asset):
                switch await opener.open(asset: asset, allowUserInteraction: false, sender: nil) {
                case let .success(publication):
                    self.publication = publication
                    tableOfContents = (try? await publication.tableOfContents().get()) ?? []
                    initialLocation = await resolveInitialLocation(in: publication)
                    state = .loaded
                case let .failure(error):
                    state = .failed(error.localizedDescription)
                }
            case let .failure(error):
                state = .failed(error.localizedDescription)
            }
        }

        /// Prefers the exact local locator (same device); otherwise restores from the
        /// server's coarse fraction so a book resumes across devices.
        private func resolveInitialLocation(in publication: Publication) async -> Locator? {
            guard let itemID = item.id else { return nil }
            if let json = progressStore.locatorJSON(forItemID: itemID),
               let locator = try? Locator(jsonString: json)
            {
                return locator
            }
            // `try?` flattens bookProgress's optional, so a single bind yields the fraction.
            guard syncEnabled, let provider,
                  let fraction = try? await provider.bookProgress(itemID: itemID)
            else { return nil }
            return await publication.locate(progression: fraction)
        }

        func saveLocation(_ locator: Locator) {
            guard let itemID = item.id else { return }
            if let json = try? locator.jsonString() {
                progressStore.save(locatorJSON: json, forItemID: itemID)
            }
            scheduleRemoteReport(fraction: locator.locations.totalProgression)
        }

        /// Coalesces page-turn bursts into a single best-effort server write.
        private func scheduleRemoteReport(fraction: Double?) {
            guard syncEnabled, let fraction else { return }
            pendingFraction = fraction
            reportTask?.cancel()
            reportTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await self?.sendReport()
            }
        }

        /// Flushes any pending position immediately — call when the reader closes.
        func flushProgress() {
            progressStore.flush()
            reportTask?.cancel()
            Task { await sendReport() }
        }

        private func sendReport() async {
            guard syncEnabled, let provider, let itemID = item.id,
                  let fraction = pendingFraction else { return }
            pendingFraction = nil
            try? await provider.reportBookProgress(itemID: itemID, fraction: fraction)
        }

        func go(to link: ReadiumShared.Link) {
            guard let navigator else { return }
            Task {
                await navigator.go(to: link, options: NavigatorGoOptions(animated: true))
            }
        }
    }

    private struct EPUBNavigatorRepresentable: UIViewControllerRepresentable {
        let model: BookReaderModel

        func makeUIViewController(context: Context) -> UIViewController {
            guard let publication = model.publication,
                  let navigator = try? EPUBNavigatorViewController(
                      publication: publication,
                      initialLocation: model.initialLocation,
                      config: EPUBNavigatorViewController.Configuration(),
                      httpServer: BookReaderModel.httpServer
                  )
            else {
                return UIViewController()
            }
            navigator.delegate = context.coordinator
            model.navigator = navigator
            return navigator
        }

        func updateUIViewController(_ controller: UIViewController, context: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(model: model)
        }

        final class Coordinator: NSObject, EPUBNavigatorDelegate {
            private let model: BookReaderModel

            init(model: BookReaderModel) {
                self.model = model
            }

            func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
                MainActor.assumeIsolated {
                    model.saveLocation(locator)
                }
            }

            func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
                // Readium surfaces resource errors here; the reader keeps the last good page.
            }
        }
    }
#endif
