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
/// Required ids (`"home"`, `"libraries"`, `"settings"`) stay visible; category ids
/// such as `"category.movies"` represent consolidated media categories across every
/// matching library on the active server.
struct NavigationSectionPreference: Codable, Equatable {
    static let homeID = "home"
    static let librariesID = "libraries"
    static let settingsID = "settings"

    var id: String
    /// `nil` means the section follows the server-derived default: categories with
    /// content are visible, empty categories are hidden. A non-nil value is the user's
    /// explicit show/hide choice.
    var isVisible: Bool?
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
    /// Home stays fixed; every other visible/hidden section can be reordered within its
    /// current list.
    let canMove: Bool
    /// Only category sections can be hidden. Home, Libraries, and Settings remain visible.
    let canHide: Bool
}

/// Persists per-account navigation customization as JSON in Application Support,
/// mirroring the Up Next store's scoping. All known category sections are resolvable:
/// categories with matching libraries default into Sections, while empty categories
/// default into Hidden until the user shows them or content appears later.
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

    /// Merges stored preferences with the sections the app knows about. Stored order wins,
    /// unknown stored ids are dropped, and missing ids are appended in the native default
    /// order. Hidden rows are returned after visible rows so the editor can present
    /// Sections and Hidden as separate lists without losing each row's ordering.
    func resolvedSections(libraries: [MediaItem], serverID: String, userID: String) -> [ResolvedNavigationSection] {
        let scope = AccountScope(serverID: serverID, userID: userID)
        let stored = preferencesByScope[scope] ?? []
        let availableCategories = Set(NavigationCategory.available(in: libraries))
        let categoryByID = Dictionary(uniqueKeysWithValues: NavigationCategory.allCases.map { ($0.id, $0) })
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
            let isKnown = isKnownSectionID(preference.id)
            guard isKnown, !orderedIDs.contains(preference.id) else { continue }
            orderedIDs.append(preference.id)
            if let isVisible = preference.isVisible {
                visibility[preference.id] = isVisible
            }
        }

        for id in defaultSectionIDs(availableCategories: availableCategories) where !orderedIDs.contains(id) {
            orderedIDs.append(id)
        }

        orderedIDs.removeAll { $0 == NavigationSectionPreference.homeID }
        orderedIDs.insert(NavigationSectionPreference.homeID, at: 0)

        let sections = orderedIDs.compactMap { id -> ResolvedNavigationSection? in
            section(
                for: id,
                visibility: visibility,
                availableCategories: availableCategories,
                categoryByID: categoryByID,
                librariesByCategory: librariesByCategory
            )
        }

        return sections.filter(\.isVisible) + sections.filter { !$0.isVisible }
    }

    /// The visible sections in display order — what the roots render.
    func visibleSections(libraries: [MediaItem], serverID: String, userID: String) -> [ResolvedNavigationSection] {
        resolvedSections(libraries: libraries, serverID: serverID, userID: userID).filter(\.isVisible)
    }

    /// Hidden category sections in display order for the navigation editor.
    func hiddenSections(libraries: [MediaItem], serverID: String, userID: String) -> [ResolvedNavigationSection] {
        resolvedSections(libraries: libraries, serverID: serverID, userID: userID).filter { !$0.isVisible }
    }

    func setVisibility(_ isVisible: Bool, forSectionID id: String, libraries: [MediaItem], serverID: String, userID: String) {
        let section = resolvedSections(libraries: libraries, serverID: serverID, userID: userID)
            .first { $0.id == id }
        guard section?.canHide == true else { return }

        updatePreferences(libraries: libraries, serverID: serverID, userID: userID) { preferences in
            guard let index = preferences.firstIndex(where: { $0.id == id }) else { return }
            preferences[index].isVisible = isVisible
        }
    }

    /// Moves a section by `offset` positions (negative = toward Home), shifting the
    /// sections it passes rather than swapping with the landing spot.
    func move(sectionID id: String, by offset: Int, libraries: [MediaItem], serverID: String, userID: String) {
        let sections = resolvedSections(libraries: libraries, serverID: serverID, userID: userID)
        guard let section = sections.first(where: { $0.id == id }), section.canMove else { return }

        let group = sections.filter { $0.isVisible == section.isVisible && $0.canMove }.map(\.id)
        guard let index = group.firstIndex(of: id) else { return }
        let target = index + offset
        guard group.indices.contains(target) else { return }

        var orderedGroup = group
        let element = orderedGroup.remove(at: index)
        orderedGroup.insert(element, at: target)

        updatePreferences(libraries: libraries, serverID: serverID, userID: userID) { preferences in
            applyOrder(orderedGroup, to: &preferences)
        }
    }

    func moveVisibleSections(from source: IndexSet, to destination: Int, libraries: [MediaItem], serverID: String, userID: String) {
        let visible = visibleSections(libraries: libraries, serverID: serverID, userID: userID)
        guard let sourceIndex = source.first,
              visible.indices.contains(sourceIndex),
              visible[sourceIndex].canMove
        else { return }

        var reordered = visible
        let element = reordered.remove(at: sourceIndex)
        let adjustedDestination = destination > sourceIndex ? destination - 1 : destination
        let boundedDestination = min(max(adjustedDestination, 1), reordered.count)
        reordered.insert(element, at: boundedDestination)
        let orderedMovableIDs = reordered.filter(\.canMove).map(\.id)

        updatePreferences(libraries: libraries, serverID: serverID, userID: userID) { preferences in
            applyOrder(orderedMovableIDs, to: &preferences)
        }
    }

    // MARK: - Private

    private func isKnownSectionID(_ id: String) -> Bool {
        id == NavigationSectionPreference.homeID ||
            id == NavigationSectionPreference.librariesID ||
            id == NavigationSectionPreference.settingsID ||
            NavigationCategory(id: id) != nil
    }

    private func defaultSectionIDs(availableCategories: Set<NavigationCategory>) -> [String] {
        let visibleCategories = NavigationCategory.allCases.filter { availableCategories.contains($0) }.map(\.id)
        let hiddenCategories = NavigationCategory.allCases.filter { !availableCategories.contains($0) }.map(\.id)

        return [NavigationSectionPreference.homeID, NavigationSectionPreference.librariesID] +
            visibleCategories +
            [NavigationSectionPreference.settingsID] +
            hiddenCategories
    }

    private func section(
        for id: String,
        visibility: [String: Bool],
        availableCategories: Set<NavigationCategory>,
        categoryByID: [String: NavigationCategory],
        librariesByCategory: [NavigationCategory: [MediaItem]]
    ) -> ResolvedNavigationSection? {
        switch id {
        case NavigationSectionPreference.homeID:
            return ResolvedNavigationSection(
                id: id,
                title: String(localized: "Home", comment: "Navigation section: home"),
                systemImage: "house",
                isVisible: true,
                category: nil,
                libraries: [],
                canMove: false,
                canHide: false
            )
        case NavigationSectionPreference.librariesID:
            return ResolvedNavigationSection(
                id: id,
                title: String(localized: "Libraries", comment: "Navigation section: the libraries grid"),
                systemImage: "rectangle.stack",
                isVisible: true,
                category: nil,
                libraries: [],
                canMove: true,
                canHide: false
            )
        case NavigationSectionPreference.settingsID:
            return ResolvedNavigationSection(
                id: id,
                title: String(localized: "Settings", comment: "Settings navigation label"),
                systemImage: "gearshape",
                isVisible: true,
                category: nil,
                libraries: [],
                canMove: true,
                canHide: false
            )
        default:
            guard let category = categoryByID[id] else { return nil }
            return ResolvedNavigationSection(
                id: id,
                title: category.title,
                systemImage: category.systemImage,
                isVisible: visibility[id] ?? availableCategories.contains(category),
                category: category,
                libraries: librariesByCategory[category] ?? [],
                canMove: true,
                canHide: true
            )
        }
    }

    private func applyOrder(_ orderedIDs: [String], to preferences: inout [NavigationSectionPreference]) {
        let orderedSet = Set(orderedIDs)
        let preferenceByID = Dictionary(uniqueKeysWithValues: preferences.map { ($0.id, $0) })
        var nextIDs = orderedIDs.makeIterator()

        for index in preferences.indices where orderedSet.contains(preferences[index].id) {
            guard let nextID = nextIDs.next(), let preference = preferenceByID[nextID] else { return }
            preferences[index] = preference
        }
    }

    /// Materializes the current resolved order into stored preferences, applies the
    /// mutation, persists, and bumps the revision.
    private func updatePreferences(
        libraries: [MediaItem],
        serverID: String,
        userID: String,
        mutate: (inout [NavigationSectionPreference]) -> Void
    ) {
        let scope = AccountScope(serverID: serverID, userID: userID)
        let storedByID = Dictionary(uniqueKeysWithValues: (preferencesByScope[scope] ?? []).map { ($0.id, $0) })
        var preferences = resolvedSections(libraries: libraries, serverID: serverID, userID: userID)
            .map { section in
                NavigationSectionPreference(id: section.id, isVisible: storedByID[section.id]?.isVisible)
            }
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
