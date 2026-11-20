import Observation
import SwiftUI

/// A window keeps its current results through tab and split-view replacement. A search
/// opened from a detail in Search can temporarily suspend that detail's original stack.
@MainActor @Observable
final class GlobalSearchSession {
    let typed = SectionSearchState(retainsResults: true)
    let natural = LibraryNaturalSearchState()
    private var mode = SearchDraftMode.natural

    var displaysKeywords: Bool {
        mode != .natural
    }

    var text: String {
        natural.text
    }

    func edit(_ value: String, naturalSearchEnabled: Bool) {
        guard value != text else { return }
        natural.text = value
        mode.edit(value, naturalSearchEnabled: naturalSearchEnabled)
        if displaysKeywords {
            typed.setKeywordText(value, recordsHistory: !naturalSearchEnabled)
        } else {
            typed.text = ""
        }
    }

    func searchByKeyword(recordingIn history: SearchHistoryStore? = nil) {
        natural.resetResults()
        mode = .keyword
        typed.setKeywordText(text, recordsHistory: history != nil)
        if let history {
            typed.submitSearch(to: history)
        }
    }

    func applyKeywordPreference() {
        if !displaysKeywords {
            searchByKeyword()
        }
        mode = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .natural : .keywordUntilSubmit
    }

    func submit(naturalSearchEnabled: Bool, history: SearchHistoryStore) {
        if naturalSearchEnabled {
            mode = .natural
            typed.text = ""
            natural.submit()
        } else {
            searchByKeyword(recordingIn: history)
            applyKeywordPreference()
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
