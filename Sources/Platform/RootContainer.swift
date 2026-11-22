import SwiftUI
#if os(tvOS)
    import CloudKit
#endif

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
    #if os(visionOS)
        @Environment(CinemaModel.self) private var cinema
    #endif
    @SceneStorage("gus.root.selection") private var storedSelection = NavigationSectionPreference.homeID

    init(session: SessionStore) {
        let navigation = RootNavigationState(searchHistory: session.searchHistory)
        navigation.home = session.homeStore()
        _state = State(initialValue: navigation)
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
            .gusSessionPlayerHost(state: state, enabled: state.detailItem == nil)
            .gusAudioHost(coordinator: audio, enabled: state.detailItem == nil)
        #if os(iOS) || os(tvOS) || os(macOS)
            .gusNowPlaying(coordinator: audio, enabled: state.detailItem == nil)
        #endif
            .task {
                preferences.load(serverID: session.server.id, userID: session.user.id)
                if !state.hasRestoredSelection {
                    state.hasRestoredSelection = true
                    if navigation.routeRequest == 0 {
                        state.selectSection(storedSelection)
                    } else {
                        state.adopt(navigation.route)
                    }
                }
                handleSearchCommand()
                await state.home?.loadIfNeeded()
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
                #if os(iOS)
                    session.refreshForYouSyncAccount()
                #endif
                await session.profile.load()
                app.synchronizeProfile(from: session)
                session.references.beginRefresh()
                await state.refreshCachedContent(ifStale: true)
            }
        #if os(tvOS)
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    session.forYouShelf.clear()
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged).map({ _ in () }) {
                    session.forYouShelf.iCloudAccountChanged()
                }
            }
        #endif
            .onChange(of: session.intelligenceAccess.usesNaturalSearch) { _, _ in
                state.useKeywordSearchForCurrentDrafts()
            }
        #if !os(tvOS)
            .focusedSceneValue(state)
        #endif
            .onChange(of: navigation.searchFocusRequest) { handleSearchCommand() }
            .onChange(of: navigation.routeRequest) { _, _ in state.adopt(navigation.route) }
            .onChange(of: state.selectedSectionID) { _, id in storedSelection = id }
            .onChange(of: session.seerr.revision, initial: true) { _, revision in
                state.updateSeerrRevision(revision)
            }
            .modifier(IntelligencePromptHost(blocked: defersIntelligencePrompt))
            .environment(state)
            .environment(audio)
            .environment(session.seerr)
            .task { await session.seerr.restore() }
    }

    private var defersIntelligencePrompt: Bool {
        #if os(visionOS)
            if cinema.isOpen {
                return true
            }
        #elseif os(macOS)
            if !navigation.playerWindows.requests.isEmpty {
                return true
            }
        #endif
        return app.isTransitioning || state.isProfilePresented || state.playerItem != nil || state.detailItem != nil ||
            audio.isPresented || audio.store?.isPlaybackRequested == true
    }

    private func handleSearchCommand() {
        guard navigation.consumeSearchFocus() else { return }
        if let term = navigation.consumeLibrarySearch(for: session.lease) {
            state.selectSection(RootNavigationState.searchID)
            state.focusSearch()
            state.replaySearch(.typed(term))
        } else {
            state.focusSearch()
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
            if DeviceIdentity.usesIPadPresentation, widthClass == .regular {
                IPadSplitRootView()
            } else {
                TabRootView()
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
        let directIDs = Set(direct.map(\.id))
        return sections.filter { !directIDs.contains($0.id) }
    }

    private struct TabConfiguration: Equatable {
        let sectionIDs: [String]
        let overflowIDs: [String]
        let selected: String
        let librariesLoaded: Bool
    }

    private var configuration: TabConfiguration {
        .init(sectionIDs: sections.map(\.id), overflowIDs: overflow.map(\.id), selected: state.selectedSectionID, librariesLoaded: state.home?.libraryState == .loaded)
    }

    private var selection: Binding<String> {
        Binding(get: {
            if direct.contains(where: { $0.id == state.selectedSectionID }) || state.selectedSectionID == RootNavigationState.searchID {
                return state.selectedSectionID
            }
            return overflow.isEmpty ? direct.first?.id ?? NavigationSectionPreference.homeID : RootNavigationState.moreID
        }, set: { id in
            if id == RootNavigationState.moreID {
                state.selectMoreTab(overflowIDs: overflow.map(\.id))
            } else {
                state.selectSection(id)
                #if os(iOS)
                    if id == RootNavigationState.searchID, state.paths[id, default: []].isEmpty,
                       state.globalSearch.text.isEmpty, session.searchHistory.entries.isEmpty
                    {
                        state.globalSearch.typed.isPresented = true
                    }
                #endif
            }
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
                Tab(value: RootNavigationState.moreID) { SectionStack(sectionID: RootNavigationState.moreID, overflow: overflow) } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
            #if os(iOS)
                Tab(value: RootNavigationState.searchID, role: .search) {
                    SectionStack(sectionID: RootNavigationState.searchID)
                        .searchable(
                            text: Binding(get: { state.globalSearch.text }, set: { state.editSearchText($0, naturalSearchEnabled: session.intelligenceAccess.usesNaturalSearch) }),
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
        .onChange(of: configuration, initial: true) { _, config in
            state.reconcileTabSelection(sectionIDs: config.sectionIDs, overflowIDs: config.overflowIDs, librariesLoaded: config.librariesLoaded)
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
        .onAppear { state.useSidebar() }
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
            let visibility = Binding(
                get: { state.sidebarVisibility ?? (dynamicTypeSize.isAccessibilitySize ? .detailOnly : .doubleColumn) },
                set: { state.sidebarVisibility = $0 }
            )
            NavigationSplitView(columnVisibility: visibility) {
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
            } detail: {
                SectionStack(sectionID: state.selectedSectionID)
            }
            .navigationSplitViewStyle(.balanced)
            .onAppear { state.useSidebar() }
            .onChange(of: dynamicTypeSize.isAccessibilitySize) { _, usesAccessibilitySize in
                if usesAccessibilitySize {
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
    let sectionID: String
    var overflow: [ResolvedNavigationSection] = []

    var body: some View {
        let path = sectionID == RootNavigationState.moreID
            ? state.morePathBinding(overflowIDs: overflow.map(\.id))
            : state.pathBinding(for: sectionID)
        let contentSection: String = if case let .section(id)? = path.wrappedValue.first {
            id
        } else {
            sectionID
        }
        NavigationStack(path: path) {
            Group {
                if sectionID == RootNavigationState.searchID {
                    GlobalSearchContent()
                } else if sectionID == RootNavigationState.moreID {
                    List(overflow) { section in
                        NavigationLink(value: GusRoute.section(section.id)) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                    }
                    .navigationTitle("More")
                } else {
                    SectionDestination(sectionID: sectionID)
                }
            }
            .gusItemDestinations()
            .toolbar {
                #if os(iOS)
                    if sectionID == RootNavigationState.searchID, DeviceIdentity.usesIPadPresentation,
                       !session.intelligenceAccess.usesNaturalSearch || state.globalSearch.displaysKeywords
                    {
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
            }
        }
        .environment(\.detailNavigationStack, .section(contentSection))
        #if os(tvOS)
            .gusTVNativeControls()
            .gusTVFocusScope()
        #endif
        #if os(visionOS)
        .gusNowPlaying(coordinator: audio, enabled: state.detailItem == nil)
        #endif
    }
}

struct SectionDestination: View {
    @Environment(RootNavigationState.self) private var state
    @Environment(SessionStore.self) private var session
    @Environment(NavigationPreferencesStore.self) private var preferences
    let sectionID: String

    var body: some View {
        let sections = RootSections.resolve(preferences, state: state, session: session)
        if let section = sections.first(where: { $0.id == sectionID }) {
            RootSectionDestination(section: section, home: state.home)
        } else {
            HomeView(store: state.home)
        }
    }
}

private struct RootSectionDestination: View {
    let section: ResolvedNavigationSection
    let home: HomeStore?
    var body: some View {
        if section.id == NavigationSectionPreference.homeID {
            HomeView(store: home)
        } else if section.id == NavigationSectionPreference.downloadedID {
            DownloadedLibraryView()
        } else if section.id == NavigationSectionPreference.discoverID {
            DiscoverView()
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
