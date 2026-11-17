import Foundation

/// Shared presentation meaning for actions; domain journals retain their own phases.
/// Cancellation clears the outcome rather than becoming a displayed failure.
enum ActionOutcome: Equatable, Sendable {
    case pending
    case accepted
    case confirmed
    case queued
    case uncertain
    case failed(GusError)

    var accessibilityValue: String {
        switch self {
        case .pending: String(localized: "In progress")
        case .accepted: String(localized: "Accepted")
        case .confirmed: String(localized: "Confirmed")
        case .queued: String(localized: "Queued")
        case .uncertain: String(localized: "Not confirmed")
        case let .failed(error): error.localizedDescription
        }
    }
}

/// Simple load lifecycle shared by the feature stores and `LoadingStateView`.
enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool {
        self == .loading
    }
}

/// Foreground presentation distinguishes an empty initial load from work over
/// usable content. Domain stores keep their own query and action phases.
enum ForegroundLoadOperation: Equatable { case initial, refresh, pagination }
enum ForegroundLoadPhase: Equatable {
    case ready
    case loading(ForegroundLoadOperation)
    case failed(ForegroundLoadOperation, String)
}

extension LoadState {
    func foregroundPhase(hasContent: Bool, refreshing: Bool = false, paging: Bool = false, pageError: String? = nil) -> ForegroundLoadPhase {
        if let pageError {
            return .failed(.pagination, pageError)
        }
        if paging {
            return .loading(.pagination)
        }
        if refreshing {
            return .loading(.refresh)
        }
        switch self {
        case .idle, .loading: return .loading(hasContent ? .refresh : .initial)
        case let .failed(message): return .failed(hasContent ? .refresh : .initial, message)
        case .loaded: return .ready
        }
    }
}
