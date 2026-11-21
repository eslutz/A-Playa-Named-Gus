import Foundation
import Observation

/// A one-query override ends on edit. Re-enabling natural search keeps an
/// existing keyword draft live until the user submits or clears it.
enum SearchDraftMode {
    case natural
    case keyword
    case keywordUntilSubmit

    mutating func edit(_ text: String, naturalSearchEnabled: Bool) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self = .natural
        } else if !naturalSearchEnabled {
            self = .keywordUntilSubmit
        } else if self != .keywordUntilSubmit {
            self = .natural
        }
    }
}

/// Holds one submitted query across adaptive layout changes. Editing never starts inference.
@MainActor @Observable
final class LibraryNaturalSearchState {
    var text = "" {
        didSet {
            if text != oldValue {
                resetResults()
            }
        }
    }

    private var activeRun = UUID()
    private(set) var submission: UUID?
    private(set) var filters: [String] = []
    private(set) var items: [MediaItem] = []
    private(set) var state: LoadState = .idle

    func submit() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        resetResults()
        submission = UUID()
        state = .loading
    }

    func resetResults() {
        submission = nil
        state = .idle
        items = []
        filters = []
    }

    func run(session: SessionStore, onKeyword: () -> Void) async {
        guard let request = submission, state == .loading, session.isActive else { return }
        let run = UUID()
        activeRun = run
        func isCurrent() -> Bool {
            session.isActive && submission == request && activeRun == run && session.intelligenceAccess.usesNaturalSearch
        }
        do {
            let allowed = try await session.intelligenceAccess.requestSearchAccess()
            try Task.checkCancellation()
            guard isCurrent() else { return }
            guard allowed else { throw GusIntelligenceError.useKeyword }
            let model = GusIntelligenceModel(session: session)
            let intent = try await model.interpretLibrary(text)
            try Task.checkCancellation()
            guard isCurrent() else { return }
            filters = intent.appliedFilters
            guard intent.unsupported.isEmpty else {
                let missing = intent.unsupported.joined(separator: ", ")
                state = .failed(String(localized: "Couldn’t verify these requirements: \(missing)"))
                return
            }
            let result = try await session.libraryIntelligence.search(intent)
            try Task.checkCancellation()
            guard isCurrent() else { return }
            items = ContentRatingGate.filter(result)
            state = .loaded
        } catch GusIntelligenceError.useKeyword {
            guard isCurrent(), !Task.isCancelled else { return }
            resetResults()
            onKeyword()
        } catch {
            guard isCurrent() else { return }
            let failure = GusError(from: error)
            if Task.isCancelled || failure.isCancellation {
                resetResults()
                return
            }
            failure.handleIfUnauthorized(session: session)
            state = .failed(error.localizedDescription)
        }
    }
}

/// Merge native field completions in source order using the current locale.
enum SearchCompletions {
    static func matching(_ prefix: String, candidates: [String], limit: Int = 6) -> [String] {
        let query = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, !query.isEmpty else { return [] }
        var seen: Set<String> = [query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)]
        var matches: [String] = []
        for term in candidates where term.localizedStandardContains(query) {
            let key = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if seen.insert(key).inserted {
                matches.append(term)
                if matches.count == limit {
                    break
                }
            }
        }
        return matches
    }
}
