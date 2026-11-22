import Foundation
import Observation

/// Keep the search mode so replay can reproduce the original intent.
enum SearchHistoryEntry: Codable, Hashable, Identifiable {
    case typed(String)
    case natural(String)
    case related(RelatedSearch)

    var id: String {
        switch self {
        case let .typed(text): "typed:" + Self.normalizedKey(text)
        case let .natural(text): "natural:" + Self.normalizedKey(text)
        case let .related(search): "related:" + search.identityKey
        }
    }

    private static func normalizedKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    var completed: Self? {
        switch self {
        case let .typed(text):
            let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return nil }
            return .typed(query)
        case let .natural(text):
            let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return nil }
            return .natural(query)
        case let .related(target):
            let value = RelatedSearch(kind: target.kind, id: target.id, name: target.name)
            guard value.id != nil, !value.name.isEmpty else { return nil }
            return .related(value)
        }
    }
}

/// Only completed search intents are kept on this device for the authenticated account.
@MainActor @Observable
final class SearchHistoryStore {
    private static let limit = 20
    private(set) var entries: [SearchHistoryEntry]
    private let defaults: UserDefaults
    private let key: String
    private var active = true
    /// A delayed completion started before an explicit deletion cannot undo it.
    private(set) var deletionRevision = 0

    init(scope: AccountScope, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = Self.key(for: scope)
        let saved = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([SearchHistoryEntry].self, from: $0) } ?? []
        var seen = Set<String>()
        entries = Array(saved.compactMap(\.completed).filter { seen.insert($0.id).inserted }.prefix(Self.limit))
        if entries != saved {
            persist()
        }
    }

    func record(_ entry: SearchHistoryEntry, startedAt revision: Int? = nil) {
        guard revision == nil || revision == deletionRevision, active, let value = entry.completed, entries.first != value else { return }
        entries = [value] + entries.filter { $0.id != value.id }.prefix(Self.limit - 1)
        persist()
    }

    func remove(_ entry: SearchHistoryEntry) {
        guard active else { return }
        deletionRevision += 1
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clear() {
        guard active else { return }
        deletionRevision += 1
        entries.removeAll()
        defaults.removeObject(forKey: key)
    }

    /// A disappearing view from a signed-out session must not restore a deleted entry.
    func deactivate() {
        active = false
        entries.removeAll()
    }

    static func delete(scope: AccountScope, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(for: scope))
    }

    private func persist() {
        if entries.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }

    private static func key(for scope: AccountScope) -> String {
        let server = Data(scope.serverID.utf8).base64EncodedString()
        let user = Data(scope.userID.utf8).base64EncodedString()
        return "dev.ericslutz.gus.searchHistory." + server + "." + user
    }
}
