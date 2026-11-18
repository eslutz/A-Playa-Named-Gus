import SwiftUI

/// Native image rendering; OS27 inherits the account-owned system session/cache.
/// OS26 retains AsyncImage's native transport because session injection is unavailable.
///
/// Replaces Swiftfin's Nuke usage. Uses system Materials + an SF Symbol for the
/// placeholder/failure states so it feels first-party everywhere.
struct AsyncPoster: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderSymbol: String = "photo"
    var fallbackURLs: [URL] = []
    var onExhausted: (() async -> Void)?
    var body: some View {
        let sequence = ArtworkRequestSequence([url].compactMap { $0 } + fallbackURLs)
        PosterRequest(sequence: sequence, contentMode: contentMode, placeholderSymbol: placeholderSymbol, onExhausted: onExhausted)
            // A header-only collection can gain its member cover asynchronously.
            // Give the replacement sequence a fresh attempt, including its first URL.
            .id(sequence.urls)
    }
}

private struct PosterRequest: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State var sequence: ArtworkRequestSequence
    let contentMode: ContentMode
    let placeholderSymbol: String
    let onExhausted: (() async -> Void)?

    var body: some View {
        let requestedURL = sequence.currentURL
        AsyncImage(url: requestedURL, transaction: Transaction(animation: animation)) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case let .failure(error):
                placeholder.task {
                    guard let requestedURL, !Task.isCancelled, !GusError(from: error).isCancellation else { return }
                    switch sequence.failed(requestedURL) {
                    case .advanced: DiagnosticsHub.shared.record(.artworkFallback)
                    case .exhausted: await onExhausted?()
                    case .ignored: break
                    }
                }
            case .empty:
                placeholder.overlay {
                    if requestedURL != nil {
                        ProgressView()
                    }
                }
            @unknown default:
                placeholder
            }
        }
        // AsyncImage may retain its previous phase while changing URLs. Its
        // failure task must belong to the request which produced that phase.
        .id(requestedURL)
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
