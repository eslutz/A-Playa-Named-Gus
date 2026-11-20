import SwiftUI

/// Only the visual container changes with width; navigation and players remain session-owned.
struct RootContainer: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var app
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(NavigationPreferencesStore.self) private var preferences
    @State private var state: RootNavigationState
    @Environment(AudioPlaybackCoordinator.self) private var audio
    @SceneStorage("gus.root.selection") private var storedSelection = NavigationSectionPreference.homeID

    init(searchHistory: SearchHistoryStore) {
        _state = State(initialValue: RootNavigationState(searchHistory: searchHistory))
    }

    var body: some View {
        // Keep the presentation anchor stable when the native tab/split container
        // changes its hosting hierarchy during rotation or window resizing.
        presentationRoot
            // Keep the editor and its draft alive while tab/split children are replaced.
            .gusTVTask(isPresented: Bindable(state).isProfilePresented) {
                NavigationStack { UserProfileView() }
            }
            .gusContentLinks()
            .task(id: state.selectedSectionID == RootNavigationState.searchID ? state.globalSearch.related?.lookupID : nil) {
                if state.selectedSectionID == RootNavigationState.searchID, let related = state.globalSearch.related {
                    await related.resolve(session: session)
                    guard !Task.isCancelled, state.globalSearch.related === related, let match = related.resolved else { return }
                    let pages = state.libraryStore(for: .related(match), session: session, searchResults: related)
                    if pages.state == .idle || pages.state == .loading {
                        await pages.load(superseding: true)
                    }
                }
            }
            .gusSessionPlayerHost(state: state, enabled: state.detailItem == nil)
            .gusAudioHost(coordinator: audio, enabled: state.detailItem == nil)
        #if os(iOS) || os(tvOS) || os(macOS)
            .gusNowPlaying(coordinator: audio, enabled: state.detailItem == nil)
        #endif
            .task {
                preferences.load(serverID: session.server.id, userID: session.user.id)
                if navigation.routeRequest == 0 {
                    state.selectSection(storedSelection)
                } else {
                    state.adopt(navigation.route)
                }
                if navigation.searchFocusRequest > 0 {
                    focusSearch()
                }
                if state.home == nil {
                    let home = HomeStore(session: session)
                    state.home = home
                    await home.load()
                }
            }
            .task {
                await session.profile.load()
                app.synchronizeProfile(from: session)
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await preferences.refreshBookFormats(session: session)
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await session.profile.load()
                app.synchronizeProfile(from: session)
                session.references.beginRefresh()
                await state.refreshCachedContent()
            }
            .onChange(of: navigation.searchFocusRequest) { _, request in
                if request > 0 {
                    focusSearch()
                }
            }
            .onChange(of: navigation.routeRequest) { _, _ in state.adopt(navigation.route) }
            .onChange(of: state.selectedSectionID) { _, id in storedSelection = id }
            .environment(state)
            .environment(audio)
            .environment(session.seerr)
            .task { await session.seerr.restore() }
    }

    private func focusSearch() {
        switch state.selectedSectionID {
        case NavigationSectionPreference.discoverID, NavigationSectionPreference.downloadedID:
            state.paths[state.selectedSectionID] = NavigationPath()
        default:
            state.selectSection(RootNavigationState.searchID)
            state.paths[RootNavigationState.searchID] = NavigationPath()
            state.globalSearch.typed.isPresented = true
        }
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
                .tabViewStyle(.sidebarAdaptable)
                .gusTVAccountMenu()
                .gusTVBrowsingBackdrop()
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
            } else if DeviceIdentity.usesIPadPresentation {
                IPadSplitRootView()
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
            let ids = RootNavigationState.iPhoneDirectSectionIDs(sections.map(\.id), usesSavedOrder: preferences.hasSavedPreferences(serverID: session.server.id, userID: session.user.id))
            return ids.compactMap { id in sections.first { $0.id == id } }
        #elseif os(visionOS)
            let ids = RootNavigationState.visionDirectSectionIDs(sections.map(\.id))
            return ids.compactMap { id in sections.first { $0.id == id } }
        #else
            return sections
        #endif
    }

    private var overflow: [ResolvedNavigationSection] {
        sections.filter { section in !direct.contains { $0.id == section.id } }
    }

    private var selection: Binding<String> {
        Binding(get: {
            #if os(visionOS)
                // Keep the native selection valid during the same update that removes More.
                if state.selectedSectionID == RootNavigationState.moreID, overflow.isEmpty {
                    return direct.first?.id ?? NavigationSectionPreference.homeID
                }
            #endif
            return (direct.contains { $0.id == state.selectedSectionID } || state.selectedSectionID == RootNavigationState.searchID) ? state.selectedSectionID : RootNavigationState.moreID
        }, set: { id in
            state.selectSection(id)
            #if os(iOS)
                if id == RootNavigationState.searchID, state.globalSearch.related == nil, state.globalSearch.text.isEmpty {
                    state.globalSearch.typed.isPresented = true
                }
            #endif
        })
    }

    var body: some View {
        TabView(selection: selection) {
            #if os(tvOS)
                Tab("Search", systemImage: "magnifyingglass", value: RootNavigationState.searchID, role: .search) { SectionStack(sectionID: RootNavigationState.searchID) }
            #endif
            ForEach(direct) { section in
                Tab(value: section.id) { SectionStack(sectionID: section.id) } label: {
                    #if os(iOS) || os(tvOS)
                        Label(section.id == NavigationCategory.tvshows.id ? String(localized: "Series") : section.title, systemImage: section.systemImage)
                    #else
                        Label(section.title, systemImage: section.systemImage)
                    #endif
                }
            }
            if !overflow.isEmpty {
                Tab(value: RootNavigationState.moreID) { SectionStack(sectionID: overflow.contains(where: { $0.id == state.selectedSectionID }) ? state.selectedSectionID : RootNavigationState.moreID, overflow: overflow) } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
            #if os(iOS)
                Tab(value: RootNavigationState.searchID, role: .search) {
                    SectionStack(sectionID: RootNavigationState.searchID)
                        .searchable(
                            text: Binding(get: { state.globalSearch.text }, set: { state.editSearchText($0) }),
                            isPresented: Bindable(state.globalSearch.typed).isPresented,
                            prompt: "Search Library"
                        )
                        .modifier(LibrarySearchFieldBehavior(search: state.globalSearch))
                }
            #elseif os(visionOS)
                Tab("Search", systemImage: "magnifyingglass", value: RootNavigationState.searchID) {
                    SectionStack(sectionID: RootNavigationState.searchID)
                }
            #endif
        }
        #if os(visionOS)
        .onChange(of: sections.map(\.id), initial: true) { _, ids in
            state.reconcileVisionMoreSelection(sectionIDs: ids)
        }
        .onChange(of: state.selectedSectionID) { _, _ in state.reconcileVisionMoreSelection(sectionIDs: sections.map(\.id)) }
        #endif
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
                    state.selectSection(id)
                }
            })) {
                Label("Search", systemImage: "magnifyingglass").tag(RootNavigationState.searchID)
                    .accessibilityIdentifier("Navigation.search")
                ForEach(sections) { section in Label(section.title, systemImage: section.systemImage).tag(section.id) }
            }
            .navigationTitle("Gus")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } detail: {
            SectionStack(sectionID: state.selectedSectionID)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

#if os(iOS)
    private struct IPadSplitRootView: View {
        @Environment(RootNavigationState.self) private var state
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(SessionStore.self) private var session
        @Environment(NavigationPreferencesStore.self) private var preferences
        private var sections: [ResolvedNavigationSection] {
            RootSections.resolve(preferences, state: state, session: session)
        }

        var body: some View {
            NavigationSplitView(columnVisibility: Bindable(state).sidebarVisibility) {
                List(selection: Binding<String?>(get: { state.selectedSectionID }, set: {
                    if let id = $0 {
                        state.selectSection(id)
                    }
                })) {
                    Label("Search", systemImage: "magnifyingglass")
                        .accessibilityIdentifier("Navigation.search")
                        .tag(RootNavigationState.searchID)
                    ForEach(sections) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .accessibilityIdentifier("Navigation.section." + section.id)
                            .tag(section.id)
                    }
                }
                .navigationTitle("Gus")
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 320)
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Hide Sidebar", systemImage: "sidebar.left") {
                            state.sidebarVisibility = .detailOnly
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("Navigation.hideSidebar")
                    }
                }

            } detail: {
                SectionStack(sectionID: state.selectedSectionID)
                    .toolbar(removing: .sidebarToggle)
                    .toolbar {
                        if state.sidebarVisibility == .detailOnly {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Show Sidebar", systemImage: "sidebar.left") {
                                    state.sidebarVisibility = .doubleColumn
                                }
                                .labelStyle(.iconOnly)
                                .accessibilityIdentifier("Navigation.showSidebar")
                            }
                        }
                    }
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar(removing: .sidebarToggle)
            .onChange(of: dynamicTypeSize, initial: true) { _, size in
                if size.isAccessibilitySize {
                    state.sidebarVisibility = .detailOnly
                }
            }
        }
    }

#endif

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
        // Read the observable reference before the escaping search-content closure.
        let home = state.home
        NavigationStack(path: state.pathBinding(for: sectionID)) {
            Group {
                if sectionID == RootNavigationState.searchID {
                    GlobalSearchContent()
                } else if sectionID == RootNavigationState.moreID {
                    List(overflow.isEmpty ? sections : overflow) { section in
                        Button { state.selectedSectionID = section.id } label: { Label(section.title, systemImage: section.systemImage) }
                    }
                    .navigationTitle("More")
                } else if let section = sections.first(where: { $0.id == sectionID }) {
                    if section.id == NavigationSectionPreference.downloadedID {
                        DownloadedLibraryView()
                    } else if section.id == NavigationSectionPreference.discoverID {
                        DiscoverView()
                    } else {
                        RootSectionDestination(section: section, home: home)
                    }
                } else {
                    HomeView(store: home)
                }
            }
            .gusItemDestinations()
            .toolbar {
                #if os(iOS)
                    if sectionID == RootNavigationState.searchID, state.globalSearch.related == nil, DeviceIdentity.usesIPadPresentation {
                        ToolbarItem(placement: .primaryAction) {
                            let search = state.searchState(for: sectionID)
                            Button {
                                search.showsList.toggle()
                            } label: {
                                Label(search.showsList ? "Grid" : "List", systemImage: search.showsList ? "square.grid.2x2" : "list.bullet")
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("Search.displayMode")
                        }
                    }
                #endif
                if overflow.contains(where: { $0.id == sectionID }), state.paths[sectionID]?.isEmpty != false {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { state.selectedSectionID = RootNavigationState.moreID } label: { GusToolbarLabel("More", systemImage: "chevron.backward") }.accessibilityLabel("More").gusTVToolbarIcon()
                    }
                }
            }
        }
        #if os(tvOS)
        .gusTVNativeControls()
        .gusTVFocusScope()
        #endif
        #if os(visionOS)
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
        } else if section.id == NavigationSectionPreference.playlistsID {
            VideoPlaylistsView()
        } else if section.id == NavigationSectionPreference.settingsID {
            SettingsView()
        } else if let category = section.category {
            switch category {
            case .livetv:
                LiveTVView()
            case .collections:
                CollectionsView()
            default:
                LibraryGridView(scope: .category(category))
            }
        } else {
            LibrariesLandingView(store: home)
        }
    }
}
