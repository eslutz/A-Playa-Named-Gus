#if canImport(ReadiumNavigator)
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
        @Environment(OfflineDownloadStore.self) private var downloads
        @State private var openedDownload: OfflineDownloadRecord?
        let item: MediaItem
        let fileURL: URL
        let provider: (any MediaProviderSession)?
        let accountScope: AccountScope
        var close: (() -> Void)?

        @State private var model: BookReaderModel?
        @State private var showingChapters = false

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
                                // The session host owns this cover; do not dismiss
                                // an ancestor detail sheet after adaptive relayout.
                                if let close {
                                    close()
                                } else {
                                    dismiss()
                                }
                            }
                            .accessibilityIdentifier("BookReader.done")
                        }
                        ToolbarItem {
                            if let model, !model.tableOfContents.isEmpty {
                                chaptersButton(model)
                            }
                        }
                    }
            }
            .sheet(isPresented: $showingChapters, onDismiss: {
                guard let navigator = model?.navigator, navigator.viewIfLoaded?.window != nil else { return }
                navigator.becomeFirstResponder()
            }) {
                if let model {
                    chapterBrowser(model)
                }
            }
            .task {
                if model == nil {
                    openedDownload = downloads.record(for: item, serverID: accountScope.serverID, userID: accountScope.userID)
                    let model = BookReaderModel(
                        item: item,
                        fileURL: fileURL,
                        provider: provider,
                        accountScope: accountScope
                    )
                    self.model = model
                    await model.open()
                }
            }
            .onDisappear {
                model?.flushProgress()
                // Presenting the chapter browser does not close the reader.
                if !showingChapters, model?.isAtEnd == true {
                    downloads.deleteAfterCompletion(openedDownload)
                }
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

        private func chaptersButton(_ model: BookReaderModel) -> some View {
            Button("Chapters", systemImage: "list.bullet") {
                model.navigator?.view.window?.endEditing(true)
                showingChapters = true
            }
            .accessibilityLabel("Chapters")
        }

        private func chapterBrowser(_ model: BookReaderModel) -> some View {
            NavigationStack {
                List {
                    BookChapterListEntries(links: model.tableOfContents) { link in
                        model.go(to: link)
                        showingChapters = false
                    }
                }
                .navigationTitle("Chapters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showingChapters = false }
                            .accessibilityIdentifier("BookChapters.done")
                    }
                }
            }
        }
    }

    /// EPUB tables of contents can group chapters beneath a book or part entry.
    /// Preserve that hierarchy in a native list and keep each parent readable.
    private struct BookChapterListEntries: View {
        let links: [ReadiumShared.Link]
        let navigate: (ReadiumShared.Link) -> Void

        var body: some View {
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                let title = link.title ?? link.href.description
                if link.children.isEmpty {
                    if link.href.isEmpty || link.href == "#" {
                        Text(title)
                    } else {
                        Button(title) { navigate(link) }
                    }
                } else {
                    DisclosureGroup {
                        if !link.href.isEmpty, link.href != "#" {
                            Button("Open \(title)") { navigate(link) }
                                .accessibilityIdentifier("BookChapters.open.\(title)")
                        }
                        BookChapterListEntries(links: link.children, navigate: navigate)
                    } label: {
                        Text(title)
                    }
                    .accessibilityIdentifier("BookChapters.group.\(title)")
                }
            }
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
        private let accountScope: AccountScope
        private let progressWriterToken: UUID
        private let progressStore = BookProgressStore.shared
        weak var navigator: EPUBNavigatorViewController?

        // Server sync is best-effort and debounced so a page-turn burst is one write.
        private var pendingFraction: Double?
        private var finalPageVisible = false
        private var reportTask: Task<Void, Never>?

        // Shared Readium plumbing for opening local publication assets.
        private static let httpClient = DefaultHTTPClient()
        private static let assetRetriever = AssetRetriever(httpClient: httpClient)

        init(
            item: MediaItem,
            fileURL: URL,
            provider: (any MediaProviderSession)?,
            accountScope: AccountScope
        ) {
            self.item = item
            self.fileURL = fileURL
            self.provider = provider
            self.accountScope = accountScope
            progressWriterToken = OfflinePlaybackProgressStore.shared.writerToken(for: accountScope)
        }

        /// Use the visible end of the final reading-order resource, not a 90% guess
        /// or the locator at the beginning of the current page.
        var isAtEnd: Bool {
            OfflinePlaybackProgressStore.shared.writerToken(for: accountScope) == progressWriterToken && finalPageVisible
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
            if let json = progressStore.locatorJSON(forItemID: itemID, scope: accountScope),
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
            if let last = publication?.readingOrder.last?.url(),
               let visible = navigator?.viewport?.resources.last
            {
                finalPageVisible = visible.href == last && visible.progression.upperBound >= 1
            } else {
                finalPageVisible = false
            }
            guard OfflinePlaybackProgressStore.shared.writerToken(for: accountScope) == progressWriterToken,
                  let itemID = item.id else { return }
            if let json = try? locator.jsonString() {
                progressStore.save(locatorJSON: json, forItemID: itemID, scope: accountScope)
            }
            if provider == nil, let fraction = locator.locations.totalProgression {
                OfflinePlaybackProgressStore.shared.checkpoint(
                    itemID: itemID, positionTicks: JellyfinBookProgress.ticks(forFraction: fraction), scope: accountScope, writerToken: progressWriterToken
                )
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
                      config: EPUBNavigatorViewController.Configuration()
                  )
            else {
                return UIViewController()
            }
            navigator.delegate = context.coordinator
            context.coordinator.bindInput(to: navigator)
            model.navigator = navigator
            return navigator
        }

        func updateUIViewController(_ controller: UIViewController, context: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(model: model)
        }

        @MainActor final class Coordinator: NSObject, EPUBNavigatorDelegate {
            private let model: BookReaderModel
            private let directionalNavigation = DirectionalNavigationAdapter()

            init(model: BookReaderModel) {
                self.model = model
            }

            func bindInput(to navigator: EPUBNavigatorViewController) {
                directionalNavigation.bind(to: navigator)
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
