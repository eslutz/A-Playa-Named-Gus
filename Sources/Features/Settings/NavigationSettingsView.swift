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
            if isEditing {
                Button {
                    show(section)
                } label: {
                    HStack {
                        navigationRow(section)
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .buttonStyle(.plain)
            } else {
                navigationRow(section)
            }
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
            navigationRow(section)
                .moveDisabled(!section.canMove)
                .deleteDisabled(!section.canHide)
        #else
            if section.canMove {
                navigationRow(section)
                    .moveDisabled(!section.canMove)
                    .deleteDisabled(!section.canHide)
                    .draggable(section.id)
                    .dropDestination(for: String.self) { draggedIDs, _ in
                        moveDraggedSection(draggedIDs.first, before: section.id, in: sections)
                    }
            } else {
                navigationRow(section)
                    .moveDisabled(!section.canMove)
                    .deleteDisabled(!section.canHide)
                    .dropDestination(for: String.self) { draggedIDs, _ in
                        moveDraggedSection(draggedIDs.first, before: section.id, in: sections)
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
            navigationPreferences.setVisibility(
                false,
                forSectionID: sections[index].id,
                libraries: libraries,
                serverID: session.server.id,
                userID: session.user.id
            )
        }
    }

    private func show(_ section: ResolvedNavigationSection) {
        navigationPreferences.setVisibility(
            true,
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
        } catch {
            let gusError = GusError(from: error)
            guard !gusError.isCancellation else { return }
            state = .failed(gusError.localizedDescription)
        }
    }
}
