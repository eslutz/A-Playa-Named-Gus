import Foundation
import Observation

/// A typed query and a metadata search with the same title are distinct ways to search.
enum SearchHistoryEntry: Codable, Hashable, Identifiable {
    case typed(String)
    case related(RelatedSearch)

    var id: String {
        switch self {
        case let .typed(text): "typed:" + RelatedSearch.normalizedName(text)
        case let .related(search): "related:" + search.identityKey
        }
    }

    var title: String {
        switch self {
        case let .typed(text): text
        case let .related(search): search.name
        }
    }
}

/// Only completed search intents are kept on this device for the authenticated account.
@MainActor @Observable
final class SearchHistoryStore {
    private(set) var entries: [SearchHistoryEntry]
    private let defaults: UserDefaults
    private let key: String
    private var active = true

    init(scope: AccountScope, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = Self.key(for: scope)
        entries = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([SearchHistoryEntry].self, from: $0) } ?? []
    }

    func record(_ entry: SearchHistoryEntry) {
        guard active else { return }
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let value = if case .typed = entry {
            SearchHistoryEntry.typed(title)
        } else {
            entry
        }
        guard entries.first != value else { return }
        entries = [value] + entries.filter { $0.id != value.id }.prefix(19)
        persist()
    }

    func remove(_ entry: SearchHistoryEntry) {
        guard active else { return }
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clear() {
        guard active else { return }
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
