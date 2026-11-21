import SwiftUI

struct UserProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var audioLanguage = ""
    @State private var subtitleLanguage = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var picture: Data?
    @State private var loadingPicture = false
    @State private var ready = false
    @State private var confirmingReload = false
    #if !os(iOS) && !os(tvOS)
        @State private var saved = false
    #endif

    var body: some View {
        Group {
            if ready {
                profileForm
            } else if !session.profile.isLoading, let message = session.profile.errorMessage {
                ContentUnavailableView {
                    Label("Profile Unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: { Text(message) } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView("Loading Profile")
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            if !ready {
                ToolbarItem(placement: .cancellationAction) {
                    GusCloseButton { dismiss() }
                        .disabled(session.profile.isSaving)
                }
            }
        }
        .interactiveDismissDisabled(session.profile.isSaving)
        .onChange(of: session.profile.profile) { _, _ in
            if !ready {
                populateFields()
            }
        }
        .task {
            if !ready {
                await load()
            }
        }
    }

    private var profileForm: some View {
        Form {
            Section("Profile") {
                ProfilePicturePicker(current: session.profile.imageData, picture: $picture, isLoading: $loadingPicture)
                TextField("Username", text: $name).autocorrectionDisabled().gusAccountNameInput()
                Text("Changing your username also changes the name you use to sign in to Jellyfin.").font(.footnote)
            }
            Section("Jellyfin Playback Preferences") {
                languagePicker("Audio Language", selection: $audioLanguage)
                languagePicker("Subtitle Language", selection: $subtitleLanguage)
            }
            Section {
                SecureField("New Password", text: $newPassword).textContentType(.newPassword)
                if !newPassword.isEmpty || !confirmation.isEmpty {
                    SecureField("Confirm New Password", text: $confirmation).textContentType(.newPassword)
                    if !confirmation.isEmpty, confirmation != newPassword {
                        Text("The new passwords do not match.").font(.footnote)
                    }
                }
            } header: {
                Text("Change Password")
            } footer: {
                if !newPassword.isEmpty {
                    Text("Changing your password signs other devices out of Jellyfin.")
                }
            }
            Section {
                SecureField("Current Password", text: $currentPassword).textContentType(.password)
            } footer: {
                if session.profile.profile?.hasPassword == false {
                    Text("Leave Current Password blank to save changes or set your first password.")
                } else {
                    Text("Enter your current Jellyfin password to save profile changes.")
                }
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
                    Task { await save() }
                }
                .disabled(!canSave)
            #endif
        }
        .disabled(session.profile.isSaving || session.profile.isLoading)
        .toolbar {
            #if os(iOS) || os(tvOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(session.profile.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if session.profile.isSaving {
                            ProgressView().accessibilityLabel("Saving Profile")
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("Profile.save")
                }
            #else
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(session.profile.isSaving) }
            #endif
        }
        .confirmationDialog("Reload Profile?", isPresented: $confirmingReload) {
            Button("Reload and Discard Draft", role: .destructive) { Task { await load() } }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Reloading replaces your unsaved profile changes with the current server profile.")
        }
    }

    private var hasDraftChanges: Bool {
        guard ready, let profile = session.profile.profile else { return false }
        return name != (profile.name ?? session.user.name)
            || audioLanguage != (profile.configuration?.audioLanguagePreference ?? "")
            || subtitleLanguage != (profile.configuration?.subtitleLanguagePreference ?? "")
            || !newPassword.isEmpty || !confirmation.isEmpty || picture != nil
    }

    private var canSave: Bool {
        hasDraftChanges && name.trimmedNilIfEmpty != nil
            && (!currentPassword.isEmpty || session.profile.profile?.hasPassword == false)
            && newPassword == confirmation && !loadingPicture
            && !session.profile.isSaving && !session.profile.isLoading && !session.profile.needsSaveReadback
    }

    private func save() async {
        guard canSave else { return }
        let outcome = await session.profile.save(
            name: name,
            audioLanguage: audioLanguage,
            subtitleLanguage: subtitleLanguage,
            currentPassword: currentPassword,
            newPassword: newPassword,
            picture: picture
        )
        currentPassword = ""
        if session.profile.didSavePicture {
            picture = nil
        }
        app.synchronizeProfile(from: session)
        guard outcome == .confirmed else { return }
        populateFields()
        #if os(iOS) || os(tvOS)
            dismiss()
        #else
            saved = true
        #endif
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
        currentPassword = ""
        newPassword = ""
        confirmation = ""
        picture = nil
        ready = true
    }
}
