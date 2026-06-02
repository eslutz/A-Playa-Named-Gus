import Foundation
import JellyfinAPI
import Observation
import OSLog

/// Loads the signed-in user's library views and "Continue Watching" items.
///
/// Pattern reference: Swiftfin's `HomeViewModel` (`Paths.getUserViews` +
/// `Paths.getResumeItems`).
@MainActor
@Observable
final class HomeStore {

    private(set) var state: LoadState = .idle
    private(set) var libraries: [BaseItemDto] = []
    private(set) var resumeItems: [BaseItemDto] = []

    private let session: SessionStore
    private let logger = Logger(subsystem: "dev.ericslutz.gus", category: "Home")

    init(session: SessionStore) {
        self.session = session
    }

    func load() async {
        state = .loading
        do {
            async let views = loadLibraries()
            async let resume = loadResume()
            libraries = try await views
            resumeItems = try await resume
            state = .loaded
        } catch {
            logger.error("Home load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    private func loadLibraries() async throws -> [BaseItemDto] {
        let parameters = Paths.GetUserViewsParameters(userID: session.user.id)
        let response = try await session.client.send(Paths.getUserViews(parameters: parameters))
        return response.value.items ?? []
    }

    private func loadResume() async throws -> [BaseItemDto] {
        let parameters = Paths.GetResumeItemsParameters(
            userID: session.user.id,
            limit: 20,
            fields: [.primaryImageAspectRatio],
            enableUserData: true,
            includeItemTypes: [.movie, .episode],
            enableImages: true
        )
        let response = try await session.client.send(Paths.getResumeItems(parameters: parameters))
        return response.value.items ?? []
    }
}
