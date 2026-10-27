import SwiftUI

/// One semantic row for the grid/list variants of a library, retaining the same destination.
struct MediaLibraryRow: View {
    @Environment(SessionStore.self) private var session
    let item: MediaItem

    var body: some View {
        HStack(spacing: 16) {
            ArtworkTile(url: session.mediaProvider.primaryImageURL(for: item, context: .posterGrid), aspectRatio: 2.0 / 3.0, placeholderSymbol: item.artworkPlaceholderSymbol)
                .frame(width: 44, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle).font(.body.weight(.medium))
                if let year = item.productionYear {
                    Text(String(year)).font(.subheadline).foregroundStyle(.secondary)
                } else if let artist = item.albumArtist ?? item.artists.first {
                    Text(artist).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
