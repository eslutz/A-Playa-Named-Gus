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

    var body: some View {
        LoadingStateView(
            state: state,
            isEmpty: siblings.isEmpty,
            emptyTitle: "No Photos",
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
        .navigationTitle(currentTitle)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem {
                    Button {
                        isSlideshowActive.toggle()
                    } label: {
                        Label(
                            isSlideshowActive ? "Pause Slideshow" : "Play Slideshow",
                            systemImage: isSlideshowActive ? "pause.fill" : "play.fill"
                        )
                    }
                    .accessibilityLabel(isSlideshowActive ? "Pause Slideshow" : "Play Slideshow")
                }
            }
            .task {
                await loadSiblings()
            }
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
            url: session.mediaProvider.primaryImageURL(for: item, maxWidth: 2048),
            contentMode: .fit,
            placeholderSymbol: "photo"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityLabel(item.displayTitle)
    }

    private func loadSiblings() async {
        guard state != .loading, siblings.isEmpty else { return }
        state = .loading
        do {
            let page = try await session.mediaProvider.items(query: MediaItemQuery(
                parentID: photo.parentID,
                startIndex: 0,
                limit: 500,
                sort: .name
            ))
            let photos = page.items.filter { $0.type == .photo }
            siblings = photos.isEmpty ? [photo] : photos
            selectedID = photo.id
            state = .loaded
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            // Fall back to showing just the opened photo rather than failing the screen.
            siblings = [photo]
            selectedID = photo.id
            state = .loaded
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
    }
}
