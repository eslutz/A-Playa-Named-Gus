import Foundation
import Observation
import OSLog

/// One entry in the user's customized navigation: a section id plus visibility.
/// `"libraries"` is the fixed Libraries grid; any other id is a library (user view) on
/// the active server. Home and Settings are never represented here — they are fixed at
/// the start and end of navigation by design.
struct NavigationSectionPreference: Codable, Equatable {
    static let librariesID = "libraries"

    var id: String
    var isVisible: Bool
}

/// A preference resolved against the libraries the server actually has right now.
struct ResolvedNavigationSection: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let isVisible: Bool
    /// The backing library item; `nil` for the fixed Libraries grid entry.
    let library: MediaItem?
}

/// Persists per-account navigation customization (order + visibility of the sections
/// between Home and Settings) as JSON in Application Support, mirroring the Up Next
/// store's scoping. Stored ids that no longer exist on the server are dropped at
/// resolution time, and new libraries appear automatically (visible, at the end), so a
/// changed server never breaks navigation.
@MainActor
@Observable
final class NavigationPreferencesStore {
    private(set) var revision = 0

    private var preferencesByScope: [AccountScope: [NavigationSectionPreference]] = [:]
    private var loadedScopes: Set<AccountScope> = []
    private let directory: URL
    private let logger = Logger(category: .home)

    init(directory: URL = AppStorageLocation.appDirectory().appendingPathComponent("Navigation", isDirectory: true)) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load(serverID: String, userID: String) {
        let scope = AccountScope(serverID: serverID, userID: userID)
        guard !loadedScopes.contains(scope) else { return }
        loadedScopes.insert(scope)

        guard let data = try? Data(contentsOf: fileURL(for: scope)) else { return }
        do {
            preferencesByScope[scope] = try JSONDecoder().decode([NavigationSectionPreference].self, from: data)
            revision += 1
        } catch {
            logger.error("Failed to decode navigation preferences: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Merges stored preferences with the libraries the server has right now:
    /// stored order wins, unknown stored ids are dropped, new sections append visible.
    /// The Libraries grid entry is always present.
    func resolvedSections(libraries: [MediaItem], serverID: String, userID: String) -> [ResolvedNavigationSection] {
        let scope = AccountScope(serverID: serverID, userID: userID)
        let stored = preferencesByScope[scope] ?? []
        let libraryByID = Dictionary(uniqueKeysWithValues: libraries.compactMap { item in
            item.id.map { ($0, item) }
        })

        var orderedIDs: [String] = []
        var visibility: [String: Bool] = [:]
        for preference in stored {
            let isKnown = preference.id == NavigationSectionPreference.librariesID || libraryByID[preference.id] != nil
            guard isKnown, !orderedIDs.contains(preference.id) else { continue }
            orderedIDs.append(preference.id)
            visibility[preference.id] = preference.isVisible
        }

        if !orderedIDs.contains(NavigationSectionPreference.librariesID) {
            orderedIDs.insert(NavigationSectionPreference.librariesID, at: 0)
            visibility[NavigationSectionPreference.librariesID] = true
        }
        for library in libraries {
            guard let id = library.id, !orderedIDs.contains(id) else { continue }
            orderedIDs.append(id)
            visibility[id] = true
        }

        return orderedIDs.map { id in
            if id == NavigationSectionPreference.librariesID {
                return ResolvedNavigationSection(
                    id: id,
                    title: String(localized: "Libraries", comment: "Navigation section: the libraries grid"),
                    systemImage: "rectangle.stack",
                    isVisible: visibility[id] ?? true,
                    library: nil
                )
            }
            let library = libraryByID[id]
            return ResolvedNavigationSection(
                id: id,
                title: library?.name ?? id,
                systemImage: library?.librarySymbol ?? "rectangle.stack",
                isVisible: visibility[id] ?? true,
                library: library
            )
        }
    }

    /// The visible sections in display order — what the roots render between Home and
    /// Settings.
    func visibleSections(libraries: [MediaItem], serverID: String, userID: String) -> [ResolvedNavigationSection] {
        resolvedSections(libraries: libraries, serverID: serverID, userID: userID).filter(\.isVisible)
    }

    func setVisibility(_ isVisible: Bool, forSectionID id: String, libraries: [MediaItem], serverID: String, userID: String) {
        updatePreferences(libraries: libraries, serverID: serverID, userID: userID) { preferences in
            guard let index = preferences.firstIndex(where: { $0.id == id }) else { return }
            preferences[index].isVisible = isVisible
        }
    }

    /// Moves a section by `offset` positions (negative = toward Home), shifting the
    /// sections it passes rather than swapping with the landing spot.
    func move(sectionID id: String, by offset: Int, libraries: [MediaItem], serverID: String, userID: String) {
        updatePreferences(libraries: libraries, serverID: serverID, userID: userID) { preferences in
            guard let index = preferences.firstIndex(where: { $0.id == id }) else { return }
            let target = index + offset
            guard preferences.indices.contains(target) else { return }
            let element = preferences.remove(at: index)
            preferences.insert(element, at: target)
        }
    }

    // MARK: - Private

    /// Materializes the current resolved order into stored preferences, applies the
    /// mutation, persists, and bumps the revision.
    private func updatePreferences(
        libraries: [MediaItem],
        serverID: String,
        userID: String,
        mutate: (inout [NavigationSectionPreference]) -> Void
    ) {
        let scope = AccountScope(serverID: serverID, userID: userID)
        var preferences = resolvedSections(libraries: libraries, serverID: serverID, userID: userID)
            .map { NavigationSectionPreference(id: $0.id, isVisible: $0.isVisible) }
        mutate(&preferences)
        preferencesByScope[scope] = preferences
        loadedScopes.insert(scope)
        persist(preferences, scope: scope)
        revision += 1
    }

    private func persist(_ preferences: [NavigationSectionPreference], scope: AccountScope) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(preferences)
            try data.write(to: fileURL(for: scope), options: .atomic)
        } catch {
            logger.error("Failed to save navigation preferences: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fileURL(for scope: AccountScope) -> URL {
        directory.appendingPathComponent("\(scope.storageKey).json")
    }
}
