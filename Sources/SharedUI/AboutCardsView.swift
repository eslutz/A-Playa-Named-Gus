import SwiftUI

/// Full-width synopsis and adaptive, roomy metadata cards.
struct AboutCardsView: View {
    let item: MediaItem
    let posterURL: URL?
    @State private var showsFullSynopsis = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 24) {
                if let overview = item.overview?.trimmedNilIfEmpty {
                    DetailInfoCard(title: "Synopsis") {
                        Text(overview).fixedSize(horizontal: false, vertical: true)
                        Button("Show More") { showsFullSynopsis = true }
                            .accessibilityIdentifier("Detail.fullSynopsis")
                    }
                    .tvFocusSection()
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 32) {
                        informationCards.frame(minWidth: 320, maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        informationCards
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("Detail.aboutCards")
            .tvFocusSection()
        }
        .sheet(isPresented: $showsFullSynopsis) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(item.displayTitle)
                            .font(.title.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("Synopsis.heading")
                        Text(item.overview ?? "")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .navigationTitle("Synopsis")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        GusCloseButton { showsFullSynopsis = false }
                            .accessibilityIdentifier("Synopsis.done")
                    }
                }
            }
        }
    }

    @ViewBuilder private var informationCards: some View {
        posterSummaryCard.gusTVFocusableInfo()
        DetailInfoCard(title: "Media") {
            if let runtime = item.runtimeText {
                LabeledContent("Duration", value: runtime)
            }
            if let rating = item.officialRating {
                LabeledContent("Rating", value: rating)
            }
            if let container = item.container?.trimmedNilIfEmpty {
                LabeledContent("Container", value: container.uppercased().replacingOccurrences(of: ",", with: ", "))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.gusTVFocusableInfo()
    }

    private var posterSummaryCard: some View {
        DetailInfoCard(title: LocalizedStringKey(item.displayTitle)) {
            HStack(alignment: .top, spacing: 12) {
                ArtworkTile(url: posterURL, placeholderSymbol: item.artworkPlaceholderSymbol)
                    .frame(width: AboutCardMetrics.posterSize.width, height: AboutCardMetrics.posterSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    if let tagline = item.primaryTagline {
                        Text(tagline)
                            .fixedSize(horizontal: false, vertical: true)
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

/// Intrinsically sized card with a thin-material background used in the About section.
struct DetailInfoCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            content
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
