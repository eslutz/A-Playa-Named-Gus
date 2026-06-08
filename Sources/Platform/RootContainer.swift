import JellyfinAPI
import SwiftUI

/// Signed-in root, with all platform divergence in one place.
///
/// - iPhone (compact) & tvOS → `TabView` (focus engine on tvOS).
/// - iPad / macOS → `NavigationSplitView` (sidebar = libraries).
/// - visionOS → `.sidebarAdaptable` `TabView` for the native floating sidebar style.
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

/// Tab-based root (compact iPhone, tvOS).
private struct TabRootView: View {
    @Environment(AppNavigationModel.self) private var navigation
    @State private var selection: AppRoute = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: AppRoute.home) {
                NavigationStack {
                    SearchRootView {
                        HomeView()
                    }
                    .gusItemDestinations()
                }
            }
            Tab("Libraries", systemImage: "rectangle.stack", value: AppRoute.libraries) {
                NavigationStack {
                    SearchRootView {
                        LibrariesLandingView()
                    }
                    .gusItemDestinations()
                }
            }
            Tab("Settings", systemImage: "gearshape", value: AppRoute.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .onChange(of: selection) { _, route in
            if navigation.route != route {
                navigation.open(route)
            }
        }
        .onChange(of: navigation.route) { _, route in
            selection = route
        }
    }
}

private enum SidebarItem: Hashable {
    case home
    case libraries
    case settings

    /// String key used with `SceneStorage` to restore sidebar selection across launches.
    var sceneKey: String {
        switch self {
        case .home: return "home"
        case .libraries: return "libraries"
        case .settings: return "settings"
        }
    }

    init?(sceneKey key: String) {
        switch key {
        case "home":
            self = .home
        case "libraries":
            self = .libraries
        case "settings":
            self = .settings
        default:
            if key.hasPrefix("library:") {
                self = .libraries
            } else {
                return nil
            }
        }
    }
}

#if os(visionOS)
    /// visionOS-native root using the system sidebar tab presentation.
    private struct VisionSidebarRootView: View {
        @Environment(AppNavigationModel.self) private var navigation
        @Environment(SessionStore.self) private var session
        @State private var home: HomeStore?
        @State private var selection: SidebarItem = .home
        @SceneStorage("gus.vision.sidebar.selection") private var storedSelectionKey: String = "home"

        var body: some View {
            TabView(selection: $selection) {
                Tab("Home", systemImage: "house", value: SidebarItem.home) {
                    NavigationStack {
                        SearchRootView {
                            HomeView()
                        }
                        .gusItemDestinations()
                    }
                }

                Tab("Libraries", systemImage: "rectangle.stack", value: SidebarItem.libraries) {
                    NavigationStack {
                        SearchRootView {
                            LibrariesLandingView(store: home)
                        }
                        .gusItemDestinations()
                    }
                }

                Tab("Settings", systemImage: "gearshape", value: SidebarItem.settings) {
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
                if let restored = SidebarItem(sceneKey: storedSelectionKey) {
                    selection = restored
                }
            }
            .onChange(of: selection) { _, item in
                storedSelectionKey = item.sceneKey
                switch item {
                case .home:
                    navigation.open(.home)
                case .libraries:
                    navigation.open(.libraries)
                case .settings:
                    navigation.open(.settings)
                }
            }
            .onChange(of: navigation.route) { _, route in
                switch route {
                case .home:
                    selection = .home
                case .libraries:
                    selection = .libraries
                case .settings:
                    selection = .settings
                case .search:
                    break
                }
            }
            .task {
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
    @State private var home: HomeStore?
    @State private var selection: SidebarItem? = .home
    /// Persists the active sidebar row across app launches via SwiftUI scene restoration.
    @SceneStorage("gus.sidebar.selection") private var storedSelectionKey: String = "home"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Home", systemImage: "house").tag(SidebarItem.home)
                Label("Libraries", systemImage: "rectangle.stack").tag(SidebarItem.libraries)
                Label("Settings", systemImage: "gearshape").tag(SidebarItem.settings)
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
        #if os(visionOS)
        .glassBackground()
        #endif
        .onChange(of: selection) { _, item in
            switch item {
            case .home:
                navigation.open(.home)
            case .libraries:
                navigation.open(.libraries)
            case .settings:
                navigation.open(.settings)
            case .none:
                break
            }
        }
        .onChange(of: navigation.route) { _, route in
            switch route {
            case .home:
                selection = .home
            case .libraries:
                selection = .libraries
            case .settings:
                selection = .settings
            case .search:
                break
            }
        }
        .onAppear {
            // Restore sidebar selection from the previous session on launch.
            if let restored = SidebarItem(sceneKey: storedSelectionKey) {
                selection = restored
            }
        }
        .onChange(of: selection) { _, newItem in
            if let newItem {
                storedSelectionKey = newItem.sceneKey
            }
        }
        .task {
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
        case .libraries:
            LibrariesLandingView(store: home)
        case .home, .none:
            HomeView()
        }
    }
}
