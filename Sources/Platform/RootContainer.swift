import JellyfinAPI
import SwiftUI

/// Signed-in root, with all platform divergence in one place.
///
/// - iPhone (compact) & tvOS → `TabView` (focus engine on tvOS).
/// - iPad / macOS / visionOS → `NavigationSplitView` (sidebar = libraries).
struct RootContainer: View {
    var body: some View {
        #if os(tvOS)
            TabRootView()
        #elseif os(macOS) || os(visionOS)
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
            #if os(tvOS)
                Tab("Search", systemImage: "magnifyingglass", value: AppRoute.search) {
                    NavigationStack {
                        SearchView()
                            .gusItemDestinations()
                    }
                }
            #endif
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
            selection = tabSelection(for: route)
        }
    }

    private func tabSelection(for route: AppRoute) -> AppRoute {
        #if os(tvOS)
            return route
        #else
            return route == .search ? .home : route
        #endif
    }
}

private enum SidebarItem: Hashable {
    case home
    case settings
    case library(String)
}

/// Split-view root (iPad, macOS, visionOS).
private struct SplitRootView: View {
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(SessionStore.self) private var session
    @State private var home: HomeStore?
    @State private var selection: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Home", systemImage: "house").tag(SidebarItem.home)

                Section("Libraries") {
                    if let home {
                        ForEach(home.libraries, id: \.id) { library in
                            Label(library.name ?? "Library", systemImage: library.librarySymbol)
                                .tag(SidebarItem.library(library.id ?? ""))
                        }
                    }
                }

                Label("Settings", systemImage: "gearshape").tag(SidebarItem.settings)
            }
            .navigationTitle(Text("Gus", comment: "App name"))
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
            ToolbarItemGroup {
                Button {
                    navigation.open(.home)
                } label: {
                    Label("Home", systemImage: "house")
                }

                Button {
                    navigation.open(.search)
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }

                Button {
                    navigation.open(.settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
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
            case .settings:
                navigation.open(.settings)
            case .library, .none:
                break
            }
        }
        .onChange(of: navigation.route) { _, route in
            switch route {
            case .home, .search:
                selection = .home
            case .settings:
                selection = .settings
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
        case let .library(id):
            if let library = home?.libraries.first(where: { $0.id == id }) {
                LibraryGridView(library: library)
            } else {
                ContentUnavailableView("Select a Library", systemImage: "rectangle.stack")
            }
        case .home, .none:
            HomeView()
        }
    }
}
