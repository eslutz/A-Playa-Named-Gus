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
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 180)
                VStack(alignment: .leading, spacing: 20) {
                    Text(item.displayTitle).font(.largeTitle.bold()).lineLimit(3)
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    HeroMetadataRow(item: item)
                    controls().focusSection()
                    if let overview = item.overview?.trimmedNilIfEmpty {
                        Button { showingOverview = true } label: {
                            Text(overview).font(.body).lineLimit(3).multilineTextAlignment(.leading)
                                .frame(maxWidth: 880, alignment: .leading)
                        }
                        .accessibilityLabel("Synopsis")
                        .accessibilityHint("Read the full description")
                        .gusTVFocus(id: "synopsis", section: "detail:" + ItemRef(item: item).id, ids: ["play", "more", "synopsis"], item: item)
                    }
                }
                .frame(maxWidth: 1000, alignment: .leading)
            }
            .padding(.horizontal, 64).padding(.vertical, 48)
            .frame(maxWidth: .infinity, minHeight: 720, alignment: .bottomLeading)
            .background {
                GeometryReader { geometry in
                    AsyncPoster(url: backdropURL, placeholderSymbol: item.artworkPlaceholderSymbol, fallbackURLs: session.mediaProvider.artworkURLs(for: item, maxWidth: 1920))
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .overlay {
                            LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        }
                        .overlay {
                            LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
                        }
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea(.container, edges: [.top, .horizontal])
            }
            .sheet(isPresented: $showingOverview) {
                NavigationStack {
                    ScrollView {
                        Text(item.overview ?? "").font(.title3).padding(64)
                            .frame(maxWidth: 1200, alignment: .leading)
                    }
                    .focusable()
                    .navigationTitle(item.displayTitle)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingOverview = false } } }
                }
            }
        }
    }
#endif
