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

        private var summary: some View {
            VStack(alignment: .leading, spacing: 24) {
                Text(item.displayTitle).font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let overview = item.overview?.trimmedNilIfEmpty {
                    Button { showingOverview = true } label: {
                        Text(overview).font(.body).lineLimit(3).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Synopsis")
                    .accessibilityHint("Read the full description")
                    .gusTVDetailActionFocus(id: "synopsis", item: item)
                }
                HeroMetadataRow(item: item, foreground: .white.opacity(0.8))
            }
            .foregroundStyle(.white)
        }

        var body: some View {
            Group {
                if item.type == .series || item.type == .season {
                    VStack(alignment: .leading, spacing: 28) {
                        summary
                        controls().frame(width: 440)
                    }.frame(maxWidth: 1080, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .bottom, spacing: 80) {
                        summary.frame(maxWidth: 1040, alignment: .leading)
                        Spacer(minLength: 0)
                        controls().frame(width: 440).focusSection()
                    }
                }
            }
            .padding(64)
            .frame(maxWidth: .infinity, minHeight: 700, alignment: .bottomLeading)
            .background {
                GeometryReader { geometry in
                    AsyncPoster(
                        url: backdropURL,
                        placeholderSymbol: item.artworkPlaceholderSymbol,
                        fallbackURLs: session.mediaProvider.artworkURLs(for: item, maxWidth: 1920)
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0.5), .black.opacity(0.1)], startPoint: .bottom, endPoint: .top)
                    }
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
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingOverview = false } } }
                }
            }
        }
    }
#endif
