import SwiftUI

/// Tapping a credit pushes the titles for that server entity.
struct DetailMetadataRows: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: DetailPageMetrics.sectionSpacing) {
            if !item.genreSearchTargets.isEmpty {
                MetadataPillRow(title: "Genres", values: item.genreSearchTargets, identifier: "Detail.metadataGenres", item: item)
            }
            if !item.isBookFormat, !item.studioSearchTargets.isEmpty {
                MetadataPillRow(title: "Studios", values: item.studioSearchTargets, identifier: "Detail.metadataStudios", item: item)
            }
        }
    }
}

private struct MetadataPillRow: View {
    @Environment(RootNavigationState.self) private var navigation
    @Environment(\.detailScrollViewport) private var viewport
    let title: LocalizedStringKey
    let values: [RelatedSearch]
    let identifier: String
    let item: MediaItem

    var body: some View {
        let context = "detail:" + ItemRef(item: item).id
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(values, id: \.identityKey) { target in
                        Button(target.name) {
                            navigation.openRelatedSearch(target, viewport: viewport?.location)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityHint("Search for related titles")
                        .accessibilityIdentifier("Detail.related." + target.identityKey)
                        .gusTVFocus(id: target.identityKey, section: context + ":" + identifier, ids: values.map(\.identityKey), context: context)
                    }
                }
                .padding(.vertical, 2)
                .gusTVRailPadding()
            }
            .lookToScroll(.horizontal)
            .gusTVRailViewport()
        }
    }
}
