import Foundation

/// Simple load lifecycle shared by the feature stores and `LoadingStateView`.
enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool { self == .loading }
}
