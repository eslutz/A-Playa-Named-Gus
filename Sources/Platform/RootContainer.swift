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
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack {
                    HomeView()
                        .gusItemDestinations()
                }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }
}

private enum SidebarItem: Hashable {
    case home
    case settings
    case library(String)
}

/// Split-view root (iPad, macOS, visionOS).
private struct SplitRootView: View {

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
            .navigationTitle("Gus")
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            #endif
        } detail: {
            NavigationStack {
                detail
                    .gusItemDestinations()
            }
        }
        .navigationSplitViewStyle(.balanced)
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
