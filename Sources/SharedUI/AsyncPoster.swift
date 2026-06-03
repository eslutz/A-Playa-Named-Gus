import SwiftUI

/// Image loader built on `AsyncImage` + the shared tuned `URLCache`.
///
/// Replaces Swiftfin's Nuke usage. Uses system Materials + an SF Symbol for the
/// placeholder/failure states so it feels first-party everywhere.
struct AsyncPoster: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderSymbol: String = "photo"

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failure:
                placeholder
            case .empty:
                placeholder.overlay { ProgressView() }
            @unknown default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay {
                Image(systemName: placeholderSymbol)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
    }
}
