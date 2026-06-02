import SwiftUI

/// Renders a `LoadState`: a spinner while loading, a `ContentUnavailableView` on
/// failure/empty, and the provided content once loaded.
struct LoadingStateView<Content: View>: View {

    let state: LoadState
    var isEmpty: Bool = false
    var emptyTitle: String = "Nothing Here Yet"
    var emptySymbol: String = "tray"
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        case .loaded:
            if isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptySymbol)
                }
            } else {
                content()
            }
        }
    }
}
