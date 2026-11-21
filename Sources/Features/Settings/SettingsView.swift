import SwiftUI

/// Account, known servers, sign-out, and version info.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(RootNavigationState.self) private var navigationState
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    @Environment(SavedMediaStore.self) private var videoPlaylists

    @State private var rememberPlaybackTracks = false
    @State private var showingTVAccentEditor = false
    @State private var reauthenticationServer: ServerConnection?
    @State private var switchErrorMessage: String?
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnratedContent = false
    @AppStorage(AppearanceSetting.defaultsKey) private var appearanceRawValue = AppearanceSetting.system.rawValue
    @AppStorage(PlaybackQuality.defaultsKey) private var playbackQualityRawValue = PlaybackQuality.maximum.rawValue
    @AppStorage(PlaybackPreferences.autoPlayNextEpisodeKey) private var autoPlayNextEpisode = true

    var body: some View {
        Form {
            Section("Account") {
                Button("View and Edit Profile") { navigationState.isProfilePresented = true }
                LabeledContent("User", value: session.user.name)
                LabeledContent("Server", value: session.server.name)
                LabeledContent("Address", value: session.server.url.absoluteString)
            }

            ForEach(appModel.servers) { server in
                let users = appModel.users(on: server)
                if !users.isEmpty {
                    Section {
                        ForEach(users) { user in
                            storedUserRow(user, server: server)
                        }
                    } header: {
                        Text(server.name)
                    } footer: {
                        Text(server.url.host() ?? server.url.absoluteString)
                    }
                }
            }

            if DownloadsAvailability.isSupported, session.mediaProvider.capabilities.supportsDownloads {
                DownloadsSettingsSection(
                    byteCount: downloads.totalByteCount(serverID: session.server.id, userID: session.user.id),
                    isUnavailable: downloads.loadErrorMessage != nil
                )
            }

            Section {
                playbackSetting(
                    title: "Streaming Quality",
                    helpTitle: "About Streaming Quality",
                    helpText: "Maximum lets compatible files play at original quality. Lower settings cap the streaming bitrate for constrained networks."
                ) {
                    qualityPicker
                }
                Toggle("Auto-Play Next Episode", isOn: $autoPlayNextEpisode)
                playbackSetting(
                    title: "Remember Episode Tracks",
                    compactTitle: "Remember Tracks",
                    helpTitle: "About Remembering Episode Tracks",
                    helpText: "Gus remembers the audio and subtitle choices you make for each series on this device and account. Other episodes use those choices when matching tracks are available. Turning this off clears your saved choices."
                ) {
                    Toggle("Remember Episode Tracks for This Account", isOn: Binding(
                        get: { rememberPlaybackTracks },
                        set: { enabled in
                            rememberPlaybackTracks = enabled
                            PlaybackTrackMemory.shared.setEnabled(enabled, scope: session.references.scope)
                        }
                    ))
                    #if !os(tvOS)
                    .labelsHidden()
                    #endif
                    .accessibilityIdentifier("Settings.rememberEpisodeTracks")
                }
            } header: {
                Text("Playback")
            }

            IntelligenceSettingsSection()

            Section("iCloud Sync") {
                #if os(iOS) || os(tvOS)
                    ForYouSyncSetting()
                #endif
                SyncSettingRow(title: "Sync Gus Resume and Next Up", isOn: Binding(
                    get: { videoPlaylists.syncEnabled },
                    set: { videoPlaylists.syncEnabled = $0 }
                ), identifier: "Settings.resumeSync") {
                    Text("Jellyfin stores playlists and collections. iCloud synchronizes Gus resume positions and Next Up state.")
                        .font(.caption)
                    Text(videoPlaylists.syncStatus)
                        .accessibilityIdentifier("Settings.resumeSyncStatus")
                }
            }

            Section {
                Picker("Appearance", selection: $appearanceRawValue) {
                    ForEach(AppearanceSetting.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                #if os(iOS)
                    ThemeSettingsControls()
                #endif
                NavigationLink(value: GusRoute.screen(.navigationSettings)) {
                    Label("Navigation", systemImage: "list.bullet")
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows your device's light and dark setting. Navigation customizes which sections appear in the main menu.")
            }

            #if os(tvOS)
                TVThemeSettingsControls { showingTVAccentEditor = true }
            #endif

            Section {
                Picker("Limit Content Ratings", selection: $contentLimitRawValue) {
                    ForEach(ContentRatingGate.Limit.allCases) { limit in
                        Text(limit.title).tag(limit.rawValue)
                    }
                }
                if contentLimitRawValue != ContentRatingGate.Limit.off.rawValue {
                    Toggle("Hide Unrated Media", isOn: $hideUnratedContent)
                }
                #if canImport(DeclaredAgeRange) && (os(iOS) || os(macOS))
                    AgeRangeDefaultsButton()

                #endif
            } header: {
                Text("Content Restrictions")
            } footer: {
                Text("Hides and gates media rated above the limit. Pair with Jellyfin user permissions and Apple Screen Time for enforced parental controls.")
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    Task { await appModel.signOut() }
                }
                .gusKeyboardShortcut("q", modifiers: [.command, .shift])
            }

            Section("Integrations") {
                NavigationLink(value: GusRoute.screen(.seerrSettings)) {
                    Label("Seerr", systemImage: "sparkles")
                }
            }

            Section("Developer") {
                NavigationLink(value: GusRoute.screen(.clientLogs)) {
                    Label("Client Logs", systemImage: "ladybug")
                }
            }

            Section("About") {
                LabeledContent("Version", value: DeviceIdentity.appVersion)
                LabeledContent("Client", value: DeviceIdentity.clientName)
                LabeledContent("Device", value: DeviceIdentity.deviceName)
            }
        }
        .task(id: session.references.scope) {
            rememberPlaybackTracks = PlaybackTrackMemory.shared.isEnabled(scope: session.references.scope)
        }
        .settingsFormStyle()
        .gusTVAccentEditor(isPresented: $showingTVAccentEditor)
        .navigationTitle("Settings")
        .task {
            downloads.load(serverID: session.server.id, userID: session.user.id)
        }
        .sheet(item: $reauthenticationServer) { server in
            NavigationStack {
                SignInView(server: server)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                reauthenticationServer = nil
                            }
                        }
                    }
            }
        }
        .alert(
            "Account Switch Failed",
            isPresented: Binding(
                get: { switchErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        switchErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                switchErrorMessage = nil
            }
        } message: {
            Text(switchErrorMessage ?? "")
        }
    }

    private var qualityOptions: some View {
        ForEach(PlaybackQuality.allCases) { quality in
            Text(quality.title).tag(quality.rawValue)
        }
    }

    @ViewBuilder
    private var qualityPicker: some View {
        #if os(tvOS)
            Picker("Streaming Quality", selection: $playbackQualityRawValue) { qualityOptions }
        #else
            let quality = PlaybackQuality(rawValue: playbackQualityRawValue) ?? .maximum
            #if os(iOS)
                Picker(selection: $playbackQualityRawValue) {
                    qualityOptions
                } label: {
                    Text("Streaming Quality")
                } currentValueLabel: {
                    Text(quality.compactTitle)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityValue(quality.title)
                .accessibilityIdentifier("Settings.streamingQuality")
            #else
                Menu {
                    Picker("Streaming Quality", selection: $playbackQualityRawValue) { qualityOptions }
                        .pickerStyle(.inline)
                } label: {
                    Text(quality.compactTitle)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .accessibilityLabel("Streaming Quality")
                .accessibilityValue(quality.title)
                .accessibilityIdentifier("Settings.streamingQuality")
            #endif
        #endif
    }

    @ViewBuilder
    private func playbackSetting<Control: View>(
        title: LocalizedStringKey,
        compactTitle: LocalizedStringKey? = nil,
        helpTitle: LocalizedStringKey,
        helpText: LocalizedStringKey,
        @ViewBuilder control: () -> Control
    ) -> some View {
        #if os(tvOS)
            // The television Form focuses each cell as one remote action.
            control()
            PlaybackHelpButton(title: helpTitle, message: helpText)
        #else
            let help = PlaybackHelpButton(title: helpTitle, message: helpText)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    Text(title).fixedSize().accessibilityHidden(true)
                    help
                    Spacer(minLength: 4)
                    control().fixedSize()
                }
                if let compactTitle {
                    HStack(spacing: 0) {
                        Text(compactTitle).fixedSize().accessibilityHidden(true)
                        help
                        Spacer(minLength: 4)
                        control().fixedSize()
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        Text(title).fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
                        help
                    }
                    control()
                }
            }
            .accessibilityElement(children: .contain)
        #endif
    }

    @ViewBuilder
    private func storedUserRow(_ user: StoredUser, server: ServerConnection) -> some View {
        let isActiveUser = session.user.id == user.id && session.user.serverID == user.serverID

        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text(user.name)
                    Text(server.url.host() ?? server.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: isActiveUser ? "checkmark.circle.fill" : "person.circle")
            }

            Spacer()

            if isActiveUser {
                Text("Active")
                    .foregroundStyle(.secondary)
            } else if appModel.hasStoredToken(for: user) {
                Button("Switch") {
                    Task { await switchToStoredUser(user) }
                }
            } else {
                Button("Sign In Again") {
                    reauthenticationServer = server
                }
            }
        }
    }

    private func switchToStoredUser(_ user: StoredUser) async {
        do {
            try await appModel.switchToStoredUser(user)
        } catch {
            switchErrorMessage = error.localizedDescription
        }
    }
}

private extension View {
    @ViewBuilder
    func settingsFormStyle() -> some View {
        #if os(visionOS)
            formStyle(.automatic)
        #elseif os(iOS)
            formStyle(.grouped)
                .frame(maxWidth: DeviceIdentity.usesIPadPresentation ? 760 : .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #else
            formStyle(.grouped)
        #endif
    }
}

private struct PlaybackHelpButton: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @State private var showingHelp = false

    var body: some View {
        Button { showingHelp = true } label: {
            Label(title, systemImage: "info.circle")
            #if os(tvOS)
                .labelStyle(.titleAndIcon)
            #else
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
            #endif
                .contentShape(Rectangle())
        }
        #if os(tvOS)
        .alert(title, isPresented: $showingHelp) {
            Button("OK") {}
        } message: {
            Text(message)
        }
        #else
        .buttonStyle(.borderless)
        .popover(isPresented: $showingHelp) {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
                .frame(idealWidth: 280, maxWidth: 340, alignment: .leading)
                .padding()
                .presentationCompactAdaptation(.popover)
        }
        #endif
    }
}

private struct DownloadsSettingsSection: View {
    let byteCount: Int64
    let isUnavailable: Bool

    private var formattedByteCount: String {
        isUnavailable ? String(localized: "Unavailable") : ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var body: some View {
        Section {
            NavigationLink(value: GusRoute.screen(.downloads)) {
                LabeledContent("Downloaded Media", value: formattedByteCount)
            }
        } header: {
            Text("Downloads")
        } footer: {
            Text("Downloads are available on iOS, iPadOS, macOS, and visionOS. tvOS is excluded because its app storage is system-purgeable.")
        }
    }
}
