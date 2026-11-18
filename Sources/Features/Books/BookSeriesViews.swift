import SwiftUI

struct BookSeriesRef: Hashable {
    let account: AccountScope
    let library: LibraryGridScope
    let key: BookSeriesKey
    let name: String
}

/// A series replaces its member cards in the ordinary library order. Individual
/// titles retain the usual navigation link, artwork, actions, and spoken status.
struct BookShelfView: View {
    @Environment(SessionStore.self) private var session
    let store: LibraryStore
    let showsList: Bool

    var body: some View {
        if showsList {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(store.bookEntries) { entry in
                    link(entry).buttonStyle(.plain)
                    Divider()
                }
            }
            .scrollTargetLayout()
        } else {
            let ids = store.bookEntries.map(\.id)
            LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: PosterGrid.spacing) {
                ForEach(store.bookEntries) { entry in
                    link(entry)
                        .posterNavigationStyle()
                        .gusTVFocus(id: entry.id, section: "library:" + store.scope.storeIdentity, ids: ids, initial: entry.id == ids.first)
                }
            }
            .scrollTargetLayout()
            .tvFocusSection()
        }
    }

    @ViewBuilder private func link(_ entry: BookShelfEntry) -> some View {
        switch entry {
        case let .title(item):
            MediaItemNavigationLink(item: item) {
                if showsList {
                    MediaLibraryRow(item: item)
                } else {
                    PosterCard(item: item, imageURL: session.mediaProvider.primaryImageURL(for: item, context: .posterGrid), fallbackURLs: session.mediaProvider.artworkURLs(for: item, request: .init(role: .poster, maxWidth: 360)))
                }
            }
            .mediaItemContextMenu(item: item)
        case let .series(series):
            NavigationLink(value: BookSeriesRef(account: session.references.scope, library: store.scope, key: series.id, name: series.name)) {
                BookSeriesLabel(series: series, showsList: showsList, complete: store.hasCompleteBookCatalog)
            }
        }
    }
}

private struct BookSeriesLabel: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var limit = ContentRatingGate.Limit.off
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false
    let series: BookSeries
    let showsList: Bool
    let complete: Bool

    private var subtitle: String {
        guard complete else { return String(localized: "Series") }
        let count = series.members.count
        if series.id.format == .audioBook {
            return count == 1 ? String(localized: "Series · 1 audiobook") : String(localized: "Series · \(count) audiobooks")
        }
        return count == 1 ? String(localized: "Series · 1 book") : String(localized: "Series · \(count) books")
    }

    var body: some View {
        Group {
            if showsList {
                HStack(spacing: 16) {
                    covers.frame(width: 44)
                    caption
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    covers
                    caption
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(series.name)
        .accessibilityValue(subtitle)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(series.name).font(showsList ? .body.weight(.medium) : .subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var covers: some View {
        let aspect: CGFloat = series.id.format == .audioBook ? 1 : 2.0 / 3.0
        let books = ContentRatingGate.coverMembers(series.members, limit: limit, hideUnrated: hideUnrated, count: 3)
        return Color.clear.aspectRatio(aspect, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let step = geometry.size.width * 0.055
                    let inset = CGFloat(max(0, books.count - 1)) * step
                    ForEach(books.indices.reversed(), id: \.self) { index in
                        let item = books[index]
                        let urls = session.mediaProvider.artworkURLs(for: item, request: .init(role: item.coverArtworkRole, maxWidth: showsList ? 144 : 360))
                        ArtworkTile(url: urls.first, aspectRatio: aspect, placeholderSymbol: "book", fallbackURLs: Array(urls.dropFirst()))
                            .clipShape(RoundedRectangle(cornerRadius: showsList ? 4 : 8))
                            .frame(width: max(0, geometry.size.width - inset))
                            .offset(x: CGFloat(index) * step, y: CGFloat(books.count - index - 1) * step)
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

struct BookSeriesDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(RootNavigationState.self) private var root
    @Environment(\.dismiss) private var dismiss
    let ref: BookSeriesRef
    @State private var store: LibraryStore?

    private var currentRef: BookSeriesRef {
        let name = store?.bookCatalog.series(ref.key)?.name
        return BookSeriesRef(account: ref.account, library: ref.library, key: ref.key, name: name ?? ref.name)
    }

    var body: some View {
        Group {
            if session.references.scope != ref.account {
                ContentUnavailableView("Series Unavailable", systemImage: "books.vertical")
            } else if let store {
                let members = store.bookCatalog.series(ref.key)?.members ?? []
                ScrollView {
                    VStack(alignment: .leading) {
                        if let error = store.refreshError {
                            Text(error).foregroundStyle(.secondary)
                            Button("Try Again") { Task { await store.load() } }
                        }
                        LoadingStateView(state: store.state, isEmpty: members.isEmpty, emptyTitle: "No Titles in This Series", emptySymbol: "books.vertical", retryAction: { Task { await store.load() } }) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(members, id: \.id) { item in
                                    MediaItemNavigationLink(item: item) { MediaLibraryRow(item: item) }
                                        .buttonStyle(.plain)
                                        .mediaItemContextMenu(item: item)
                                    Divider()
                                }
                            }
                        }
                    }
                    .gusTVPagePadding()
                    .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await store.load() }
                .gusVisibleContent(.library(ref.library.storeIdentity), isLoading: store.isLoading)
                .modifier(BookSeriesManagement(store: store, series: currentRef, onClose: {
                    if store.hasCompleteBookCatalog, store.bookCatalog.series(ref.key) == nil {
                        dismiss()
                    }
                }))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(currentRef.name)
        .task(id: ref) {
            guard ref.account == session.references.scope else { return }
            let library = root.libraryStore(for: ref.library, session: session)
            store = library
            if library.state == .idle {
                await library.load()
            }
        }
    }
}

/// Capture immutable membership when the editor opens, even if its underlying
/// view refreshes after a partial save or a rename removes the old stack.
struct BookSeriesManagement: ViewModifier {
    let store: LibraryStore?
    var series: BookSeriesRef?
    var onClose: () -> Void = {}
    @Environment(SessionStore.self) private var session
    @Environment(RootNavigationState.self) private var root
    @State private var canEdit = false
    @State private var draft: Draft?

    private struct Draft: Identifiable {
        let id = UUID()
        let books: [MediaItem]
        let members: [MediaItem]
        let name: String?
    }

    private var offersEditing: Bool {
        guard let store, store.hasCompleteBookCatalog, CollectionPlatform.canManage else { return false }
        if let series {
            guard series.key.format == .book, let group = store.bookCatalog.series(series.key) else { return false }
            return group.members.allSatisfy { BookSeriesKey.explicitID($0.seriesID) == nil }
        }
        return store.scope.includeTypes?.contains(.book) == true && store.bookCatalog.books.contains {
            $0.type == .book && BookSeriesKey.explicitID($0.seriesID) == nil
        }
    }

    func body(content: Content) -> some View {
        content.toolbar {
            if offersEditing, canEdit, let store {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let books = store.bookCatalog.books.filter { $0.type == .book }
                        let members = series.flatMap { store.bookCatalog.series($0.key)?.members } ?? []
                        draft = Draft(books: books, members: members, name: series?.name)
                    } label: {
                        Label(series == nil ? "New Series" : "Edit Series", systemImage: series == nil ? "plus" : "pencil")
                    }
                }
            }
        }
        .task(id: offersEditing) {
            canEdit = false
            if offersEditing {
                let supported = (try? await session.mediaProvider.canEditBookSeries()) == true
                if !Task.isCancelled, session.isActive {
                    canEdit = supported
                }
            }
        }
        .sheet(item: $draft, onDismiss: onClose) { draft in
            BookSeriesEditor(books: draft.books, members: draft.members, seriesName: draft.name) {
                if let store {
                    await root.refreshBookShelves(afterEditing: store)
                }
            }
        }
    }
}
