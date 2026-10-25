import Foundation
import Observation

/// A server item ID is a locator, not a permanent identity. The snapshot is only
/// a fallback for presentation while offline; it never authorizes remote actions.
struct MediaReference: Codable, Hashable, Sendable {
    let scope: AccountScope
    var item: MediaItem

    init(item: MediaItem, scope: AccountScope) {
        self.item = item
        self.scope = scope
    }
}

enum MediaReferenceResolution: Sendable {
    case resolved(MediaItem)
    case unavailable
    case requiresSelection([MediaItem])
}

@MainActor
@Observable
final class MediaReferenceResolver {
    let scope: AccountScope
    private(set) var isActive = true
    private let provider: any MediaProviderSession
    private var validated: [MediaReference: (item: MediaItem, date: Date)] = [:]
    private var aliases: [String: String] = [:]
    private var pending: [MediaReference: Task<MediaReferenceResolution, Error>] = [:]
    private var catalogs: [MediaItemType: Task<[MediaItem], Error>] = [:]
    private(set) var revision = 0
    private(set) var updates: [String: MediaItem] = [:]

    init(provider: any MediaProviderSession, scope: AccountScope) {
        self.provider = provider
        self.scope = scope
    }

    /// Call at the start of an explicit refresh/foreground reconciliation. Aliases
    /// survive only this session; their targets are still verified before actions.
    func invalidate() {
        isActive = false
        for task in pending.values {
            task.cancel()
        }
        for task in catalogs.values {
            task.cancel()
        }
        pending.removeAll()
        catalogs.removeAll()
        validated.removeAll()
        updates.removeAll()
    }

    func beginRefresh() {
        validated.removeAll()
        catalogs.removeAll()
    }

    func resolve(_ reference: MediaReference, forceRefresh: Bool = false) async throws -> MediaReferenceResolution {
        guard isActive, reference.scope == scope, reference.item.providerKind == provider.providerKind,
              let id = reference.item.id else { throw GusError.notFound }
        if !forceRefresh, let cached = validated[reference], Date().timeIntervalSince(cached.date) < 300 {
            return .resolved(cached.item)
        }
        if let task = pending[reference] {
            let result = try await task.value
            try Task.checkCancellation()
            guard isActive else { throw GusError.cancelled }
            return result
        }
        let task = Task { try await self.lookup(reference) }
        pending[reference] = task
        defer { pending.removeValue(forKey: reference) }
        let result = try await task.value
        try Task.checkCancellation()
        guard isActive else { throw GusError.cancelled }
        if case let .resolved(item) = result {
            validated[reference] = (item, Date())
            updates[id] = item
            if let currentID = item.id, currentID != id {
                aliases[id] = currentID
                DiagnosticsHub.shared.record(.referenceReplaced)
            }
            revision += 1
        }
        return result
    }

    func currentItem(_ item: MediaItem, forceRefresh: Bool = true) async throws -> MediaItem {
        let result = try await resolve(MediaReference(item: item, scope: scope), forceRefresh: forceRefresh)
        guard case let .resolved(current) = result else { throw GusError.notFound }
        return current
    }

    /// An explicit user choice is resolved again in the current account. Nothing is
    /// written until the owner store checks its entry/revision is still current.
    func selectedReplacement(_ item: MediaItem) async throws -> MediaItem {
        guard isActive, item.providerKind == provider.providerKind, let id = item.id else { throw GusError.notFound }
        let current = try await provider.item(id: id)
        try Task.checkCancellation()
        guard isActive, ContentRatingGate.admitsStored(current) else { throw GusError.notFound }
        return current
    }

    func recordReplacement(from old: MediaReference, to current: MediaItem) {
        guard old.scope == scope, old.item.providerKind == provider.providerKind,
              current.providerKind == provider.providerKind, let oldID = old.item.id, let newID = current.id else { return }
        aliases[oldID] = newID
        updates[oldID] = current
        validated[old] = (current, Date())
        revision += 1
    }

    private func lookup(_ reference: MediaReference) async throws -> MediaReferenceResolution {
        let saved = reference.item
        guard let id = saved.id else { return .unavailable }
        do {
            let current = try await provider.item(id: aliases[id] ?? id)
            if let type = saved.type, let currentType = current.type, type != currentType {
                throw GusError.notFound
            }
            let a = Self.identities(saved), b = Self.identities(current)
            // An old locator can be reused. Missing or unrelated namespaces do
            // not prove that this is still the saved title.
            if !a.isEmpty, !a.contains(where: { b[$0.key] == $0.value }) || a.contains(where: { b[$0.key] != nil && b[$0.key] != $0.value }) {
                throw GusError.notFound
            }
            return .resolved(current)
        } catch {
            guard GusError(from: error) == .notFound else { throw error }
        }
        DiagnosticsHub.shared.record(.referenceUnavailable)
        SpotlightIndexer.deleteItem(itemID: id, serverID: scope.serverID, userID: scope.userID)
        if var shelf = TopShelfSnapshot.load(), shelf.serverID == scope.serverID, shelf.userID == scope.userID {
            shelf.items.removeAll { $0.id == id }
            shelf.save()
        }
        let identities = Self.identities(saved)
        guard !identities.isEmpty, let type = saved.type else {
            guard let name = saved.name, !name.isEmpty else { return .unavailable }
            let page = try await provider.items(query: MediaItemQuery(
                searchTerm: name, includeTypes: saved.type.map { [$0] }, startIndex: 0,
                limit: 100, isRecursive: true, sort: .name
            ))
            let suggestions = page.items.filter { $0.id != nil && $0.type == saved.type }
            return suggestions.isEmpty ? .unavailable : .requiresSelection(suggestions)
        }
        let candidates = try await catalog(type: type).filter { Self.matches(saved, candidate: $0) }
        guard candidates.count == 1, let candidate = candidates.first, let candidateID = candidate.id else {
            return candidates.isEmpty ? .unavailable : .requiresSelection(candidates)
        }
        // Recheck the chosen identity; a library can change during enumeration.
        let current = try await provider.item(id: candidateID)
        guard Self.matches(saved, candidate: current) else { return .requiresSelection(candidates) }
        return .resolved(current)
    }

    private func catalog(type: MediaItemType) async throws -> [MediaItem] {
        if let task = catalogs[type] {
            return try await task.value
        }
        let task = Task<[MediaItem], Error> {
            var items: [MediaItem] = []
            var seen = Set<String>()
            var expectedTotal: Int?
            while true {
                try Task.checkCancellation()
                let page = try await self.provider.items(query: MediaItemQuery(
                    includeTypes: [type], startIndex: items.count, limit: 200,
                    isRecursive: true, sort: .name
                ))
                if let total = page.totalRecordCount {
                    if let expectedTotal, expectedTotal != total {
                        throw GusError.server(String(localized: "The library changed. Try again.", comment: "Catalog changed during reference recovery"))
                    }
                    expectedTotal = total
                }
                for item in page.items {
                    guard let id = item.id, seen.insert(id).inserted else {
                        throw GusError.server(String(localized: "The library changed. Try again.", comment: "Catalog changed during reference recovery"))
                    }
                    items.append(item)
                }
                if let total = expectedTotal, items.count > total {
                    throw GusError.offline
                }
                if let total = expectedTotal, items.count == total {
                    return items
                }
                if page.items.isEmpty {
                    if let total = expectedTotal, items.count < total {
                        throw GusError.offline
                    }
                    return items
                }
                if expectedTotal == nil, page.items.count < 200 {
                    return items
                }
            }
        }
        catalogs[type] = task
        do { return try await task.value } catch { catalogs.removeValue(forKey: type); throw error }
    }

    static func identities(_ item: MediaItem) -> [String: String] {
        guard item.type == .movie || item.type == .series || item.type == .episode else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in item.externalIDs {
            let namespace = key.lowercased()
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["imdb", "tmdb", "tvdb"].contains(namespace), !value.isEmpty {
                result[namespace] = value
            }
        }
        return result
    }

    static func matches(_ saved: MediaItem, candidate: MediaItem) -> Bool {
        guard candidate.id != nil, candidate.providerKind == saved.providerKind, candidate.type == saved.type else { return false }
        if let a = saved.productionYear, let b = candidate.productionYear, a != b {
            return false
        }
        let a = identities(saved), b = identities(candidate)
        guard !a.isEmpty, a.contains(where: { b[$0.key] == $0.value }), !a.contains(where: { b[$0.key] != nil && b[$0.key] != $0.value }) else { return false }
        if saved.type == .episode {
            // Different series IDs need separate explicit recovery; episode numbers
            // alone cannot establish which series an episode belongs to.
            guard let series = saved.seriesID, series == candidate.seriesID,
                  let season = saved.parentIndexNumber, season == candidate.parentIndexNumber,
                  let episode = saved.indexNumber, episode == candidate.indexNumber else { return false }
        }
        return true
    }
}

/// Do not silently transplant a saved position when the remote identity changes.
enum MediaPlaybackIdentity {
    static func resumeTicks(requested: Int?, originalID: String, current: MediaItem) -> Int? {
        if current.id == originalID || requested == 0 {
            return requested
        }
        return current.userData?.playbackPositionTicks
    }
}
