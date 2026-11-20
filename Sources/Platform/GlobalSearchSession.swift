import Observation
import SwiftUI

/// A window keeps its current results through tab and split-view replacement. A search
/// opened from a detail in Search can temporarily suspend that detail's original stack.
@MainActor @Observable
final class GlobalSearchSession {
    let typed = SectionSearchState(retainsResults: true)
    let natural = LibraryNaturalSearchState()
    var naturalMode = false {
        didSet {
            if oldValue != naturalMode {
                natural.resetResults()
            }
        }
    }

    var text: String {
        naturalMode ? natural.text : typed.text
    }

    func submit(to history: SearchHistoryStore) {
        if naturalMode {
            natural.submit()
        } else {
            typed.submitSearch(to: history)
        }
    }

    var related: RelatedSearchResults?
    var detailOrigin: SearchDetailOrigin?

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
    let viewport: DetailScrollLocation?
    let focus: TVFocusMemory
    let focusContext: String?
}

struct DetailScrollLocation: Equatable {
    let key: String
    let y: CGFloat
}

/// A saved result position belongs to one query in one window.
@MainActor final class SearchResultsViewport {
    var distanceFromTop: CGFloat?
}

@MainActor @Observable
final class RelatedSearchResults {
    let target: RelatedSearch
    private(set) var resolved: RelatedSearch?
    private(set) var unavailable = false
    private(set) var errorMessage: String?
    var pages: LibraryStore?
    var scrollAnchor: String?
    let viewport = SearchResultsViewport()
    private(set) var lookupID = UUID()

    func retry() {
        errorMessage = nil
        lookupID = UUID()
    }

    init(target: RelatedSearch) {
        self.target = target
        resolved = target.id == nil ? nil : target
    }

    func resolve(session: SessionStore) async {
        guard resolved == nil, !unavailable, errorMessage == nil else { return }
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
