import SwiftUI

/// Settings editor for the customizable main navigation. It uses SwiftUI's native list
/// editing behavior: movable rows get reorder handles, hideable category rows get delete
/// controls, and hidden category rows can be shown again.
struct NavigationSettingsView: View {
    #if !os(macOS)
        @Environment(\.editMode) private var editMode
    #endif
    @Environment(SessionStore.self) private var session
    @Environment(NavigationPreferencesStore.self) private var navigationPreferences

    @State private var libraries: [MediaItem] = []
    @State private var state: LoadState = .idle
    #if os(macOS)
        @State private var isMacEditing = false
    #endif

    var body: some View {
        List {
            switch state {
            case .idle, .loading:
                Section {
                    HStack {
                        Text("Loading Sections")
                        Spacer()
                        ProgressView()
                    }
                }
            case let .failed(message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                    Button("Try Again") { Task { await loadLibraries() } }
                }
            case .loaded:
                Section("Sections") {
                    sectionRows
                }
                .id(navigationPreferences.revision)

                Section("Hidden") {
                    hiddenRows
                }
            }
        }
        .navigationTitle("Navigation")
        .toolbar {
            #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button(isMacEditing ? "Done" : "Edit") {
                        isMacEditing.toggle()
                    }
                }
            #elseif !os(tvOS)
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            #endif
        }
        .task {
            await loadLibraries()
        }
    }

    @ViewBuilder
    private var sectionRows: some View {
        let sections = navigationPreferences.visibleSections(
            libraries: libraries,
            serverID: session.server.id,
            userID: session.user.id
        )

        ForEach(sections) { section in
            sectionRow(section, in: sections)
        }
        .onMove(perform: moveSections)
        .onDelete(perform: hideSections)
    }

    @ViewBuilder
    private var hiddenRows: some View {
        let sections = navigationPreferences.hiddenSections(
            libraries: libraries,
            serverID: session.server.id,
            userID: session.user.id
        )

        ForEach(sections) { section in
            #if os(tvOS)
                Button {
                    setVisibility(true, for: section)
                } label: {
                    Label("Show \(section.title)", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("Navigation.show." + section.id)
            #else
                if isEditing {
                    HStack {
                        navigationRow(section)
                        Spacer()
                        Button {
                            setVisibility(true, for: section)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Show \(section.title)"))
                        .accessibilityIdentifier("Navigation.show." + section.id)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 12))
                } else {
                    navigationRow(section)
                }
            #endif
        }
    }

    private var isEditing: Bool {
        #if os(macOS)
            isMacEditing
        #else
            editMode?.wrappedValue.isEditing == true
        #endif
    }

    private func navigationRow(_ section: ResolvedNavigationSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
    }

    @ViewBuilder
    private func sectionRow(_ section: ResolvedNavigationSection, in sections: [ResolvedNavigationSection]) -> some View {
        if isEditing {
            navigationRow(section)
                .moveDisabled(!section.canMove)
                .deleteDisabled(!section.canHide)
        } else {
            standardSectionRow(section, in: sections)
        }
    }

    @ViewBuilder
    private func standardSectionRow(_ section: ResolvedNavigationSection, in sections: [ResolvedNavigationSection]) -> some View {
        #if os(tvOS)
            if section.canMove {
                let movable = sections.filter(\.canMove)
                Menu {
                    if section.canHide {
                        Button("Hide Menu Item", systemImage: "eye.slash") {
                            setVisibility(false, for: section)
                        }
                    }
                    Button("Move Up", systemImage: "arrow.up") { moveSection(section, by: -1) }
                        .disabled(movable.first?.id == section.id)
                    Button("Move Down", systemImage: "arrow.down") { moveSection(section, by: 1) }
                        .disabled(movable.last?.id == section.id)
                } label: {
                    navigationRow(section)
                }
                .accessibilityIdentifier("Navigation.section." + section.id)
            } else {
                navigationRow(section)
            }
        #else
            if section.canMove {
                navigationRow(section)
                    .moveDisabled(!section.canMove)
                    .deleteDisabled(!section.canHide)
                    .draggable(section.id)
                    .dropDestination(for: String.self) { draggedIDs, _ in
                        _ = moveDraggedSection(draggedIDs.first, before: section.id, in: sections)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 12))
            } else {
                navigationRow(section)
                    .moveDisabled(!section.canMove)
                    .deleteDisabled(!section.canHide)
                    .dropDestination(for: String.self) { draggedIDs, _ in
                        _ = moveDraggedSection(draggedIDs.first, before: section.id, in: sections)
                    }
            }
        #endif
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        navigationPreferences.moveVisibleSections(
            from: source,
            to: destination,
            libraries: libraries,
            serverID: session.server.id,
            userID: session.user.id
        )
    }

    #if os(tvOS)
        private func moveSection(_ section: ResolvedNavigationSection, by offset: Int) {
            navigationPreferences.move(sectionID: section.id, by: offset, libraries: libraries, serverID: session.server.id, userID: session.user.id)
        }
    #endif

    private func moveDraggedSection(_ draggedID: String?, before targetID: String, in sections: [ResolvedNavigationSection]) -> Bool {
        guard let draggedID,
              draggedID != targetID,
              let sourceIndex = sections.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = sections.firstIndex(where: { $0.id == targetID }),
              sections[sourceIndex].canMove
        else { return false }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        moveSections(from: IndexSet(integer: sourceIndex), to: destination)
        return true
    }

    private func hideSections(at offsets: IndexSet) {
        let sections = navigationPreferences.visibleSections(
            libraries: libraries,
            serverID: session.server.id,
            userID: session.user.id
        )
        for index in offsets where sections.indices.contains(index) {
            setVisibility(false, for: sections[index])
        }
    }

    private func setVisibility(_ visible: Bool, for section: ResolvedNavigationSection) {
        navigationPreferences.setVisibility(
            visible,
            forSectionID: section.id,
            libraries: libraries,
            serverID: session.server.id,
            userID: session.user.id
        )
    }

    private func loadLibraries() async {
        guard state != .loading else { return }
        state = .loading
        navigationPreferences.load(serverID: session.server.id, userID: session.user.id)
        do {
            libraries = try await session.mediaProvider.userViews()
            state = .loaded
            await navigationPreferences.refreshBookFormats(session: session)
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            state = .failed(gusError.localizedDescription)
        }
    }
}
