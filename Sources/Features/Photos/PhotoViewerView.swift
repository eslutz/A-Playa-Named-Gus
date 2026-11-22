import SwiftUI

/// Full-screen photo viewer: pages through the opened photo's siblings with a
/// slideshow mode. Photos render at full width via the provider's image pipeline.
struct PhotoViewerView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let photo: MediaItem

    @State private var siblings: [MediaItem] = []
    @State private var state: LoadState = .idle
    @State private var selectedID: String?
    @State private var isSlideshowActive = false
    @State private var isLoadingSiblings = false
    @State private var siblingError: String?

    init(photo: MediaItem, slideshowAlbumID: String? = nil) {
        self.photo = photo
        _isSlideshowActive = State(initialValue: slideshowAlbumID != nil && slideshowAlbumID == photo.parentID)
    }

    var body: some View {
        LoadingStateView(
            state: state,
            isEmpty: siblings.isEmpty,
            emptyTitle: String(localized: "No Photos", comment: "Photo viewer empty-state title when no photos are available"),
            emptySymbol: "photo"
        ) {
            TabView(selection: $selectedID) {
                ForEach(siblings, id: \.id) { item in
                    photoPage(for: item)
                        .tag(item.id)
                }
            }
            #if os(iOS) || os(tvOS) || os(visionOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .ignoresSafeArea(edges: .bottom)
        }
        #if os(tvOS)
        .navigationTitle("")
        #else
        .navigationTitle(currentTitle)
        #endif
        .gusTVPhotoHeading(title: currentTitle, position: (siblings.firstIndex(where: { $0.id == selectedID }) ?? 0) + 1, total: siblings.count)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem {
                    Button {
                        isSlideshowActive.toggle()
                    } label: {
                        GusToolbarLabel(
                            isSlideshowActive ? "Pause Slideshow" : "Play Slideshow",
                            systemImage: isSlideshowActive ? "pause.fill" : "play.fill"
                        )
                    }
                    .gusIPadIconOnly()
                    .gusTVToolbarIcon()
                    .accessibilityLabel(isSlideshowActive ? "Pause Slideshow" : "Play Slideshow")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isLoadingSiblings {
                    ProgressView().accessibilityLabel("Loading Photos")
                }
                if let siblingError {
                    VStack(spacing: 8) {
                        Text(siblingError).foregroundStyle(.secondary)
                        Button("Try Again") { Task { await loadSiblings() } }
                    }.padding().background(.regularMaterial)
                }
            }
            .task { await loadSiblings() }
            .task(id: isSlideshowActive) {
                guard isSlideshowActive else { return }
                await runSlideshow()
            }
    }

    private var currentTitle: String {
        siblings.first { $0.id == selectedID }?.displayTitle ?? photo.displayTitle
    }

    private func photoPage(for item: MediaItem) -> some View {
        AsyncPoster(
            url: session.mediaProvider.artworkURLs(for: item, request: .init(role: .photo, maxWidth: 2048)).first,
            contentMode: .fit,
            placeholderSymbol: "photo"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityLabel(item.mediaAccessibility.label)
        .accessibilityValue(item.mediaAccessibility.value)
    }

    private func loadSiblings() async {
        guard !isLoadingSiblings else { return }
        isLoadingSiblings = true
        siblingError = nil
        if siblings.isEmpty {
            siblings = [photo]
            selectedID = photo.id
            state = .loaded
        }
        defer { isLoadingSiblings = false }
        guard let parent = photo.parentID else { return }
        do {
            _ = try await MediaPageLoader.collect(pageSize: 200, didLoadPage: { loaded in
                let selected = siblings.first { $0.id == selectedID }
                var visible = PhotoSelection.includingOpened(photo, in: ContentRatingGate.filter(loaded))
                if let selected, selected.id != photo.id {
                    visible = PhotoSelection.includingOpened(selected, in: visible)
                }
                siblings = visible
                state = .loaded
            }) { offset, limit in
                guard session.isActive else { throw CancellationError() }
                let page = try await session.mediaProvider.items(query: MediaItemQuery(parentID: parent, includeTypes: [.photo], startIndex: offset, limit: limit, sort: .name))
                try Task.checkCancellation()
                guard session.isActive else { throw CancellationError() }
                return page
            }
        } catch {
            let failure = GusError(from: error)
            guard !failure.isCancellation, session.isActive else { return }
            siblingError = failure.localizedDescription
        }
    }

    private func runSlideshow() async {
        while isSlideshowActive, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            guard isSlideshowActive, !Task.isCancelled else { return }
            advance()
        }
    }

    private func advance() {
        guard !siblings.isEmpty else { return }
        guard let current = siblings.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = siblings.first?.id
            return
        }
        let next = (current + 1) % siblings.count
        if reduceMotion {
            selectedID = siblings[next].id
        } else {
            withAnimation {
                selectedID = siblings[next].id
            }
        }
        // The slideshow changes content without user interaction; tell VoiceOver.
        AccessibilityNotification.Announcement(siblings[next].displayTitle).post()
    }
}

/// Preserve the item that opened the gallery even when it is outside the sibling page.
enum PhotoSelection {
    static func includingOpened(_ photo: MediaItem, in siblings: [MediaItem]) -> [MediaItem] {
        let ordered = MediaPageLoader.unique(siblings).filter { $0.id != nil }
        if ordered.contains(where: { $0.id == photo.id && $0.providerKind == photo.providerKind }) {
            return ordered
        }
        return MediaPageLoader.unique([photo] + ordered).filter { $0.id != nil }
    }
}
