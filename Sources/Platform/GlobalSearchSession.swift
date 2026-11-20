import Observation
import SwiftUI

/// A window keeps its current results through tab and split-view replacement. A search
/// opened from a detail in Search can temporarily suspend that detail's original stack.
@MainActor @Observable
final class GlobalSearchSession {
    let typed = SectionSearchState(retainsResults: true)
    var related: RelatedSearchResults?

    init(target: RelatedSearch? = nil) {
        related = target.map { RelatedSearchResults(target: $0) }
    }
}

struct SearchDetailOrigin {
    let section: String
    let path: NavigationPath
    let sheet: ItemRef?
    let sheetPath: NavigationPath
    let search: GlobalSearchSession?
    let scrollAnchors: [String: String]
    let focus: TVFocusMemory
    let focusContext: String?
}

@MainActor @Observable
final class RelatedSearchResults {
    let target: RelatedSearch
    private(set) var resolved: RelatedSearch?
    private(set) var unavailable = false
    private(set) var errorMessage: String?
    var pages: LibraryStore?

    init(target: RelatedSearch) {
        self.target = target
        resolved = target.id == nil ? nil : target
    }

    func resolve(session: SessionStore) async {
        guard resolved == nil, !unavailable else { return }
        errorMessage = nil
        do {
            let match = try await session.mediaProvider.resolveRelatedSearch(target)
            try Task.checkCancellation()
            guard session.isActive else { return }
            if let match {
                resolved = match
                session.searchHistory.record(.related(match))
            } else {
                unavailable = true
            }
        } catch {
            let error = GusError(from: error)
            guard !Task.isCancelled, !error.isCancellation, session.isActive else { return }
            error.handleIfUnauthorized(session: session)
            errorMessage = error.localizedDescription
        }
    }
}
