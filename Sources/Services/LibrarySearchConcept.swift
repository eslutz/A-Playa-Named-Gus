import Foundation

/// A requested idea and alternative phrases that can establish it in one title's metadata.
struct LibrarySearchConcept: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable { case tone, subject }

    let phrase: String
    let kind: Kind
    let alternatives: [String]
    var id: String {
        GusLibraryMatching.normalized(phrase)
    }

    private static let scary = ["scary", "creepy", "frightening", "terrifying", "eerie", "horror", "nightmarish"]
    private static let robots = ["robot", "robots", "robotic", "android", "androids", "droid", "droids", "animatronic", "animatronics", "automaton", "automatons", "automata"]

    init(_ phrase: String, kind: Kind = .subject, synonyms: [String] = []) {
        self.phrase = phrase
        let key = GusLibraryMatching.normalized(phrase)
        if Self.scary.contains(key) {
            self.kind = .tone
            alternatives = Self.scary
        } else if Self.robots.contains(key) {
            self.kind = .subject
            alternatives = Self.robots
        } else {
            self.kind = kind
            var seen = Set<String>()
            alternatives = ([key] + synonyms.map(GusLibraryMatching.normalized)).filter { !$0.isEmpty && seen.insert($0).inserted }
        }
    }

    static func known(_ word: String) -> Self? {
        guard scary.contains(word) || robots.contains(word) else { return nil }
        return Self(word)
    }

    /// English exclusions and alternatives cannot be represented by a conjunction of positive
    /// concepts. Inspect words outside named lookups; a title itself may include “not” or “or”.
    static func hasUnsupportedComposition(in text: String, concepts: [Self]) -> Bool {
        let phrases = Set(scary + robots + concepts.map(\.id))
        let connectors = ["without", "without a", "without any", "excluding", "except for", "not", "not a", "not too", "no", "or"]
        return phrases.contains { phrase in
            text.contains(" " + phrase + " or ") || connectors.contains { text.contains(" " + $0 + " " + phrase + " ") }
        }
    }

    var label: String {
        if alternatives == Self.scary {
            return String(localized: "Scary tone")
        }
        if alternatives == Self.robots {
            return String(localized: "Robots")
        }
        return phrase
    }

    var browseLabel: String {
        if alternatives == Self.scary {
            return String(localized: "Horror")
        }
        if alternatives == Self.robots {
            return String(localized: "Robot stories")
        }
        return label
    }

    /// Tags and genres express a category directly. An overview or tagline provides plot evidence.
    func strength(in item: MediaItem) -> Int {
        let categories = item.tags + (kind == .tone ? item.genres : [])
        if matches(categories) {
            return 2
        }
        return matches([item.overview].compactMap { $0 } + item.taglines) ? 1 : 0
    }

    private func matches(_ values: [String]) -> Bool {
        values.contains { value in
            let words = " " + GusLibraryMatching.normalized(value) + " "
            return alternatives.contains { words.contains(" " + $0 + " ") }
        }
    }
}

extension GusSearchIntent {
    struct Relaxation: Identifiable, Sendable {
        let id: String
        let label: String
    }

    var relaxations: [Relaxation] {
        guard concepts.count > 1 else { return [] }
        return concepts.map { removed in
            let remaining = concepts.filter { $0.id != removed.id }
            let label = remaining.count == 1 ? remaining[0].browseLabel : String(localized: "Remove \(removed.label)")
            return Relaxation(id: removed.id, label: label)
        }
    }

    func removingConcept(_ id: String) -> Self? {
        guard concepts.count > 1, concepts.contains(where: { $0.id == id }) else { return nil }
        var broader = self
        broader.concepts.removeAll { $0.id == id }
        return broader
    }

    /// Only open-ended concept searches prefer complete titles. Named lookups and requested
    /// media types keep their own granularity, including multiple explicitly requested episodes.
    var prefersTitles: Bool {
        !concepts.isEmpty && mediaTypes.isEmpty && keywords.isEmpty
    }

    func groupID(_ item: MediaItem) -> String? {
        guard let id = item.id else { return nil }
        if prefersTitles {
            if item.type == .series {
                return "series:" + id
            }
            if item.type == .episode, let seriesID = item.seriesID, !seriesID.isEmpty {
                return "series:" + seriesID
            }
        }
        return "item:" + id
    }

    struct Rank: Comparable, Sendable {
        let typePriority: Int
        let strength: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.typePriority, lhs.strength) < (rhs.typePriority, rhs.strength)
        }
    }

    func rank(_ item: MediaItem) -> Rank {
        let preferred = prefersTitles && (item.type == .series || item.type == .movie)
        return Rank(typePriority: preferred ? 1 : 0, strength: concepts.reduce(0) { $0 + $1.strength(in: item) })
    }

    func rankedResults(_ items: [MediaItem], limit: Int = 60) -> [MediaItem] {
        guard limit > 0 else { return [] }
        guard !concepts.isEmpty else { return Array(items.prefix(limit)) }
        let ranked = items.map { (item: $0, rank: rank($0)) }.sorted { $0.rank > $1.rank }
        var seen = Set<String>()
        var results: [MediaItem] = []
        for match in ranked {
            guard let key = groupID(match.item), seen.insert(key).inserted else { continue }
            results.append(match.item)
            if results.count == limit {
                break
            }
        }
        return results
    }
}
