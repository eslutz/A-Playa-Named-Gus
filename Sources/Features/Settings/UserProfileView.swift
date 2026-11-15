import SwiftUI

struct UserProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var audioLanguage = ""
    @State private var subtitleLanguage = ""
    @State private var ready = false
    @State private var confirmingReload = false
    #if !os(iOS) && !os(tvOS)
        @State private var saved = false
    #endif

    var body: some View {
        Group {
            if !ready, session.profile.isLoading {
                ProgressView("Loading Profile")
            } else if !ready, let message = session.profile.errorMessage {
                ContentUnavailableView {
                    Label("Profile Unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: { Text(message) } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                profileForm
            }
        }
        .navigationTitle("Profile")
        .task { await load() }
    }

    private var profileForm: some View {
        Form {
            Section("Profile") {
                ProfileAvatar(data: session.profile.imageData)
                TextField("Username", text: $name)
                Text("Changing your username also changes the name you use to sign in to Jellyfin.").font(.footnote)
            }
            Section("Jellyfin Playback Preferences") {
                languagePicker("Audio Language", selection: $audioLanguage)
                languagePicker("Subtitle Language", selection: $subtitleLanguage)
            }
            if let message = session.profile.errorMessage {
                Section {
                    Text(message)
                    if let currentUsername = session.profile.currentUsernameAfterPartialSave {
                        LabeledContent("Current Jellyfin Username", value: currentUsername)
                    }
                    Button("Reload Profile") {
                        if hasDraftChanges {
                            confirmingReload = true
                        } else {
                            Task { await load() }
                        }
                    }
                }
            }
            #if !os(iOS) && !os(tvOS)
                if saved, !hasDraftChanges {
                    Text("Profile saved to Jellyfin.")
                }
                Button("Save Changes") {
                    Task {
                        saved = await session.profile.save(name: name, audioLanguage: audioLanguage, subtitleLanguage: subtitleLanguage) == .confirmed
                        app.synchronizeProfile(from: session)
                    }
                }
                .disabled(!ready || name.trimmedNilIfEmpty == nil || session.profile.isSaving || session.profile.isLoading || session.profile.needsSaveReadback)
            #endif
        }
        .disabled(session.profile.isSaving || session.profile.isLoading)
        .navigationTitle("Profile")
        .toolbar {
            #if os(iOS) || os(tvOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(session.profile.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let outcome = await session.profile.save(name: name, audioLanguage: audioLanguage, subtitleLanguage: subtitleLanguage)
                            app.synchronizeProfile(from: session)
                            if outcome == .confirmed {
                                dismiss()
                            }
                        }
                    } label: {
                        if session.profile.isSaving {
                            ProgressView().accessibilityLabel("Saving Profile")
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!ready || name.trimmedNilIfEmpty == nil || session.profile.isSaving || session.profile.isLoading || session.profile.needsSaveReadback)
                    .accessibilityIdentifier("Profile.save")
                }
            #else
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            #endif
        }
        .confirmationDialog("Reload Profile?", isPresented: $confirmingReload) {
            Button("Reload and Discard Draft", role: .destructive) { Task { await load() } }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Reloading replaces your unsaved profile changes with the current server profile.")
        }
        .interactiveDismissDisabled(session.profile.isSaving)
        .onChange(of: session.profile.profile) { _, _ in
            if !ready {
                populateFields()
            }
        }
    }

    private var hasDraftChanges: Bool {
        guard ready, let profile = session.profile.profile else { return false }
        return name != (profile.name ?? session.user.name)
            || audioLanguage != (profile.configuration?.audioLanguagePreference ?? "")
            || subtitleLanguage != (profile.configuration?.subtitleLanguagePreference ?? "")
    }

    private func languagePicker(_ title: LocalizedStringKey, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("Server default").tag("")
            ForEach(languageCodes, id: \.self) { code in
                Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
            }
        }
    }

    private var languageCodes: [String] {
        // Jellyfin stores ISO 639-2 codes; users choose localized language names.
        let codes = Locale.LanguageCode.isoLanguageCodes.compactMap { $0.identifier(.alpha3) }
        return Set(codes + [audioLanguage, subtitleLanguage]).filter { !$0.isEmpty }.sorted {
            (Locale.current.localizedString(forLanguageCode: $0) ?? $0)
                .localizedStandardCompare(Locale.current.localizedString(forLanguageCode: $1) ?? $1) == .orderedAscending
        }
    }

    private func load() async {
        await session.profile.load()
        app.synchronizeProfile(from: session)
        if session.profile.errorMessage == nil || !ready {
            populateFields()
        }
    }

    private func populateFields() {
        guard let profile = session.profile.profile else { return }
        name = profile.name ?? session.user.name
        audioLanguage = profile.configuration?.audioLanguagePreference ?? ""
        subtitleLanguage = profile.configuration?.subtitleLanguagePreference ?? ""
        ready = true
    }
}
