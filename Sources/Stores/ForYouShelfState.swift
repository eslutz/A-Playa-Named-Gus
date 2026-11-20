import Foundation
import Observation

/// The shelf refreshes independently of Home's playback and discovery rails.
@MainActor @Observable
final class ForYouShelfState {
    struct Context: Equatable {
        let cloudEnabled: Bool
        let recommendationsEnabled: Bool
        let limit: String
        let hideUnrated: Bool
        let activityRevision: Int
        let tasteRevision: Int
    }

    private(set) var picks: [GusLibraryPick] = []
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var context: Context?
    private var generation = UUID()

    func load(_ context: Context, session: SessionStore, refresh: Bool = false) async {
        let previous = self.context
        let token = UUID()
        generation = token
        self.context = context
        error = nil
        if previous != context {
            picks = []
        }
        guard session.isActive, context.recommendationsEnabled else {
            picks = []
            isLoading = false
            return
        }
        isLoading = true
        defer {
            if generation == token {
                isLoading = false
            }
        }
        do {
            let result = try await session.libraryIntelligence.recommendations(refresh: refresh)
            try Task.checkCancellation()
            guard session.isActive, generation == token, session.intelligencePreferences.recommendationsEnabled else { return }
            picks = result.filter { ContentRatingGate.admitsStored($0.item) }
        } catch {
            guard session.isActive, !Task.isCancelled, generation == token else { return }
            let failure = GusError(from: error)
            failure.handleIfUnauthorized(session: session)
            if !failure.isCancellation {
                picks = []
                self.error = error.localizedDescription
            }
        }
    }
}
