import SwiftUI

/// Horizontal scroll of info cards: poster + tagline, overview text, and media facts.
struct AboutCardsView: View {
    let item: MediaItem
    let posterURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    posterSummaryCard

                    if let overview = item.overview?.trimmedNilIfEmpty {
                        DetailInfoCard(title: LocalizedStringKey(item.displayTitle)) {
                            Text(overview)
                                .lineLimit(5)
                        }
                    }

                    DetailInfoCard(title: "Media") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let runtime = item.runtimeText {
                                Text(runtime)
                            }
                            if let rating = item.officialRating {
                                Text(rating)
                            }
                            if let container = item.container?.trimmedNilIfEmpty {
                                Text(container.uppercased())
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .lookToScroll(.horizontal)
        }
    }

    private var posterSummaryCard: some View {
        DetailInfoCard(title: LocalizedStringKey(item.displayTitle)) {
            HStack(alignment: .top, spacing: 12) {
                AsyncPoster(url: posterURL, contentMode: .fill, placeholderSymbol: item.type == .series ? "tv" : "film")
                    .frame(width: 74, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    if let tagline = item.primaryTagline {
                        Text(tagline)
                            .lineLimit(3)
                    }
                    if let year = item.yearText {
                        Text(year)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Info card chrome

/// Fixed-size card with a thin-material background used in the About section.
struct DetailInfoCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .lineLimit(2)
            content
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(width: AboutCardMetrics.cardWidth, height: AboutCardMetrics.cardHeight, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
