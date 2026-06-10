import SwiftUI

/// Tiny poster thumbnail for watch rows — image widths stay watch-sized through the
/// provider's image pipeline (battery/network rule from the brief).
struct WatchPoster: View {
    @Environment(SessionStore.self) private var session
    let item: MediaItem

    var body: some View {
        AsyncImage(url: session.mediaProvider.primaryImageURL(for: item, maxWidth: 120)) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            default:
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 36, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}
