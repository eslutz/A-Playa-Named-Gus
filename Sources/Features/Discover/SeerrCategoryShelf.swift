import Observation
import SwiftUI

@MainActor @Observable
final class SeerrCategoryDirectory {
    let kind: SeerrCategoryKind
    private(set) var categories: [SeerrCategory] = []
    private(set) var state: LoadState = .idle
    private(set) var errorMessage: String?
    private(set) var revision: UUID?
    private var generation = UUID()

    init(kind: SeerrCategoryKind) {
        self.kind = kind
    }

    func load(store: SeerrStore, refresh: Bool = false) async {
        let expected = store.revision
        if revision != expected {
            categories = []
            state = .idle
            revision = expected
        }
        if !refresh, state == .loaded || state == .loading {
            return
        }
        let operation = UUID()
        generation = operation
        state = .loading
        errorMessage = nil
        defer {
            if generation == operation, Task.isCancelled {
                state = categories.isEmpty ? .idle : .loaded
            }
        }
        do {
            let values = try await store.requireClient().categories(kind)
            guard !Task.isCancelled, generation == operation, store.revision == expected else { return }
            var seen: Set<Int> = []
            categories = values.filter { $0.id > 0 && seen.insert($0.id).inserted }
            state = .loaded
        } catch {
            guard !Task.isCancelled, generation == operation, store.revision == expected else { return }
            store.handle(error)
            guard store.revision == expected else { return }
            state = categories.isEmpty ? .failed(error.localizedDescription) : .loaded
            errorMessage = error.localizedDescription
        }
    }
}

struct SeerrCategoryShelf: View {
    let directory: SeerrCategoryDirectory
    let store: SeerrStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(directory.kind.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                if directory.kind.isGenre {
                    NavigationLink("See All", value: store.navigationRoute(.categories(.init(store: directory))))
                        .accessibilityIdentifier("Seerr.feed.\(directory.kind.rawValue).showAll")
                }
            }
            .tvFocusSection()

            if directory.revision == store.revision, !directory.categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: MediaRailMetrics.spacing(for: .backdrop)) {
                        ForEach(directory.categories) { category in
                            SeerrCategoryLink(category: category, kind: directory.kind, store: store)
                                .frame(width: MediaRailMetrics.itemWidth(for: .backdrop))
                        }
                    }
                    .padding(.vertical, 8)
                }
                .lookToScroll(.horizontal)
                .gusTVRailViewport()
            } else if directory.state == .loaded {
                Text("No categories in this feed").foregroundStyle(.secondary)
            } else if directory.errorMessage == nil {
                ProgressView("Loading categories")
            }

            if let error = directory.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                Button("Retry Shelf") { Task { await directory.load(store: store, refresh: true) } }
            }
        }
    }
}

struct SeerrCategoryGrid: View {
    let directory: SeerrCategoryDirectory
    let store: SeerrStore

    var body: some View {
        LoadingStateView(
            state: directory.revision == store.revision ? directory.state : .loading,
            isEmpty: directory.categories.isEmpty,
            emptyTitle: String(localized: "No categories in this feed"),
            emptySymbol: "rectangle.stack",
            retryAction: { Task { await directory.load(store: store, refresh: true) } }
        ) {
            ScrollView {
                LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: 24) {
                    ForEach(directory.categories) { category in
                        SeerrCategoryLink(category: category, kind: directory.kind, store: store)
                    }
                }
                .padding()
                .frame(maxWidth: PageContentMetrics.maxWidth)
                .frame(maxWidth: .infinity)
            }
            .lookToScroll()
        }
        .navigationTitle(directory.kind.title)
        .task(id: store.revision) { await directory.load(store: store) }
        .refreshable { await directory.load(store: store, refresh: true) }
    }
}

private struct SeerrCategoryLink: View {
    let category: SeerrCategory
    let kind: SeerrCategoryKind
    let store: SeerrStore
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue

    var body: some View {
        NavigationLink(value: store.navigationRoute(.catalog(name: category.name, source: .category(kind, category.id)))) {
            VStack(alignment: .leading, spacing: 6) {
                // Seerr's genre backdrops have no associated title IDs or ratings.
                let backdrop = contentLimitRawValue == ContentRatingGate.Limit.off.rawValue ? category.backdrops?.first : nil
                ArtworkTile(
                    url: SeerrArtwork.url(path: category.logoPath, width: "w500") ?? SeerrArtwork.url(path: backdrop, width: "w780"),
                    aspectRatio: 16.0 / 9.0,
                    contentMode: kind.isGenre ? .fill : .fit,
                    placeholderSymbol: kind.isGenre ? "theatermasks" : "building.2"
                )
                .padding(kind.isGenre ? 0 : 12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
                Text(category.name).font(.headline).fixedSize(horizontal: false, vertical: true)
            }
        }
        .posterNavigationStyle()
        .accessibilityLabel(category.name)
        .accessibilityIdentifier("Seerr.category.\(kind.rawValue).\(category.id)")
    }
}

private extension SeerrCategoryKind {
    var title: String {
        switch self {
        case .movieGenres: String(localized: "Movie Genres")
        case .studios: String(localized: "Studios")
        case .tvGenres: String(localized: "TV Genres")
        case .networks: String(localized: "Networks")
        }
    }
}
