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
    @State private var picture: ProfilePictureChange = .unchanged
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
            Section {
                ProfilePicturePicker(
                    current: session.profile.imageData, hasServerPicture: session.profile.profile?.primaryImageTag != nil,
                    picture: $picture, isLoading: $loadingPicture
                )
                TextField("Username", text: $name).autocorrectionDisabled().gusAccountNameInput()
                Text("Changing your username also changes the name you use to sign in to Jellyfin.").font(.footnote)
            }
            Section("Jellyfin Playback Preferences") {
                languagePicker("Audio Language", selection: $audioLanguage)
                languagePicker("Subtitle Language", selection: $subtitleLanguage)
            }
            Section {
                NewPasswordField(title: "New Password", value: $newPassword)
                NewPasswordField(title: "Confirm New Password", value: $confirmation)
                if !confirmation.isEmpty, confirmation != newPassword {
                    Text("The new passwords do not match.").font(.footnote)
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
            if session.profile.quickConnectEnabled {
                Section("Quick Connect") {
                    NavigationLink("Authorize Another Device") { ProfileQuickConnectView() }
                        .accessibilityIdentifier("Profile.quickConnect")
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
        .task { await session.profile.refreshQuickConnectAvailability() }
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
            || !newPassword.isEmpty || !confirmation.isEmpty || picture != .unchanged
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
            picture = .unchanged
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
        picture = .unchanged
        ready = true
    }
}

private struct NewPasswordField: View {
    private enum Input { case secure, visible }

    let title: LocalizedStringKey
    @Binding var value: String
    @State private var revealed = false
    @FocusState private var focused: Input?

    var body: some View {
        HStack {
            Group {
                if revealed {
                    TextField(title, text: $value)
                        .focused($focused, equals: .visible)
                        .privacySensitive()
                        .autocorrectionDisabled()
                        .gusAccountNameInput()
                } else {
                    SecureField(title, text: $value)
                        .focused($focused, equals: .secure)
                }
            }
            .textContentType(.newPassword)
            Button {
                let wasEditing = focused != nil
                revealed.toggle()
                if wasEditing {
                    focused = revealed ? .visible : .secure
                }
            } label: {
                Label(revealed ? "Hide Password" : "Show Password", systemImage: revealed ? "eye.slash" : "eye")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityHint(Text(title))
        }
    }
}

private struct ProfileQuickConnectView: View {
    @Environment(SessionStore.self) private var session
    @State private var code = ""
    @State private var result: QuickConnectAuthorizationResult?
    @State private var submission: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextField("Six-digit code", text: $code)
                    .textContentType(.oneTimeCode)
                    .autocorrectionDisabled()
                    .privacySensitive()
                #if os(iOS) || os(visionOS)
                    .keyboardType(.numberPad)
                #endif
                    .disabled(session.profile.isAuthorizingQuickConnect)
                    .onChange(of: code) { _, value in
                        if !value.isEmpty {
                            result = nil
                        }
                    }
                Button("Authorize Device") {
                    let submitted = code
                    submission = Task {
                        let reply = await session.profile.authorizeQuickConnect(code: submitted)
                        guard let reply, !Task.isCancelled else { return }
                        code = ""
                        result = reply
                    }
                }
                .disabled(!UserProfileStore.validQuickConnectCode(code) || session.profile.isAuthorizingQuickConnect)
            } footer: {
                Text("Enter the Quick Connect code shown on the device you want to sign in to this Jellyfin account.")
            }
            if session.profile.isAuthorizingQuickConnect {
                ProgressView()
            }
            switch result {
            case .authorized: Text("Device authorized.")
            case .rejected: Text("That code is invalid or has expired. Get a new code on the other device.")
            case .unavailable: Text("Quick Connect is unavailable for this account or server.")
            case .unconfirmed: Text("Authorization could not be confirmed. Check the other device before trying again.")
            case nil: EmptyView()
            }
        }
        .navigationTitle("Quick Connect")
        .onDisappear { submission?.cancel() }
    }
}
