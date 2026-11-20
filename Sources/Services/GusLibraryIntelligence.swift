import Foundation
import Observation
import OSLog

/// Session-owned catalog search and recommendation retrieval. All rows and model candidates
/// are checked against the current authenticated provider before leaving this boundary.
@MainActor @Observable
final class GusLibraryIntelligence {
    @ObservationIgnored private weak var session: SessionStore?
    private let catalog: GusLibraryCatalog
    @ObservationIgnored private var scan: Task<Void, Error>?
    @ObservationIgnored private var scanRestriction: String?
    @ObservationIgnored private var scanGeneration = UUID()
    private(set) var isIndexing = false
    private(set) var tasteRevision = 0
    private var shelfGeneration = UUID()
    @ObservationIgnored private var pendingShelf: (context: String, refresh: Bool, task: Task<[GusLibraryPick], Error>)?
    private var cachedPicks: [GusLibraryPick] = []
    private var cachedSeeds: [MediaItem]?
    private var cachedRestrictions: String?

    init(session: SessionStore) {
        self.session = session
        self.catalog = GusLibraryCatalog(directory: GusLibraryCatalog.directory(for: session.references.scope))
        session.onInvalidation(of: self) { owner in
            owner.cancelIndexing()
            owner.clearRecommendations()
        }
    }

    static func deleteCatalog(scope: AccountScope) {
        let root = GusLibraryCatalog.directory(for: scope)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        do { try FileManager.default.removeItem(at: root) }
        catch { Logger(category: .search).error("Could not remove the private library catalog.") }
    }

    func cancelIndexing() {
        scanGeneration = UUID()
        scan?.cancel()
        scan = nil
        scanRestriction = nil
        isIndexing = false
    }

    func clearRecommendations() {
        shelfGeneration = UUID()
        pendingShelf?.task.cancel()
        pendingShelf = nil
        cachedSeeds = nil
        cachedPicks = []
        cachedRestrictions = nil
    }

    func invalidateTasteSignals() {
        tasteRevision += 1
        clearRecommendations()
    }

    private var restrictions: String {
        ContentRatingGate.storedLimit().rawValue + String(UserDefaults.standard.bool(forKey: ContentRatingGate.hideUnratedDefaultsKey))
    }

    private func check(_ restriction: String) throws -> SessionStore {
        try Task.checkCancellation()
        guard let session, session.isActive, restrictions == restriction else { throw CancellationError() }
        return session
    }

    private func fetch(_ query: MediaItemQuery, restriction: String) async throws -> MediaItemPage {
        let session = try check(restriction)
        var metadataQuery = query
        metadataQuery.metadataOnly = true
        do {
            let page = try await session.mediaProvider.items(query: metadataQuery)
            _ = try check(restriction)
            return page
        } catch {
            let error = GusError(from: error)
            error.handleIfUnauthorized(session: session)
            throw error
        }
    }

    private func page(_ limit: Int, offset: Int = 0, term: String? = nil, sort: MediaItemSort = .name) -> MediaItemQuery {
        MediaItemQuery(searchTerm: term, includeTypes: GusLibraryMatching.types, startIndex: offset, limit: limit, isRecursive: true, sort: sort)
    }

    /// Join scans across windows and suggestions. Cancellation of a single query leaves the
    /// shared foreground scan available to the other search consumers.
    private func refreshCatalog(restriction: String, force: Bool) async throws {
        _ = try check(restriction)
        if scanRestriction != restriction {
            cancelIndexing()
        }
        if let scan {
            try await scan.value
            _ = try check(restriction)
            return
        }
        if !force, await catalog.isFresh(restriction: restriction) {
            return
        }
        _ = try check(restriction)
        if let scan, scanRestriction == restriction {
            try await scan.value
            _ = try check(restriction)
            return
        }
        cancelIndexing()
        let generation = UUID()
        scanGeneration = generation
        let task = Task { try await self.buildCatalog(restriction: restriction) }
        scan = task
        scanRestriction = restriction
        isIndexing = true
        defer {
            if scanGeneration == generation {
                scan = nil
                scanRestriction = nil
                isIndexing = false
            }
        }
        try await task.value
        _ = try check(restriction)
    }

    private func buildCatalog(restriction: String) async throws {
        // Account deletion and publication run on the same actor. The disk worker never
        // recreates a deleted directory after sign-out.
        _ = try check(restriction)
        try FileManager.default.createDirectory(at: catalog.directory, withIntermediateDirectories: true)
        let file = catalog.directory.appending(path: UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: file) }
        try await catalog.prepare(file, restriction: restriction)
        var progress = GusCatalogPaging()
        while true {
            let result = try await fetch(page(200, offset: progress.offset), restriction: restriction)
            let complete = try progress.advance(result, requested: 200)
            try await catalog.append(ContentRatingGate.filter(result.items), to: file)
            if complete {
                break
            }
        }
        _ = try check(restriction)
        // A same-directory rename commits the entire closed SQLite database in one operation.
        let destination = catalog.snapshot
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: file, options: .usingNewMetadataOnly)
        } else {
            try FileManager.default.moveItem(at: file, to: destination)
        }
    }

    private func verified(_ records: [MediaItem], restriction: String) async throws -> [MediaItem] {
        guard !records.isEmpty else { return [] }
        var query = page(records.count)
        query.itemIDs = records.compactMap(\.id)
        guard let ids = query.itemIDs, !ids.isEmpty else { return [] }
        let live = try await fetch(query, restriction: restriction)
        var byID: [String: MediaItem] = [:]
        for item in ContentRatingGate.filter(live.items) {
            if let id = item.id {
                byID[id] = item
            }
        }
        return records.compactMap { saved in
            guard let id = saved.id, let item = byID[id], saved.type == item.type else { return nil }
            return item
        }
    }

    func search(_ intent: GusSearchIntent) async throws -> [MediaItem] {
        guard intent.unsupported.isEmpty else { return [] }
        let restriction = restrictions
        let terms = intent.keywords + intent.themes + intent.credits.map(\.name) + intent.people
        if intent.favoritesOnly || intent.status != .all {
            // The server owns mutable user data. A new favorite or a just-completed
            // book can change membership hours before the metadata snapshot expires.
            var progress = GusCatalogPaging(), matches: [MediaItem] = []
            repeat {
                var query = page(100, offset: progress.offset)
                query.statusFilter = intent.status
                query.favoritesOnly = intent.favoritesOnly
                let result = try await fetch(query, restriction: restriction)
                matches += ContentRatingGate.filter(result.items).filter { GusLibraryMatching.accepts($0, intent: intent) }
                let complete = try progress.advance(result, requested: query.limit)
                if complete {
                    break
                }
                #if os(watchOS)
                    if progress.offset >= 100 {
                        break
                    }
                #endif
            } while matches.count < 60
            return Array(matches.prefix(60))
        }
        #if os(watchOS)
            var candidates = try await fetch(page(80, sort: .recentlyAdded), restriction: restriction).items
            for term in (terms + intent.characters + intent.genres).prefix(2) {
                candidates += try await fetch(page(30, term: term), restriction: restriction).items
            }
            return MediaPageLoader.unique(ContentRatingGate.filter(candidates)).filter { GusLibraryMatching.accepts($0, intent: intent) }
        #else
            try await refreshCatalog(restriction: restriction, force: false)
            let raw = try await catalog.matching(terms: terms, limit: 60) {
                ContentRatingGate.admitsStored($0) && GusLibraryMatching.accepts($0, intent: intent)
            }
            return try await verified(raw, restriction: restriction).filter { GusLibraryMatching.accepts($0, intent: intent) }
        #endif
    }

    func suggestions(prefix: String) async throws -> [String] {
        guard !GusLibraryMatching.words(prefix).isEmpty else { return [] }
        #if os(watchOS)
            // The Watch search field already has a bounded title read; its rows supply completions.
            return []
        #else
            let restriction = restrictions
            try await refreshCatalog(restriction: restriction, force: false)
            let raw = try await catalog.matching(terms: [prefix], limit: 8) { item in
                ContentRatingGate.admitsStored(item) && !GusLibraryMatching.completions(in: [item], prefix: prefix).isEmpty
            }
            let items = try await verified(raw, restriction: restriction)
            return GusLibraryMatching.completions(in: items, prefix: prefix)
        #endif
    }

    func recommendations(refresh: Bool = false) async throws -> [GusLibraryPick] {
        let restriction = restrictions
        let session = try check(restriction)
        guard session.intelligencePreferences.recommendationsEnabled else { clearRecommendations(); return [] }
        let context = restriction + String(session.intelligencePreferences.cloudEnabled)
        if let pendingShelf, pendingShelf.context == context, !refresh || pendingShelf.refresh {
            let result = try await pendingShelf.task.value
            _ = try check(restriction)
            return result
        }
        pendingShelf?.task.cancel()
        let generation = UUID()
        shelfGeneration = generation
        let task = Task {
            try await self.loadRecommendations(session: session, restriction: restriction, refresh: refresh, generation: generation)
        }
        pendingShelf = (context, refresh, task)
        defer {
            if generation == shelfGeneration {
                pendingShelf = nil
            }
        }
        let result = try await task.value
        _ = try check(restriction)
        return result
    }

    private func loadRecommendations(session: SessionStore, restriction: String, refresh: Bool, generation: UUID) async throws -> [GusLibraryPick] {
        func ensureCurrent() throws {
            _ = try check(restriction)
            guard shelfGeneration == generation, session.intelligencePreferences.recommendationsEnabled else { throw CancellationError() }
        }
        var favorites = page(32)
        favorites.favoritesOnly = true
        var recent = page(32)
        recent.mostRecentlyPlayedFirst = true
        let favoritePage = try await fetch(favorites, restriction: restriction)
        let recentPage = try await fetch(recent, restriction: restriction)
        let seeds = MediaPageLoader.unique(ContentRatingGate.filter(
            favoritePage.items.filter { $0.userData?.isFavorite == true } + recentPage.items.filter { $0.userData?.lastPlayedAt != nil }
        ))
        try ensureCurrent()
        let taste = GusLibraryMatching.Taste(seeds: seeds)
        guard !taste.traits.isEmpty else {
            cachedSeeds = nil
            cachedPicks = []
            return []
        }
        if !refresh, cachedRestrictions == restriction, cachedSeeds == seeds {
            let live = try await verified(cachedPicks.map(\.item), restriction: restriction)
            let checked = taste.ranked(live)
            try ensureCurrent()
            return cachedPicks.compactMap { saved in checked.first { $0.id == saved.id } }
        }

        #if os(watchOS)
            let raw = try await fetch(page(80, sort: .recentlyAdded), restriction: restriction).items
        #else
            try await refreshCatalog(restriction: restriction, force: refresh)
            let raw = try await catalog.matching(terms: taste.traits, limit: 96) { item in
                ContentRatingGate.admitsStored(item) && item.userData?.isFavorite != true &&
                    item.userData?.isWatched != true && !GusLibraryMatching.isInProgress(item)
            }
        #endif
        let preliminary = Array(taste.ranked(ContentRatingGate.filter(raw)).prefix(24))
        let live = try await verified(preliminary.map(\.item), restriction: restriction)
        let shortlist = taste.ranked(live)
        try ensureCurrent()
        guard !shortlist.isEmpty else {
            cachedSeeds = nil
            cachedPicks = []
            return []
        }
        let candidates = shortlist.enumerated().map { index, pick in
            GusRankCandidate(handle: index, title: pick.item.name ?? "", genres: pick.item.genres, summary: pick.item.overview ?? "")
        }
        let ordered: [GusLibraryPick]
        do {
            let order = try await GusIntelligenceModel(session: session).rank(candidates: candidates, traits: taste.traits)
            var selected = Set<Int>()
            ordered = (order + Array(shortlist.indices)).filter { shortlist.indices.contains($0) && selected.insert($0).inserted }.map { shortlist[$0] }
        } catch {
            try ensureCurrent()
            ordered = shortlist
        }
        try ensureCurrent()
        let selected = Array(ordered.prefix(6))
        let final = try taste.ranked(await verified(selected.map(\.item), restriction: restriction))
        try ensureCurrent()
        cachedPicks = selected.compactMap { pick in final.first { $0.id == pick.id } }
        cachedSeeds = seeds
        cachedRestrictions = restriction
        return cachedPicks
    }
}

/// Tracks raw offsets (including restricted rows) and rejects incompletely enumerated snapshots.
struct GusCatalogPaging {
    private(set) var offset = 0
    private var expected: Int?
    private var seen = Set<String>()

    mutating func advance(_ page: MediaItemPage, requested: Int) throws -> Bool {
        let total = try MediaPageLoader.validatedTotal(for: page, startIndex: offset, previousTotal: expected)
        guard expected == nil || expected == total else { throw changedLibrary }
        expected = total
        for item in page.items {
            guard let id = item.id, seen.insert(id).inserted else { throw changedLibrary }
        }
        offset += page.items.count
        if let expected, offset > expected {
            throw changedLibrary
        }
        return offset == expected || page.items.isEmpty || (expected == nil && page.items.count < requested)
    }

    private var changedLibrary: GusError {
        .server(String(localized: "The library changed. Try again.", comment: "Catalog changed during reference recovery"))
    }
}
