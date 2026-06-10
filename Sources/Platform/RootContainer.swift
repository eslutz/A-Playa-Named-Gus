import SwiftUI

/// Signed-in root, with all platform divergence in one place.
///
/// - iPhone (compact) & tvOS → `TabView` (focus engine on tvOS).
/// - iPad / macOS → `NavigationSplitView` (sidebar = sections).
/// - visionOS → `.sidebarAdaptable` `TabView` for the native floating sidebar style.
///
/// Navigation is user-customizable: Home is fixed first and Settings fixed last, while
/// the sections between them (the Libraries grid plus each server library) follow the
/// per-account order/visibility in `NavigationPreferencesStore`.
struct RootContainer: View {
    var body: some View {
        #if os(tvOS)
            TabRootView()
        #elseif os(visionOS)
            VisionSidebarRootView()
        #elseif os(macOS)
            SplitRootView()
        #else
            AdaptiveRootView()
        #endif
    }
}

#if os(iOS)
    /// iOS/iPadOS: compact width → tabs; regular width → split view.
    private struct AdaptiveRootView: View {
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        var body: some View {
            if horizontalSizeClass == .compact {
                TabRootView()
            } else {
                SplitRootView()
            }
        }
    }
#endif

/// Selection identity shared by every root: fixed Home/Settings plus dynamic sections.
private enum RootSection: Hashable {
    case home
    case section(String)
    case settings

    /// String key used with `SceneStorage` to restore selection across launches.
    var sceneKey: String {
        switch self {
        case .home: return "home"
        case .settings: return "settings"
        case let .section(id): return "section:\(id)"
        }
    }

    init?(sceneKey key: String) {
        switch key {
        case "home":
            self = .home
        case "settings":
            self = .settings
        case "libraries":
            // Legacy fixed-sidebar key from before navigation customization.
            self = .section(NavigationSectionPreference.librariesID)
        default:
            if key.hasPrefix("section:") {
                self = .section(String(key.dropFirst("section:".count)))
            } else if key.hasPrefix("library:") {
                self = .section(NavigationSectionPreference.librariesID)
            } else {
                return nil
            }
        }
    }

    /// Maps a fixed app route onto a selection; `.search` has no selection of its own.
    init?(route: AppRoute) {
        switch route {
        case .home:
            self = .home
        case .libraries:
            self = .section(NavigationSectionPreference.librariesID)
        case .settings:
            self = .settings
        case .search:
            return nil
        }
    }
}

/// Renders one customizable section: the Libraries grid, a Live TV library, or a
/// media library grid.
private struct SectionDestination: View {
    let section: ResolvedNavigationSection
    let home: HomeStore?

    var body: some View {
        if let library = section.library {
            if library.collectionType == .livetv {
                LiveTVView()
            } else {
                LibraryGridView(library: library)
            }
        } else {
            LibrariesLandingView(store: home)
        }
    }
}

/// Tab-based root (compact iPhone, tvOS).
private struct TabRootView: View {
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(SessionStore.self) private var session
    @Environment(NavigationPreferencesStore.self) private var navigationPreferences
    @State private var home: HomeStore?
    @State private var selection: RootSection = .home

    private var sections: [ResolvedNavigationSection] {
        navigationPreferences.visibleSections(
            libraries: home?.libraries ?? [],
            serverID: session.server.id,
            userID: session.user.id
        )
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: RootSection.home) {
                NavigationStack {
                    SearchRootView {
                        HomeView(store: home)
                    }
                    .gusItemDestinations()
                }
            }
            ForEach(sections) { section in
                Tab(value: RootSection.section(section.id)) {
                    NavigationStack {
                        SearchRootView {
                            SectionDestination(section: section, home: home)
                        }
                        .gusItemDestinations()
                    }
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
            Tab("Settings", systemImage: "gearshape", value: RootSection.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .onAppear {
            // Adopt a route set before this view mounted (cold-launch deep links,
            // Top Shelf actions, --gus-route); onChange alone would miss it.
            adopt(route: navigation.route)
        }
        .onChange(of: selection) { _, newSelection in
            // Only fixed destinations round-trip into the navigation model; selecting
            // a dynamic library tab is not a route change.
            switch newSelection {
            case .home where navigation.route != .home:
                navigation.open(.home)
            case .settings where navigation.route != .settings:
                navigation.open(.settings)
            case .section(NavigationSectionPreference.librariesID) where navigation.route != .libraries:
                navigation.open(.libraries)
            default:
                break
            }
        }
        .onChange(of: navigation.route) { _, route in
            adopt(route: route)
        }
        .task {
            navigationPreferences.load(serverID: session.server.id, userID: session.user.id)
            if home == nil {
                let store = HomeStore(session: session)
                home = store
                await store.load()
            }
        }
    }

    private func adopt(route: AppRoute) {
        guard let routed = RootSection(route: route) else { return }
        // A hidden Libraries section falls back to Home rather than a blank tab.
        if case let .section(id) = routed, !sections.contains(where: { $0.id == id }) {
            selection = .home
            return
        }
        selection = routed
    }
}

#if os(visionOS)
    /// visionOS-native root using the system sidebar tab presentation.
    private struct VisionSidebarRootView: View {
        @Environment(AppNavigationModel.self) private var navigation
        @Environment(SessionStore.self) private var session
        @Environment(NavigationPreferencesStore.self) private var navigationPreferences
        @State private var home: HomeStore?
        @State private var selection: RootSection = .home
        @SceneStorage("gus.vision.sidebar.selection") private var storedSelectionKey: String = "home"

        private var sections: [ResolvedNavigationSection] {
            navigationPreferences.visibleSections(
                libraries: home?.libraries ?? [],
                serverID: session.server.id,
                userID: session.user.id
            )
        }

        var body: some View {
            TabView(selection: $selection) {
                Tab("Home", systemImage: "house", value: RootSection.home) {
                    NavigationStack {
                        SearchRootView {
                            HomeView(store: home)
                        }
                        .gusItemDestinations()
                    }
                }

                ForEach(sections) { section in
                    Tab(value: RootSection.section(section.id)) {
                        NavigationStack {
                            SearchRootView {
                                SectionDestination(section: section, home: home)
                            }
                            .gusItemDestinations()
                        }
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }

                Tab("Settings", systemImage: "gearshape", value: RootSection.settings) {
                    NavigationStack {
                        SettingsView()
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .ornament(attachmentAnchor: .scene(.leading), contentAlignment: .top) {
                if VisionSidebarLayout.environmentControlPlacement == .leadingSceneOrnament {
                    VisionEnvironmentSidebarButton()
                        .padding(.top, VisionSidebarLayout.environmentControlTopPadding)
                        .padding(.trailing, VisionSidebarLayout.environmentControlTrailingPadding)
                }
            }
            .onAppear {
                // A route set before mount (cold-launch deep link, --gus-route) wins
                // over the restored scene selection.
                if navigation.route != .home, let routed = RootSection(route: navigation.route) {
                    selection = routed
                } else if let restored = RootSection(sceneKey: storedSelectionKey) {
                    selection = restored
                }
            }
            .onChange(of: selection) { _, newSelection in
                storedSelectionKey = newSelection.sceneKey
                switch newSelection {
                case .home where navigation.route != .home:
                    navigation.open(.home)
                case .settings where navigation.route != .settings:
                    navigation.open(.settings)
                case .section(NavigationSectionPreference.librariesID) where navigation.route != .libraries:
                    navigation.open(.libraries)
                default:
                    break
                }
            }
            .onChange(of: navigation.route) { _, route in
                if let routed = RootSection(route: route) {
                    selection = routed
                }
            }
            .task {
                navigationPreferences.load(serverID: session.server.id, userID: session.user.id)
                if home == nil {
                    let store = HomeStore(session: session)
                    home = store
                    await store.load()
                }
            }
        }
    }
#endif

/// Split-view root (iPad, macOS).
private struct SplitRootView: View {
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(SessionStore.self) private var session
    @Environment(NavigationPreferencesStore.self) private var navigationPreferences
    @State private var home: HomeStore?
    @State private var selection: RootSection? = .home
    /// Persists the active sidebar row across app launches via SwiftUI scene restoration.
    @SceneStorage("gus.sidebar.selection") private var storedSelectionKey: String = "home"

    private var sections: [ResolvedNavigationSection] {
        navigationPreferences.visibleSections(
            libraries: home?.libraries ?? [],
            serverID: session.server.id,
            userID: session.user.id
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Home", systemImage: "house").tag(RootSection.home)
                ForEach(sections) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(RootSection.section(section.id))
                }
                Label("Settings", systemImage: "gearshape").tag(RootSection.settings)
            }
            .navigationTitle(Text("A Playa Named Gus", comment: "App name"))
            #if os(macOS)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            #endif
        } detail: {
            NavigationStack {
                SearchRootView {
                    detail
                }
                .gusItemDestinations()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem {
                Button {
                    navigation.open(.search)
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            storedSelectionKey = item.sceneKey
            switch item {
            case .home where navigation.route != .home:
                navigation.open(.home)
            case .settings where navigation.route != .settings:
                navigation.open(.settings)
            case .section(NavigationSectionPreference.librariesID) where navigation.route != .libraries:
                navigation.open(.libraries)
            default:
                break
            }
        }
        .onChange(of: navigation.route) { _, route in
            if let routed = RootSection(route: route) {
                selection = routed
            }
        }
        .onAppear {
            // A route set before mount (cold-launch deep link, --gus-route) wins over
            // the sidebar selection restored from the previous session.
            if navigation.route != .home, let routed = RootSection(route: navigation.route) {
                selection = routed
            } else if let restored = RootSection(sceneKey: storedSelectionKey) {
                selection = restored
            }
        }
        .task {
            navigationPreferences.load(serverID: session.server.id, userID: session.user.id)
            if home == nil {
                let store = HomeStore(session: session)
                home = store
                await store.load()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .settings:
            SettingsView()
        case let .section(id):
            if let section = sections.first(where: { $0.id == id }) {
                SectionDestination(section: section, home: home)
            } else {
                // The stored selection refers to a hidden/removed section; sections may
                // also still be loading — Home is the graceful fallback either way.
                HomeView(store: home)
            }
        case .home, .none:
            HomeView(store: home)
        }
    }
}
