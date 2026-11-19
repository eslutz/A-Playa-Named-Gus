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

        var body: some View {
            VStack(alignment: .leading, spacing: 32) {
                Spacer(minLength: 300)
                VStack(alignment: .leading, spacing: 8) {
                    if item.type == .episode, let seriesName = item.seriesName?.trimmedNilIfEmpty {
                        Text(seriesName)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(item.displayTitle)
                        .font(.largeTitle.bold())
                        .lineLimit(2)
                        .frame(maxWidth: 1200, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                }
                HStack(alignment: .top, spacing: 56) {
                    controls()
                        .frame(minWidth: 528, alignment: .leading)
                        .focusSection()
                    VStack(alignment: .leading, spacing: 20) {
                        if let overview = item.overview?.trimmedNilIfEmpty {
                            DetailSynopsis(title: item.displayTitle, overview: overview, identifier: "Detail.heroOverview", focusItem: item)
                        }
                        HeroMetadataRow(item: item, foreground: .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusSection()
                }
            }
            .padding(.horizontal, 80)
            .padding(.top, 64)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, minHeight: 940, alignment: .bottomLeading)
            .background {
                GeometryReader { geometry in
                    AsyncPoster(url: backdropURL, placeholderSymbol: item.artworkPlaceholderSymbol, fallbackURLs: session.mediaProvider.artworkURLs(for: item, request: .init(role: item.type == .episode ? .episodeStill : .backdrop, maxWidth: 1920)))
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .mask {
                            LinearGradient(stops: [.init(color: .black, location: 0.28), .init(color: .black.opacity(0.2), location: 0.65), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                        }
                        .accessibilityHidden(true)
                }
                .accessibilityHidden(true)
            }
        }
    }
#endif
