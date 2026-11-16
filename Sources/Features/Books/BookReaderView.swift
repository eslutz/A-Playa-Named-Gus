#if canImport(ReadiumNavigator)
    import OSLog
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
                            ImmersiveDismissButton {
                                model?.close()
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
            .safeAreaInset(edge: .bottom) {
                if let model, let notice = model.resourceNotice {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(notice)
                        HStack {
                            Button("Try Again") { Task { await model.retryResource() } }
                            Button("Dismiss", role: .cancel) { model.dismissResourceNotice() }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                }
            }
            .alert("Book Reader", isPresented: Binding(get: { model?.readerNotice != nil }, set: {
                if !$0 {
                    model?.clearNotice()
                }
            })) {
                Button("Keep Reading", role: .cancel) { model?.clearNotice() }
            } message: { Text(model?.readerNotice ?? "") }
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
                }
                await model?.activate()
            }
            .onDisappear {
                model?.flushProgress()
                // Presenting the chapter browser does not close the reader.
                if !showingChapters {
                    if model?.isAtEnd == true {
                        downloads.deleteAfterCompletion(openedDownload)
                    }
                    model?.close()
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
                } actions: {
                    Button("Try Again") { Task { await model.retry() } }
                        .disabled(!model.canRetryOpening)
                }
            case .loaded:
                EPUBNavigatorRepresentable(model: model, generation: model.navigatorIdentity)
                    .id(model.navigatorIdentity)
                    .ignoresSafeArea(edges: .bottom)
            }
        }

        private func chaptersButton(_ model: BookReaderModel) -> some View {
            Button("Chapters", systemImage: "list.bullet") {
                model.navigator?.view.window?.endEditing(true)
                showingChapters = true
            }
            .gusIPadIconOnly()
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
                        GusCloseButton { showingChapters = false }
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
        private(set) var readerNotice: String?
        private(set) var actionOutcome: ActionOutcome?
        private(set) var resourceNotice: String?
        private(set) var navigatorIdentity = UUID()
        private var reportedResourceHrefs = Set<String>()
        private var isClosed = false
        private var navigationTask: Task<Void, Never>?
        private var navigationDeadlineTask: Task<Void, Never>?
        private var chapterRequest: (id: UUID, href: AnyURL)?
        private let chapterTimeout: Duration
        private let navigate: @MainActor (EPUBNavigatorViewController, ReadiumShared.Link) async -> Bool
        private let logger = Logger(category: .item)

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

        init(
            item: MediaItem,
            fileURL: URL,
            provider: (any MediaProviderSession)?,
            accountScope: AccountScope,
            chapterTimeout: Duration = .seconds(30),
            navigate: @escaping @MainActor (EPUBNavigatorViewController, ReadiumShared.Link) async -> Bool = { navigator, link in
                await navigator.go(to: link, options: NavigatorGoOptions(animated: true))
            }
        ) {
            self.chapterTimeout = chapterTimeout
            self.navigate = navigate
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

        func navigatorConstructionFailed() {
            logger.error("EPUB navigator construction failed")
            navigator = nil
            let message = String(localized: "The book reader could not be created. Try again.")
            state = .failed(message)
            actionOutcome = .failed(.server(message))
        }

        func owns(generation: UUID) -> Bool {
            !isClosed && navigatorIdentity == generation &&
                OfflinePlaybackProgressStore.shared.writerToken(for: accountScope) == progressWriterToken
        }

        func accepts(_ navigator: Navigator, generation: UUID) -> Bool {
            owns(generation: generation) && self.navigator === navigator
        }

        func resourceFailed(_ error: Error, href: String = "") {
            guard owns(generation: navigatorIdentity) else { return }
            let failure = BookResourceFailure(href: href, error: error).error
            guard !failure.isCancellation else { return }
            let requested = chapterRequest?.href.string == href
            let first = reportedResourceHrefs.insert(href).inserted
            guard first || requested else { return }
            if requested {
                cancelNavigation()
            }
            logger.error("EPUB resource failure: \(String(reflecting: type(of: error)), privacy: .public)")
            progressStore.flush()
            actionOutcome = .failed(failure)
            resourceNotice = String(localized: "Some content in this book couldn't be loaded. Try again from your saved reading position, or dismiss this notice to keep reading.")
        }

        func acceptResourceFailure(_ failure: BookResourceFailure, generation: UUID) {
            guard owns(generation: generation) else { return }
            resourceFailed(failure.error, href: failure.href)
        }

        func dismissResourceNotice() {
            resourceNotice = nil
        }

        private func cancelNavigation() {
            navigationTask?.cancel()
            navigationTask = nil
            navigationDeadlineTask?.cancel()
            navigationDeadlineTask = nil
            chapterRequest = nil
        }

        var canRetryOpening: Bool {
            !isClosed && OfflinePlaybackProgressStore.shared.writerToken(for: accountScope) == progressWriterToken
        }

        func activate() async {
            guard OfflinePlaybackProgressStore.shared.writerToken(for: accountScope) == progressWriterToken else {
                state = .failed(String(localized: "The book reader could not be created. Try again."))
                actionOutcome = .failed(.cancelled)
                return
            }
            if isClosed {
                isClosed = false
                publication = nil
                state = .idle
                clearNotice()
                dismissResourceNotice()
            }
            await open()
        }

        func close() {
            guard !isClosed else { return }
            isClosed = true
            cancelNavigation()
            navigatorIdentity = UUID()
            navigator = nil
            publication = nil
            state = .idle
            flushProgress()
        }

        func copyingForbidden() {
            guard readerNotice == nil else { return }
            actionOutcome = .failed(.forbidden)
            readerNotice = String(localized: "This book doesn't allow copying text.")
        }

        func clearNotice() {
            readerNotice = nil
            if resourceNotice == nil {
                actionOutcome = nil
            }
        }

        func retryResource() async {
            guard !isClosed else { return }
            cancelNavigation()
            flushProgress()
            clearNotice()
            dismissResourceNotice()
            navigator = nil
            publication = nil
            state = .idle
            await open()
        }

        func retry() async {
            guard case .failed = state, canRetryOpening else { return }
            state = .idle
            await activate()
        }

        func open() async {
            guard state == .idle, !isClosed, !Task.isCancelled else { return }
            navigatorIdentity = UUID()
            let generation = navigatorIdentity
            reportedResourceHrefs.removeAll()
            state = .loading
            actionOutcome = .pending

            guard let url = FileURL(url: fileURL) else {
                let message = String(localized: "The book file is missing.", comment: "Book reader error")
                state = .failed(message)
                actionOutcome = .failed(.notFound)
                return
            }

            let locatorJSON = item.id.flatMap {
                progressStore.locatorJSON(forItemID: $0, scope: accountScope)
            }
            switch await Self.openPublication(
                at: url,
                locatorJSON: locatorJSON,
                provider: syncEnabled ? provider : nil,
                itemID: item.id,
                resourceFailure: { [weak self] failure in
                    Task { @MainActor [weak self] in
                        self?.acceptResourceFailure(failure, generation: generation)
                    }
                }
            ) {
            case let .loaded(publication, tableOfContents, initialLocation):
                guard owns(generation: generation) else { return }
                guard !Task.isCancelled else { state = .idle; actionOutcome = nil; return }
                self.publication = publication
                self.tableOfContents = tableOfContents
                self.initialLocation = initialLocation
                state = .loaded
                actionOutcome = .confirmed
            case let .failed(message):
                guard owns(generation: generation) else { return }
                guard !Task.isCancelled else { state = .idle; actionOutcome = nil; return }
                state = .failed(message)
                actionOutcome = .failed(.server(message))
            }
        }

        /// Build and query the Readium objects in one nonisolated loading
        /// operation, before any navigator can access them. Each load owns its
        /// retriever/parser. `sending` transfers the completed publication once
        /// to the main-actor reader without asserting that it is Sendable.
        @concurrent
        private nonisolated static func openPublication(
            at url: FileURL,
            locatorJSON: String?,
            provider: (any MediaProviderSession)?,
            itemID: String?,
            resourceFailure: @escaping @Sendable (BookResourceFailure) -> Void
        ) async -> sending BookPublicationOpenResult {
            let httpClient = DefaultHTTPClient()
            let assetRetriever = AssetRetriever(httpClient: httpClient)
            let opener = PublicationOpener(
                parser: DefaultPublicationParser(
                    httpClient: httpClient,
                    assetRetriever: assetRetriever,
                    pdfFactory: DefaultPDFDocumentFactory()
                ),
                contentProtections: []
            )

            switch await assetRetriever.retrieve(url: url) {
            case let .success(asset):
                switch await opener.open(asset: asset, allowUserInteraction: false, onCreatePublication: { manifest, container, _ in
                    container = BookReportingContainer(upstream: container, declared: manifest.readingOrder + manifest.resources, report: resourceFailure)
                }, sender: nil) {
                case let .success(publication):
                    let tableOfContents = await(try? publication.tableOfContents().get()) ?? []
                    let initialLocation: Locator? = if let locatorJSON, let locator = try? Locator(jsonString: locatorJSON) {
                        locator
                    } else if let itemID, let provider,
                              let fraction = try? await provider.bookProgress(itemID: itemID)
                    {
                        await publication.locate(progression: fraction)
                    } else {
                        nil
                    }
                    return .loaded(publication, tableOfContents, initialLocation)
                case let .failure(error):
                    return .failed(error.localizedDescription)
                }
            case let .failure(error):
                return .failed(error.localizedDescription)
            }
        }

        func saveLocation(_ locator: Locator) {
            initialLocation = locator
            if let request = chapterRequest {
                if BookReportingContainer.canonical(locator.href.anyURL).isEquivalentTo(request.href) {
                    cancelNavigation()
                    actionOutcome = .confirmed
                }
            } else if actionOutcome == .pending || actionOutcome == .accepted {
                actionOutcome = .confirmed
            }
            if let last = publication?.readingOrder.last?.url(),
               let visible = navigator?.viewport?.resources.last
            {
                finalPageVisible = visible.href.isEquivalentTo(last) && visible.progression.upperBound >= 1
            } else {
                finalPageVisible = false
            }
            guard OfflinePlaybackProgressStore.shared.writerToken(for: accountScope) == progressWriterToken,
                  let itemID = item.id else { return }
            if let json = try? locator.jsonString() {
                progressStore.save(locatorJSON: json, forItemID: itemID, scope: accountScope)
            }
            if provider == nil || syncEnabled, let fraction = locator.locations.totalProgression {
                OfflinePlaybackProgressStore.shared.checkpoint(
                    itemID: itemID, positionTicks: JellyfinBookProgress.ticks(forFraction: fraction), scope: accountScope, writerToken: progressWriterToken, item: item
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
            // The session-owned checkpoint synchronizer validates identity and account
            // before every remote write. Readers only persist local positions.
            pendingFraction = nil
            progressStore.flush()
        }

        func go(to link: ReadiumShared.Link) {
            guard let navigator, let publication, owns(generation: navigatorIdentity), chapterRequest == nil else { return }
            let generation = navigatorIdentity
            let requestID = UUID()
            let href = BookReportingContainer.canonical(link.url())
            let timeout = chapterTimeout
            let deadline = ContinuousClock.now + timeout
            let navigate = navigate
            chapterRequest = (requestID, href)
            actionOutcome = .pending
            navigationDeadlineTask = Task { [weak self] in
                do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
                guard let self, owns(generation: generation), chapterRequest?.id == requestID else { return }
                resourceFailed(GusError.timeout, href: href.string)
            }
            navigationTask = Task { [weak self, weak navigator] in
                guard self?.owns(generation: generation) == true,
                      self?.chapterRequest?.id == requestID, !Task.isCancelled,
                      ContinuousClock.now < deadline else { return }
                do {
                    // Check the actual target before a native transition can replace
                    // the last readable page. Do not read an entire chapter here.
                    guard let resource = publication.get(link) else { throw GusError.notFound }
                    _ = try await resource.read(range: 0 ..< 1).get()
                    guard self?.owns(generation: generation) == true,
                          self?.chapterRequest?.id == requestID, !Task.isCancelled,
                          ContinuousClock.now < deadline, let navigator else { return }
                    let moved = await navigate(navigator, link)
                    guard let self, owns(generation: generation), chapterRequest?.id == requestID,
                          !Task.isCancelled, ContinuousClock.now < deadline else { return }
                    if moved {
                        actionOutcome = .accepted // Only a matching location confirms readiness.
                    } else {
                        resourceFailed(GusError.notFound, href: href.string)
                    }
                } catch {
                    guard let self, owns(generation: generation), chapterRequest?.id == requestID else { return }
                    resourceFailed(error, href: href.string)
                }
            }
        }
    }

    private enum BookPublicationOpenResult {
        case loaded(Publication, [ReadiumShared.Link], Locator?)
        case failed(String)
    }

    private struct EPUBNavigatorRepresentable: UIViewControllerRepresentable {
        let model: BookReaderModel
        let generation: UUID

        func makeUIViewController(context: Context) -> UIViewController {
            guard model.owns(generation: generation) else { return UIViewController() }
            guard let publication = model.publication,
                  let navigator = try? EPUBNavigatorViewController(
                      publication: publication,
                      initialLocation: model.initialLocation,
                      config: EPUBNavigatorViewController.Configuration()
                  )
            else {
                Task { @MainActor in
                    guard model.owns(generation: generation) else { return }
                    model.navigatorConstructionFailed()
                }
                return UIHostingController(rootView: ContentUnavailableView("Can't Open This Book", systemImage: "book.closed", description: Text("The book reader could not be created. Try again.")))
            }
            navigator.delegate = context.coordinator
            context.coordinator.bindInput(to: navigator)
            model.navigator = navigator
            return navigator
        }

        func updateUIViewController(_: UIViewController, context _: Context) {}

        static func dismantleUIViewController(_ controller: UIViewController, coordinator _: Coordinator) {
            (controller as? EPUBNavigatorViewController)?.delegate = nil
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(model: model, generation: generation)
        }

        @MainActor final class Coordinator: NSObject, EPUBNavigatorDelegate {
            private weak var model: BookReaderModel?
            private let generation: UUID
            private let directionalNavigation = DirectionalNavigationAdapter()

            init(model: BookReaderModel, generation: UUID) {
                self.model = model
                self.generation = generation
            }

            func bindInput(to navigator: EPUBNavigatorViewController) {
                directionalNavigation.bind(to: navigator)
            }

            func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
                MainActor.assumeIsolated {
                    guard let model, model.accepts(navigator, generation: generation) else { return }
                    model.saveLocation(locator)
                }
            }

            func navigator(_ navigator: Navigator, presentError _: NavigatorError) {
                MainActor.assumeIsolated {
                    guard let model, model.accepts(navigator, generation: generation) else { return }
                    model.copyingForbidden()
                }
            }

            func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError) {
                MainActor.assumeIsolated {
                    guard let model, model.accepts(navigator, generation: generation) else { return }
                    model.resourceFailed(error, href: href.string)
                }
            }
        }
    }
#endif
