import Foundation
import Observation

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

    func run(session: SessionStore) async {
        guard let request = submission, state == .loading, session.isActive else { return }
        let run = UUID()
        activeRun = run
        do {
            let model = GusIntelligenceModel(session: session)
            let intent = try await model.interpretLibrary(text)
            try Task.checkCancellation()
            guard session.isActive, submission == request, activeRun == run else { return }
            filters = intent.appliedFilters
            guard intent.unsupported.isEmpty else {
                let missing = intent.unsupported.joined(separator: ", ")
                state = .failed(String(localized: "Couldn’t verify these requirements: \(missing)"))
                return
            }
            let result = try await session.libraryIntelligence.search(intent)
            try Task.checkCancellation()
            guard session.isActive, submission == request, activeRun == run else { return }
            items = ContentRatingGate.filter(result)
            state = .loaded
        } catch {
            guard session.isActive, submission == request, activeRun == run else { return }
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
