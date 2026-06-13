import Foundation
import Observation
import OSLog

enum NavigationCategory: String, CaseIterable, Codable, Hashable, Identifiable {
    case movies
    case tvshows
    case music
    case books
    case photos
    case livetv

    var id: String {
        "category.\(rawValue)"
    }

    var title: String {
        switch self {
        case .movies:
            return String(localized: "Movies", comment: "Navigation category: movies")
        case .tvshows:
            return String(localized: "Shows", comment: "Navigation category: TV shows")
        case .music:
            return String(localized: "Music", comment: "Navigation category: music")
        case .books:
            return String(localized: "Books", comment: "Navigation category: books")
        case .photos:
            return String(localized: "Photos", comment: "Navigation category: photos")
        case .livetv:
            return String(localized: "Live TV", comment: "Navigation category: live TV")
        }
    }

    var systemImage: String {
        switch self {
        case .movies:
            return "film"
        case .tvshows:
            return "tv"
        case .music:
            return "music.note"
        case .books:
            return "book"
        case .photos:
            return "photo"
        case .livetv:
            return "antenna.radiowaves.left.and.right"
        }
    }

    var collectionType: MediaCollectionType {
        switch self {
        case .movies:
            return .movies
        case .tvshows:
            return .tvshows
        case .music:
            return .music
        case .books:
            return .books
        case .photos:
            return .photos
        case .livetv:
            return .livetv
        }
    }

    var includeTypes: [MediaItemType] {
        switch self {
        case .movies:
            return [.movie]
        case .tvshows:
            return [.series]
        case .music:
            return [.musicArtist, .musicAlbum, .playlist]
        case .books:
            return [.book, .audioBook]
        case .photos:
            return [.photo]
        case .livetv:
            return [.liveChannel, .recording]
        }
    }

    init?(id: String) {
        guard id.hasPrefix("category.") else { return nil }
        self.init(rawValue: String(id.dropFirst("category.".count)))
    }

    static func available(in libraries: [MediaItem]) -> [NavigationCategory] {
        let collectionTypes = Set(libraries.compactMap(\.collectionType))
        return allCases.filter { collectionTypes.contains($0.collectionType) }
    }
}

/// One entry in the user's customized navigation: a section id plus visibility.
/// `"libraries"` is the fixed individual Libraries grid; category ids such as
/// `"category.movies"` represent consolidated media categories across every matching
/// library on the active server. Home and Settings are fixed at the start and end.
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
    /// The backing category; `nil` for the fixed Libraries grid entry.
    let category: NavigationCategory?
    /// The server libraries represented by this section. Empty for the fixed Libraries
    /// grid, which intentionally surfaces all individual libraries itself.
    let libraries: [MediaItem]
}

/// Persists per-account navigation customization (order + visibility of the sections
/// between Home and Settings) as JSON in Application Support, mirroring the Up Next
/// store's scoping. Stored ids that no longer exist on the server are dropped at
/// resolution time, and new categories appear automatically (visible, at the end), so a
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

    /// Merges stored preferences with the categories the server has right now: stored
    /// order wins, unknown stored ids are dropped, new sections append visible. The
    /// individual Libraries grid entry is always present.
    func resolvedSections(libraries: [MediaItem], serverID: String, userID: String) -> [ResolvedNavigationSection] {
        let scope = AccountScope(serverID: serverID, userID: userID)
        let stored = preferencesByScope[scope] ?? []
        let categories = NavigationCategory.available(in: libraries)
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let librariesByCategory = Dictionary(grouping: libraries.compactMap { library -> (NavigationCategory, MediaItem)? in
            guard let collectionType = library.collectionType,
                  let category = NavigationCategory.allCases.first(where: { $0.collectionType == collectionType })
            else { return nil }
            return (category, library)
        }) { pair in
            pair.0
        }.mapValues { pairs in
            pairs.map(\.1)
        }

        var orderedIDs: [String] = []
        var visibility: [String: Bool] = [:]
        for preference in stored {
            let isKnown = preference.id == NavigationSectionPreference.librariesID || categoryByID[preference.id] != nil
            guard isKnown, !orderedIDs.contains(preference.id) else { continue }
            orderedIDs.append(preference.id)
            visibility[preference.id] = preference.isVisible
        }

        if !orderedIDs.contains(NavigationSectionPreference.librariesID) {
            orderedIDs.insert(NavigationSectionPreference.librariesID, at: 0)
            visibility[NavigationSectionPreference.librariesID] = true
        }
        for category in categories {
            guard !orderedIDs.contains(category.id) else { continue }
            orderedIDs.append(category.id)
            visibility[category.id] = true
        }

        return orderedIDs.map { id in
            if id == NavigationSectionPreference.librariesID {
                return ResolvedNavigationSection(
                    id: id,
                    title: String(localized: "Libraries", comment: "Navigation section: the libraries grid"),
                    systemImage: "rectangle.stack",
                    isVisible: visibility[id] ?? true,
                    category: nil,
                    libraries: []
                )
            }
            let category = categoryByID[id]
            return ResolvedNavigationSection(
                id: id,
                title: category?.title ?? id,
                systemImage: category?.systemImage ?? "rectangle.stack",
                isVisible: visibility[id] ?? true,
                category: category,
                libraries: category.flatMap { librariesByCategory[$0] } ?? []
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
