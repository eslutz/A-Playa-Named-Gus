import SwiftUI

struct UserProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var audioLanguage = ""
    @State private var subtitleLanguage = ""
    @State private var ready = false
    @State private var saved = false

    var body: some View {
        Form {
            Section("Profile") {
                ProfileAvatar(data: session.profile.imageData)
                TextField("Username", text: $name)
                Text("Changing your username also changes the name you use to sign in to Jellyfin.").font(.footnote)
            }
            Section("Jellyfin Playback Preferences") {
                languagePicker("Preferred audio language", selection: $audioLanguage)
                languagePicker("Preferred subtitle language", selection: $subtitleLanguage)
            }
            if let message = session.profile.errorMessage {
                Section {
                    Text(message)
                    Button("Reload Profile") { Task { await load() } }
                }
            }
            if saved {
                Text("Profile saved to Jellyfin.")
            }
            Button("Save Changes") {
                Task {
                    saved = await session.profile.save(name: name, audioLanguage: audioLanguage, subtitleLanguage: subtitleLanguage)
                    app.synchronizeProfile(from: session)
                }
            }.disabled(!ready || name.trimmedNilIfEmpty == nil || (session.profile.isSaving || session.profile.isLoading))
        }
        .disabled(session.profile.isSaving || session.profile.isLoading)
        .navigationTitle("Profile")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task { await load() }
        .onChange(of: session.profile.profile) { _, _ in
            if !ready {
                populateFields()
            }
        }
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
        populateFields()
    }

    private func populateFields() {
        guard let profile = session.profile.profile else { return }
        name = profile.name ?? session.user.name
        audioLanguage = profile.configuration?.audioLanguagePreference ?? ""
        subtitleLanguage = profile.configuration?.subtitleLanguagePreference ?? ""
        ready = true
    }
}
