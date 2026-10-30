import Observation
import SwiftUI

enum SeerrCatalogSource: Hashable {
    case feed(SeerrDiscoveryFeed)
    case search(String)
    case recommendations(SeerrMediaType, Int)
}

struct SeerrCatalogFilters: Equatable {
    var mediaType = "all"
    var language = ""

    var requestedMediaType: SeerrMediaType? {
        SeerrMediaType(rawValue: mediaType)
    }

    var requestedLanguage: String? {
        language.isEmpty ? Locale.preferredLanguages.first : language
    }
}

/// A query retains its previous pages if a later page fails and rejects stale account replies.
@MainActor @Observable
final class SeerrCatalogStore {
    let source: SeerrCatalogSource
    private(set) var items: [SeerrTitle] = []
    private(set) var state: LoadState = .idle
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var errorMessage: String?
    private(set) var failedPage: Int?
    private(set) var filters = SeerrCatalogFilters()
    private var nextPage = 1
    private var connectionRevision: UUID?
    private var generation = UUID()
    private var restrictionRevision: String?

    init(source: SeerrCatalogSource) {
        self.source = source
    }

    func isValid(for store: SeerrStore) -> Bool {
        connectionRevision == store.revision && restrictionRevision == store.restrictionRevision
    }

    var supportsFilters: Bool {
        if case .feed = source {
            return true
        }
        return false
    }

    var supportsMediaTypeFilter: Bool {
        if case .feed(.trending) = source {
            return true
        }
        return false
    }

    func applyFilters(_ filters: SeerrCatalogFilters, store: SeerrStore) async {
        guard supportsFilters else { return }
        self.filters = filters
        items = []
        hasMore = false
        nextPage = 1
        await load(store: store, refresh: true)
    }

    func load(store: SeerrStore, refresh: Bool = false) async {
        if connectionRevision != store.revision || restrictionRevision != String(describing: store.restrictionRevision) {
            items = []
            state = .idle
            connectionRevision = store.revision
            restrictionRevision = String(describing: store.restrictionRevision)
        }
        guard refresh || state == .idle || isFailed else { return }
        generation = UUID()
        let operation = generation
        let revision = store.revision
        state = .loading
        errorMessage = nil
        failedPage = nil
        isLoadingMore = false
        defer {
            if generation == operation, Task.isCancelled {
                state = items.isEmpty ? .idle : .loaded
            }
        }
        do {
            let page = try await fetch(client: store.requireClient(), page: 1)
            let admitted = try await store.admitted(page.results)
            guard isCurrent(operation, revision: revision, store: store) else { return }
            items = unique(admitted)
            nextPage = page.page + 1
            hasMore = page.page < page.totalPages
            state = .loaded
        } catch {
            guard isCurrent(operation, revision: revision, store: store) else { return }
            store.handle(error)
            guard store.revision == revision else { return }
            state = items.isEmpty ? .failed(error.localizedDescription) : .loaded
            errorMessage = error.localizedDescription
            failedPage = 1
        }
    }

    func loadMore(store: SeerrStore) async {
        guard hasMore, !isLoadingMore, state != .loading else { return }
        let operation = generation
        let revision = store.revision
        guard revision == connectionRevision else { return }
        isLoadingMore = true
        errorMessage = nil
        failedPage = nil
        defer {
            if generation == operation {
                isLoadingMore = false
            }
        }
        do {
            let page = try await fetch(client: store.requireClient(), page: nextPage)
            let admitted = try await store.admitted(page.results)
            guard isCurrent(operation, revision: revision, store: store) else { return }
            items = unique(items + admitted)
            nextPage = page.page + 1
            hasMore = page.page < page.totalPages
            isLoadingMore = false
        } catch {
            guard isCurrent(operation, revision: revision, store: store) else { return }
            store.handle(error)
            guard store.revision == revision else { return }
            errorMessage = error.localizedDescription
            failedPage = nextPage
            isLoadingMore = false
        }
    }

    private var isFailed: Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    private func fetch(client: SeerrClient, page: Int) async throws -> SeerrPage {
        switch source {
        case let .feed(feed):
            try await client.browse(feed, page: page, mediaType: filters.requestedMediaType, language: filters.requestedLanguage)
        case let .search(query): try await client.search(query: query, page: page)
        case let .recommendations(type, id): try await client.recommendations(mediaType: type, id: id, page: page)
        }
    }

    private func isCurrent(_ operation: UUID, revision: UUID, store: SeerrStore) -> Bool {
        !Task.isCancelled && generation == operation && store.revision == revision
            && restrictionRevision == String(describing: store.restrictionRevision)
    }

    private func unique(_ values: [SeerrTitle]) -> [SeerrTitle] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.seerrCatalogID).inserted }
    }
}

struct SeerrCatalogGridView: View {
    let title: String
    let store: SeerrStore
    @State private var catalog: SeerrCatalogStore
    @State private var showingFilters = false
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnratedContent = false

    init(title: String, source: SeerrCatalogSource, store: SeerrStore) {
        self.title = title
        self.store = store
        _catalog = State(initialValue: SeerrCatalogStore(source: source))
    }

    var body: some View {
        SeerrCatalogResults(catalog: catalog, store: store, toolbarTitle: title, filtersAction: catalog.supportsFilters ? { showingFilters = true } : nil)
            .navigationTitle(title)
            .task(id: "\(store.revision):\(contentLimitRawValue):\(hideUnratedContent)") { await catalog.load(store: store) }
            .refreshable { await catalog.load(store: store, refresh: true) }
            .toolbar {
                #if !os(tvOS)
                    if catalog.supportsFilters {
                        ToolbarItem(placement: .primaryAction) {
                            Button { showingFilters = true } label: { GusToolbarLabel("Filters", systemImage: "line.3.horizontal.decrease") }
                                .gusIPadIconOnly().accessibilityLabel("Filters")
                        }
                    }
                #endif
            }
            .sheet(isPresented: $showingFilters) {
                SeerrCatalogFilterView(catalog: catalog, store: store)
            }
    }
}

/// Picker edits remain a draft until Apply; dismissing the sheet leaves results intact.
private struct SeerrCatalogFilterView: View {
    let catalog: SeerrCatalogStore
    let store: SeerrStore
    private let revision: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SeerrCatalogFilters
    @State private var languages: [SeerrLanguage] = []
    @State private var languageError: String?
    @State private var loadingLanguages = false

    init(catalog: SeerrCatalogStore, store: SeerrStore) {
        self.catalog = catalog
        self.store = store
        revision = store.revision
        _draft = State(initialValue: catalog.filters)
    }

    var body: some View {
        NavigationStack {
            Form {
                if catalog.supportsMediaTypeFilter {
                    Picker("Media Type", selection: $draft.mediaType) {
                        Text("All").tag("all")
                        Text("Movies").tag("movie")
                        Text("TV Series").tag("tv")
                    }
                }
                Picker("Metadata Language", selection: $draft.language) {
                    Text("System").tag("")
                    ForEach(languages) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                if loadingLanguages {
                    ProgressView("Loading languages")
                } else if let languageError {
                    Text(languageError).foregroundStyle(.secondary)
                    Button("Retry Languages") { Task { await loadLanguages() } }
                }
                Text("Metadata language changes title information. Original-language and other filters are available only where Seerr supports them.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Reset Filters") { draft = SeerrCatalogFilters() }
            }
            .navigationTitle("Filters")
            .task(id: store.revision) { await loadLanguages() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        let filters = draft
                        dismiss()
                        Task {
                            guard store.revision == revision else { return }
                            await catalog.applyFilters(filters, store: store)
                        }
                    }
                }
            }
        }
    }

    @MainActor private func loadLanguages() async {
        loadingLanguages = true
        defer { loadingLanguages = false }
        do {
            let result = try await store.requireClient().languages()
            guard !Task.isCancelled, store.revision == revision else { return }
            languages = result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            languageError = nil
        } catch {
            guard !Task.isCancelled, store.revision == revision else { return }
            store.handle(error)
            languageError = error.localizedDescription
        }
    }
}

/// Search and See All share presentation, pagination and native Grid/List controls.
struct SeerrCatalogResults: View {
    let catalog: SeerrCatalogStore
    let store: SeerrStore
    var toolbarTitle: String? = nil
    var filtersAction: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnratedContent = false
    @State private var usesList = false
    @State private var scrollID: String?

    private var listPresentation: Bool {
        usesList || dynamicTypeSize.isAccessibilitySize
    }

    private var visibleItems: [SeerrTitle] {
        _ = contentLimitRawValue
        _ = hideUnratedContent
        guard catalog.isValid(for: store) else { return [] }
        return catalog.items.filter { store.admits($0) }
    }

    var body: some View {
        #if os(tvOS)
            if let toolbarTitle {
                VStack(spacing: 24) {
                    HStack {
                        Text(toolbarTitle).font(.largeTitle.bold())
                        Spacer()
                        viewMenu
                        if let filtersAction {
                            Button(action: filtersAction) { GusToolbarLabel("Filters", systemImage: "line.3.horizontal.decrease") }
                                .accessibilityLabel("Filters")
                        }
                    }
                    .focusSection()
                    .padding(.horizontal)
                    results
                }
                .gusTVDetailTitle()
            } else {
                results
            }
        #else
            results
        #endif
    }

    private var results: some View {
        LoadingStateView(
            state: catalog.isValid(for: store) ? (visibleItems.isEmpty ? catalog.state : .loaded) : .loading,
            isEmpty: visibleItems.isEmpty && !catalog.hasMore,
            emptyTitle: String(localized: "No Results"),
            emptySymbol: "magnifyingglass",
            retryAction: { Task { await catalog.load(store: store, refresh: true) } }
        ) {
            ScrollView {
                VStack(spacing: 24) {
                    if visibleItems.isEmpty, catalog.state == .loaded {
                        Text("No matching titles on this page").foregroundStyle(.secondary)
                    }
                    if catalog.state == .loading {
                        ProgressView("Updating results")
                    }
                    if listPresentation {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(visibleItems, id: \.seerrCatalogID) { item in
                                SeerrResultLink(title: item, store: store, usesList: true).id(item.seerrCatalogID)
                                Divider()
                            }
                        }
                        .scrollTargetLayout()
                    } else {
                        LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: 24) {
                            ForEach(visibleItems, id: \.seerrCatalogID) { item in
                                SeerrResultLink(title: item, store: store).id(item.seerrCatalogID)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    pagination
                }
                .padding()
                .frame(maxWidth: PageContentMetrics.maxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $scrollID)
            .lookToScroll()
        }
        .toolbar {
            #if os(tvOS)
                if toolbarTitle == nil {
                    ToolbarItem(placement: .seerrSecondaryAction) { viewMenu }
                }
            #else
                ToolbarItem(placement: .seerrSecondaryAction) { viewMenu }
            #endif
        }
        .onChange(of: store.revision) { _, _ in scrollID = nil }
    }

    private var viewMenu: some View {
        Menu {
            Picker("View", selection: $usesList) {
                Label("Grid", systemImage: "square.grid.2x2").tag(false)
                Label("List", systemImage: "list.bullet").tag(true)
            }
        } label: { GusToolbarLabel("View", systemImage: usesList ? "list.bullet" : "square.grid.2x2") }
            .accessibilityLabel("View")
            .accessibilityValue(usesList ? "List" : "Grid")
    }

    @ViewBuilder private var pagination: some View {
        if let error = catalog.errorMessage {
            VStack(spacing: 8) {
                Text(error).foregroundStyle(.secondary)
                Button(catalog.failedPage.map { $0 > 1 } == true ? "Retry Page" : "Try Again") {
                    Task {
                        if catalog.failedPage.map({ $0 > 1 }) == true {
                            await catalog.loadMore(store: store)
                        } else {
                            await catalog.load(store: store, refresh: true)
                        }
                    }
                }
            }
        } else if catalog.isLoadingMore {
            ProgressView("Loading more results")
        } else if catalog.hasMore {
            Button("Load More") { Task { await catalog.loadMore(store: store) } }
        }
    }
}
