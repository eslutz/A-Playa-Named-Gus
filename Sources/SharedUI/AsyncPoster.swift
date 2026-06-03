import SwiftUI

/// Image loader built on `AsyncImage` + the shared tuned `URLCache`.
///
/// Replaces Swiftfin's Nuke usage. Uses system Materials + an SF Symbol for the
/// placeholder/failure states so it feels first-party everywhere.
struct AsyncPoster: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
            // When Reduce Transparency is on, Materials are semi-transparent and violate the
            // preference. Fall back to an opaque tonal fill so the placeholder is clearly
            // distinct without relying on the blurred background.
            .fill(reduceTransparency ? AnyShapeStyle(Color.secondary.opacity(0.2)) : AnyShapeStyle(.regularMaterial))
            .overlay {
                Image(systemName: placeholderSymbol)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
    }
}
