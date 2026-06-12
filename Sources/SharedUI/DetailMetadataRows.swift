import SwiftUI

/// Genre and studio pill rows shown in the item detail metadata section.
struct DetailMetadataRows: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let genres = item.genres.nonEmptyStrings, !genres.isEmpty {
                MetadataPillRow(title: "Genres", values: genres)
            }

            if let studios = item.studios.compactMap(\.name).nonEmptyStrings, !studios.isEmpty {
                MetadataPillRow(title: "Studios", values: studios)
            }
        }
    }
}

// MARK: - Pill row

private struct MetadataPillRow: View {
    let title: LocalizedStringKey
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(values, id: \.self) { value in
                        Text(value)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                .padding(.vertical, 2)
            }
            .lookToScroll(.horizontal)
        }
    }
}
