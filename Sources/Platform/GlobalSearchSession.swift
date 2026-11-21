import Observation
import SwiftUI

/// The Search tab owns its draft and results across adaptive layout changes.
@MainActor @Observable
final class GlobalSearchSession {
    let typed = SectionSearchState(retainsResults: true)
    let natural = LibraryNaturalSearchState()
    private var mode = SearchDraftMode.natural
    private(set) var showsDraftSuggestions = true

    var displaysKeywords: Bool {
        mode != .natural
    }

    var text: String {
        natural.text
    }

    func edit(_ value: String, naturalSearchEnabled: Bool) {
        guard value != text else { return }
        showsDraftSuggestions = true
        natural.text = value
        mode.edit(value, naturalSearchEnabled: naturalSearchEnabled)
        if displaysKeywords {
            typed.setKeywordText(value, recordsHistory: !naturalSearchEnabled)
        } else {
            typed.text = ""
        }
    }

    func searchByKeyword(recordingIn history: SearchHistoryStore? = nil) {
        showsDraftSuggestions = false
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
            showsDraftSuggestions = false
            mode = .natural
            typed.text = ""
            natural.submit()
        } else {
            searchByKeyword(recordingIn: history)
            applyKeywordPreference()
        }
    }
}

enum DetailNavigationStack: Hashable {
    case section(String)
    case sheet(itemID: String)
}

struct DetailStackPosition: Hashable {
    let stack: DetailNavigationStack
    let depth: Int
}

struct DetailViewportReturn: Equatable {
    let position: DetailStackPosition
    let location: DetailScrollLocation
}

extension EnvironmentValues {
    @Entry var detailNavigationStack: DetailNavigationStack?
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
    let id = UUID()
    let target: RelatedSearch
    let originatingViewport: DetailScrollLocation?
    var storeKey: String {
        "related:" + id.uuidString
    }

    private(set) var resolved: RelatedSearch?
    private(set) var unavailable = false
    private(set) var errorMessage: String?
    var pages: LibraryStore?
    var scrollAnchor: String?
    let viewport = SearchResultsViewport()
    private(set) var lookupID = UUID()

    @ObservationIgnored private var discarded = false

    func discard() {
        discarded = true
    }

    func retry() {
        errorMessage = nil
        lookupID = UUID()
    }

    init(target: RelatedSearch, originatingViewport: DetailScrollLocation? = nil) {
        self.target = target
        self.originatingViewport = originatingViewport
        resolved = target.id == nil ? nil : target
    }

    func resolve(session: SessionStore) async {
        guard !discarded, resolved == nil, !unavailable, errorMessage == nil, session.isActive, !Task.isCancelled else { return }
        let lookup = lookupID
        do {
            let match = try await session.mediaProvider.resolveRelatedSearch(target)
            try Task.checkCancellation()
            guard !discarded, session.isActive, lookupID == lookup, resolved == nil else { return }
            if let match {
                resolved = match
                session.searchHistory.record(.related(match))
            } else {
                unavailable = true
            }
        } catch {
            let error = GusError(from: error)
            guard !discarded, !Task.isCancelled, !error.isCancellation, session.isActive, lookupID == lookup, resolved == nil else { return }
            error.handleIfUnauthorized(session: session)
            errorMessage = error.localizedDescription
        }
    }
}
