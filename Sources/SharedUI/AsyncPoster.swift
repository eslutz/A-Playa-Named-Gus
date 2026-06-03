import SwiftUI

/// Image loader built on `AsyncImage` + the shared tuned `URLCache`.
///
/// Replaces Swiftfin's Nuke usage. Uses system Materials + an SF Symbol for the
/// placeholder/failure states so it feels first-party everywhere.
struct AsyncPoster: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderSymbol: String = "photo"

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: animation)) { phase in
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

    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
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
