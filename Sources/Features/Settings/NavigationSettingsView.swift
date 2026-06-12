import SwiftUI

/// Settings editor for the customizable main navigation: the sections between Home and
/// Settings can be hidden and reordered per app user. Home stays fixed at the start and
/// Settings at the end by design. Explicit move buttons (rather than drag-only reorder)
/// keep the editor usable on every platform, including the tvOS focus engine.
struct NavigationSettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(NavigationPreferencesStore.self) private var navigationPreferences

    @State private var libraries: [MediaItem] = []
    @State private var state: LoadState = .idle

    var body: some View {
        List {
            Section {
                fixedRow(title: String(localized: "Home", comment: "Navigation section: home"), systemImage: "house")
            } footer: {
                Text("Home is always first.")
            }

            Section {
                switch state {
                case .idle, .loading:
                    HStack {
                        Text("Loading Sections")
                        Spacer()
                        ProgressView()
                    }
                case let .failed(message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                case .loaded:
                    sectionRows
                }
            } header: {
                Text("Sections")
            } footer: {
                Text("Hidden sections stay available from the Libraries grid. New libraries on the server appear here automatically.")
            }

            Section {
                fixedRow(title: String(localized: "Settings", comment: "Settings navigation label"), systemImage: "gearshape")
            } footer: {
                Text("Settings is always last.")
            }
        }
        .navigationTitle("Navigation")
        .task {
            await loadLibraries()
        }
    }

    @ViewBuilder
    private var sectionRows: some View {
        let sections = navigationPreferences.resolvedSections(
            libraries: libraries,
            serverID: session.server.id,
            userID: session.user.id
        )

        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
            HStack(spacing: 12) {
                Toggle(isOn: visibilityBinding(for: section)) {
                    Label(section.title, systemImage: section.systemImage)
                }

                #if os(tvOS)
                    Button {
                        move(section, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .accessibilityLabel("Move \(section.title) up")

                    Button {
                        move(section, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(index == sections.count - 1)
                    .accessibilityLabel("Move \(section.title) down")
                #endif
            }
        }
        .onMove(perform: moveSections)
    }

    private func fixedRow(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .accessibilityValue(Text("Fixed", comment: "VoiceOver value for a navigation section that can't be moved or hidden"))
    }

    private func visibilityBinding(for section: ResolvedNavigationSection) -> Binding<Bool> {
        Binding {
            section.isVisible
        } set: { isVisible in
            navigationPreferences.setVisibility(
                isVisible,
                forSectionID: section.id,
                libraries: libraries,
                serverID: session.server.id,
                userID: session.user.id
            )
        }
    }

    private func move(_ section: ResolvedNavigationSection, by offset: Int) {
        navigationPreferences.move(
            sectionID: section.id,
            by: offset,
            libraries: libraries,
            serverID: session.server.id,
            userID: session.user.id
        )
    }

    private func moveSections(from source: IndexSet, to destination: Int) {
        let sections = navigationPreferences.resolvedSections(
            libraries: libraries,
            serverID: session.server.id,
            userID: session.user.id
        )
        guard let sourceIndex = source.first else { return }
        let offset = destination > sourceIndex ? destination - sourceIndex - 1 : sourceIndex - destination
        let direction = destination > sourceIndex ? 1 : -1
        for _ in 0 ..< offset {
            navigationPreferences.move(
                sectionID: sections[sourceIndex].id,
                by: direction,
                libraries: libraries,
                serverID: session.server.id,
                userID: session.user.id
            )
        }
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
