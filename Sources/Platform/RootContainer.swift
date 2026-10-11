import SwiftUI

/// Only the visual container changes with width; navigation and players remain session-owned.
struct RootContainer: View {
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(NavigationPreferencesStore.self) private var preferences
    @State private var state = RootNavigationState()
    @Environment(AudioPlaybackCoordinator.self) private var audio
    @SceneStorage("gus.root.selection") private var storedSelection = NavigationSectionPreference.homeID

    var body: some View {
        // Keep the presentation anchor stable when the native tab/split container
        // changes its hosting hierarchy during rotation or window resizing.
        presentationRoot
            .gusContentLinks()
            .gusSessionPlayerHost(state: state, enabled: state.detailItem == nil)
            .gusAudioHost(coordinator: audio, enabled: state.detailItem == nil)
        #if os(iOS) || os(tvOS)
            .gusNowPlaying(coordinator: audio, enabled: state.detailItem == nil)
        #endif
            .task {
                preferences.load(serverID: session.server.id, userID: session.user.id)
                if navigation.routeRequest == 0 {
                    state.selectedSectionID = storedSelection
                } else {
                    state.adopt(navigation.route)
                }
                if state.home == nil {
                    let home = HomeStore(session: session)
                    state.home = home
                    await home.load()
                }
            }
            .onChange(of: navigation.routeRequest) { _, _ in state.adopt(navigation.route) }
            .onChange(of: state.selectedSectionID) { _, id in storedSelection = id }
            .environment(state)
            .environment(audio)
    }

    @ViewBuilder private var presentationRoot: some View {
        #if os(iOS)
            ZStack { platformRoot }
        #else
            // Native toolbar propagation on Vision/Mac relies on the root container.
            platformRoot
        #endif
    }

    @ViewBuilder private var platformRoot: some View {
        #if os(iOS)
            AdaptiveRootView()
        #elseif os(tvOS)
            TabRootView()
        #elseif os(visionOS)
            TabRootView().tabViewStyle(.sidebarAdaptable)
        #else
            SplitRootView()
        #endif
    }
}

#if os(iOS)
    private struct AdaptiveRootView: View {
        @Environment(\.horizontalSizeClass) private var widthClass
        var body: some View {
            if widthClass == .compact {
                TabRootView()
            } else {
                SplitRootView()
            }
        }
    }
#endif

@MainActor private enum RootSections {
    static func resolve(_ preferences: NavigationPreferencesStore, state: RootNavigationState, session: SessionStore) -> [ResolvedNavigationSection] {
        preferences.visibleSections(libraries: state.home?.libraries ?? [], serverID: session.server.id, userID: session.user.id)
    }
}

private struct TabRootView: View {
    @Environment(RootNavigationState.self) private var state
    @Environment(SessionStore.self) private var session
    @Environment(NavigationPreferencesStore.self) private var preferences
    private var sections: [ResolvedNavigationSection] {
        RootSections.resolve(preferences, state: state, session: session)
    }

    private var direct: [ResolvedNavigationSection] {
        #if os(iOS)
            let ids = RootNavigationState.directSectionIDs(sections.map(\.id))
            return sections.filter { ids.contains($0.id) }
        #else
            return sections
        #endif
    }

    private var overflow: [ResolvedNavigationSection] {
        sections.filter { section in !direct.contains { $0.id == section.id } }
    }

    private var selection: Binding<String> {
        Binding(get: {
            direct.contains { $0.id == state.selectedSectionID } ? state.selectedSectionID : RootNavigationState.moreID
        }, set: { state.selectedSectionID = $0 })
    }

    var body: some View {
        TabView(selection: selection) {
            ForEach(direct) { section in
                Tab(value: section.id) { SectionStack(sectionID: section.id) } label: { Label(section.title, systemImage: section.systemImage) }
            }
            if !overflow.isEmpty {
                Tab(value: RootNavigationState.moreID) { SectionStack(sectionID: state.selectedSectionID == RootNavigationState.moreID ? RootNavigationState.moreID : state.selectedSectionID, overflow: overflow) } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
    }
}

private struct SplitRootView: View {
    @Environment(RootNavigationState.self) private var state
    @Environment(SessionStore.self) private var session
    @Environment(NavigationPreferencesStore.self) private var preferences
    private var sections: [ResolvedNavigationSection] {
        RootSections.resolve(preferences, state: state, session: session)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<String?>(get: { state.selectedSectionID }, set: {
                if let id = $0 {
                    state.selectedSectionID = id
                }
            })) {
                ForEach(sections) { section in Label(section.title, systemImage: section.systemImage).tag(section.id) }
            }
            .navigationTitle("A Playa Named Gus")
        } detail: {
            SectionStack(sectionID: state.selectedSectionID)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct SectionStack: View {
    @Environment(RootNavigationState.self) private var state
    @Environment(AudioPlaybackCoordinator.self) private var audio
    @Environment(SessionStore.self) private var session
    @Environment(NavigationPreferencesStore.self) private var preferences
    let sectionID: String
    var overflow: [ResolvedNavigationSection] = []
    private var sections: [ResolvedNavigationSection] {
        RootSections.resolve(preferences, state: state, session: session)
    }

    var body: some View {
        NavigationStack(path: state.pathBinding(for: sectionID)) {
            Group {
                if sectionID == RootNavigationState.moreID {
                    List(overflow.isEmpty ? sections : overflow) { section in
                        Button { state.selectedSectionID = section.id } label: { Label(section.title, systemImage: section.systemImage) }
                    }
                    .navigationTitle("More")
                } else if let section = sections.first(where: { $0.id == sectionID }) {
                    if section.id == NavigationSectionPreference.downloadedID {
                        DownloadedLibraryView()
                    } else {
                        SearchRootView(state: state.searchState(for: section.id, session: session)) {
                            RootSectionDestination(section: section, home: state.home)
                        }
                    }
                } else {
                    HomeView(store: state.home)
                }
            }
            .gusItemDestinations()
            .toolbar {
                if !overflow.isEmpty, sectionID != RootNavigationState.moreID, state.paths[sectionID]?.isEmpty != false {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("More", systemImage: "chevron.backward") { state.selectedSectionID = RootNavigationState.moreID }
                    }
                }
            }
        }
        #if !os(iOS) && !os(tvOS)
        .gusNowPlaying(coordinator: audio, enabled: state.detailItem == nil)
        #endif
    }
}

private struct RootSectionDestination: View {
    let section: ResolvedNavigationSection
    let home: HomeStore?
    var body: some View {
        if section.id == NavigationSectionPreference.homeID {
            HomeView(store: home)
        } else if section.id == NavigationSectionPreference.settingsID {
            SettingsView()
        } else if let category = section.category {
            if category == .livetv {
                LiveTVView()
            } else {
                LibraryGridView(scope: .category(category))
            }
        } else {
            LibrariesLandingView(store: home)
        }
    }
}
