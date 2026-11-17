import SwiftUI

/// Tiny poster thumbnail for watch rows — image widths stay watch-sized through the
/// provider's image pipeline (battery/network rule from the brief).
struct WatchPoster: View {
    @Environment(SessionStore.self) private var session
    let item: MediaItem
    @State private var candidateIndex = 0

    private var candidates: [URL] {
        session.mediaProvider.artworkURLs(for: item, request: .init(role: .poster, maxWidth: 120))
    }

    private var imageURL: URL? {
        candidates.indices.contains(candidateIndex) ? candidates[candidateIndex] : nil
    }

    var body: some View {
        // The row owns the thumbnail's geometry, including loaded artwork. Keep the
        // image inside the same size proposal as its placeholder.
        Color.clear
            .frame(width: 36, height: 54)
            .overlay {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case let .failure(error):
                        placeholder.task(id: imageURL) {
                            guard !Task.isCancelled, !GusError(from: error).isCancellation else { return }
                            if candidateIndex + 1 < candidates.count {
                                candidateIndex += 1
                            }
                        }
                    default:
                        placeholder
                    }
                }
                .onChange(of: candidates) { _, _ in candidateIndex = 0 }
                .frame(width: 36, height: 54)
                .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: item.artworkPlaceholderSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }
}
