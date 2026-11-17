import SwiftUI

/// Renders a `LoadState`: a spinner while loading, a `ContentUnavailableView` on
/// failure/empty, and the provided content once loaded.
struct LoadingStateView<Content: View>: View {
    let state: LoadState
    var isEmpty: Bool = false
    var emptyTitle: String = "Nothing Here Yet"
    var emptySymbol: String = "tray"
    var retryAction: (() -> Void)?
    var preservesContent = false
    @ViewBuilder var content: () -> Content

    private var phase: ForegroundLoadPhase {
        state.foregroundPhase(hasContent: preservesContent && !isEmpty)
    }

    var body: some View {
        if preservesContent, !isEmpty {
            VStack(spacing: 8) {
                if phase == .loading(.refresh) {
                    ProgressView().accessibilityLabel("Refreshing")
                } else if case let .failed(.refresh, message) = phase {
                    VStack(spacing: 8) {
                        Text(message).foregroundStyle(.secondary)
                        if let retryAction {
                            Button("Try Again", action: retryAction)
                        }
                    }
                    .padding()
                }
                content()
            }
        } else {
            initialContent
        }
    }

    @ViewBuilder private var initialContent: some View {
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
            } actions: {
                if let retryAction {
                    Button("Try Again", action: retryAction)
                }
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
