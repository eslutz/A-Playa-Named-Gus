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

        var body: some View {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    if item.type == .episode, let seriesName = item.seriesName?.trimmedNilIfEmpty {
                        Text(seriesName)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text(item.displayTitle)
                        .font(.largeTitle.bold())
                        .lineLimit(2)
                        .frame(maxWidth: 1200, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 300)
                HStack(alignment: .top, spacing: 56) {
                    controls()
                        .frame(width: 528, alignment: .leading)
                        .focusSection()
                    VStack(alignment: .leading, spacing: 20) {
                        if let overview = item.overview?.trimmedNilIfEmpty {
                            Button { showingOverview = true } label: {
                                Text(overview)
                                    .font(.body)
                                    .lineLimit(4)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Synopsis")
                            .accessibilityHint("Read the full description")
                            .accessibilityIdentifier("Detail.heroOverview")
                            .gusTVDetailActionFocus(id: "synopsis", item: item)
                        }
                        HeroMetadataRow(item: item, foreground: .white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusSection()
                }
            }
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 80)
            .padding(.top, 64)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, minHeight: 940, alignment: .bottomLeading)
            .background {
                GeometryReader { geometry in
                    AsyncPoster(url: backdropURL, placeholderSymbol: item.artworkPlaceholderSymbol, fallbackURLs: session.mediaProvider.artworkURLs(for: item, maxWidth: 1920))
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .overlay {
                            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
                        }
                        .overlay {
                            LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.75), location: 0.7), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
                        }
                        .accessibilityHidden(true)
                }
                .accessibilityHidden(true)
            }
            .gusTVTask(isPresented: $showingOverview) {
                NavigationStack {
                    ScrollView {
                        Text(item.overview ?? "").font(.title3).padding(64)
                            .frame(maxWidth: 1200, alignment: .leading)
                    }
                    .focusable()
                    .navigationTitle(item.displayTitle)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { GusCloseButton { showingOverview = false } } }
                }
            }
        }
    }
#endif
