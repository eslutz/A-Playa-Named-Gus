import SwiftUI

extension View {
    @ViewBuilder func gusTVDetailHero<Controls: View>(item: MediaItem, backdropURL: URL?, @ViewBuilder controls: @escaping () -> Controls) -> some View {
        #if os(tvOS)
            TVDetailHero(item: item, backdropURL: backdropURL, controls: controls)
        #else
            self
        #endif
    }
}

#if os(tvOS)
    /// Independent TV composition; AVKit playback and shared detail actions remain native.
    private struct TVDetailHero<Controls: View>: View {
        @Environment(SessionStore.self) private var session
        let item: MediaItem
        let backdropURL: URL?
        @ViewBuilder let controls: () -> Controls
        @State private var showingOverview = false

        private var artworkAspectRatio: CGFloat {
            switch item.type {
            case .musicAlbum, .musicArtist, .audio, .audioBook: 1
            case .photo, .photoAlbum: 4.0 / 3.0
            default: 2.0 / 3.0
            }
        }

        var body: some View {
            HStack(alignment: .top, spacing: 64) {
                AsyncPoster(
                    url: session.mediaProvider.primaryImageURL(for: item, context: .posterGrid),
                    placeholderSymbol: item.artworkPlaceholderSymbol,
                    fallbackURLs: session.mediaProvider.artworkURLs(for: item, maxWidth: 1280)
                )
                .aspectRatio(artworkAspectRatio, contentMode: .fit)
                .frame(width: 360)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 28) {
                    Text(item.displayTitle).font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    HeroMetadataRow(item: item, foreground: .secondary)
                    controls().focusSection()
                    if let overview = item.overview?.trimmedNilIfEmpty {
                        Button { showingOverview = true } label: {
                            Text(overview).font(.body).lineLimit(3).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityLabel("Synopsis")
                        .accessibilityHint("Read the full description")
                        .gusTVDetailActionFocus(id: "synopsis", item: item)
                        .focusSection()
                    }
                }
                .frame(maxWidth: 1100, alignment: .leading)
            }
            .padding(64)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: $showingOverview) {
                NavigationStack {
                    ScrollView {
                        Text(item.overview ?? "").font(.title3).padding(64)
                            .frame(maxWidth: 1200, alignment: .leading)
                    }
                    .focusable()
                    .navigationTitle(item.displayTitle)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingOverview = false } } }
                }
            }
        }
    }
#endif
