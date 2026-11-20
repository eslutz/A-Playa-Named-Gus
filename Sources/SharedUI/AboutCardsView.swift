import SwiftUI

/// Full-width synopsis and adaptive, roomy metadata cards.
struct AboutCardsView: View {
    @Environment(SessionStore.self) private var session
    let item: MediaItem
    let posterURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 24) {
                if let overview = item.overview?.trimmedNilIfEmpty {
                    DetailInfoCard(title: "Synopsis") {
                        DetailSynopsis(title: item.displayTitle, overview: overview, moreIdentifier: "Detail.aboutFullSynopsis")
                    }
                    .tvFocusSection()
                }
                AdaptiveStack(horizontalMinimumWidth: 320 + 32 + 320, horizontalAlignment: .top, horizontalSpacing: 32, verticalSpacing: 24) { horizontal in
                    informationCards(horizontal: horizontal)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("Detail.aboutCards")
            .tvFocusSection()
        }
    }

    @ViewBuilder private func informationCards(horizontal: Bool) -> some View {
        posterSummaryCard
            .frame(minWidth: horizontal ? 320 : nil, maxWidth: .infinity, alignment: .topLeading)
            .gusTVFocusableInfo()
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
        }
        .frame(minWidth: horizontal ? 320 : nil, maxWidth: .infinity, alignment: .topLeading)
        .gusTVFocusableInfo()
    }

    private var posterSummaryCard: some View {
        DetailInfoCard(title: LocalizedStringKey(item.displayTitle)) {
            HStack(alignment: .top, spacing: 12) {
                ArtworkTile(url: posterURL, placeholderSymbol: item.artworkPlaceholderSymbol, fallbackURLs: session.mediaProvider.artworkURLs(for: item, request: .init(role: .poster, maxWidth: 360)))
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

/// Inspect the rendered preview itself so a change in width, font or locale updates the action.
struct DetailSynopsis: View {
    let title: String
    let overview: String
    var identifier = "Detail.synopsisPreview"
    var moreIdentifier = "Detail.fullSynopsis"
    var focusItem: MediaItem?
    var lines = 4
    @State private var previewHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    var body: some View {
        if let text = BookDetailMetadata.synopsis(overview) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: text)
                    .lineLimit(lines)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifier)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { previewHeight = $0 }
                    .background(alignment: .topLeading) {
                        // Compare the same text and font at this preview's actual width.
                        // Some OS 26 text layouts omit the truncation flag at paragraph breaks.
                        Text(verbatim: text)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                            .hidden()
                            .accessibilityHidden(true)
                    }
                if previewHeight > 0, fullHeight > previewHeight + 0.5 {
                    let button = FullSynopsisButton(title: title, overview: text)
                        .accessibilityIdentifier(moreIdentifier)
                    if let focusItem {
                        button.gusTVDetailActionFocus(id: "synopsis", item: focusItem)
                    } else {
                        button
                    }
                }
            }
        }
    }
}

/// Opens the same scrollable synopsis from either a book preview or an About card.
private struct FullSynopsisButton: View {
    let title: String
    let overview: String
    @State private var showsFullSynopsis = false

    var body: some View {
        Button("Show More") { showsFullSynopsis = true }
            .gusTVTask(isPresented: $showsFullSynopsis) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(title)
                                .font(.title.bold())
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("Synopsis.heading")
                            Text(overview)
                                .accessibilityIdentifier("Synopsis.body")
                        }
                        .frame(maxWidth: 1200, alignment: .leading)
                        .padding()
                    }
                    #if os(tvOS)
                    .focusable()
                    #endif
                    .navigationTitle("Synopsis")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            GusCloseButton { showsFullSynopsis = false }
                                .accessibilityIdentifier("Synopsis.done")
                        }
                    }
                }
                #if os(macOS)
                .frame(minWidth: 400, idealWidth: 520, minHeight: 320, idealHeight: 440)
                #endif
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
