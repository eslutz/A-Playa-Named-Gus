import Foundation
import JellyfinAPI
import Observation

/// Authenticated, session-scoped profile state. Secrets never enter image URLs.
@MainActor @Observable
final class UserProfileStore {
    private let client: JellyfinClient
    private let userID: String
    private(set) var profile: UserDto?
    private(set) var imageData: Data?
    private(set) var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?

    init(client: JellyfinClient, userID: String) {
        self.client = client
        self.userID = userID
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let value = try await client.send(Paths.getUserByID(userID: userID)).value
            guard !Task.isCancelled else { return }
            if profile?.primaryImageTag != value.primaryImageTag {
                imageData = nil
            }
            profile = value
            errorMessage = nil
            if let tag = value.primaryImageTag {
                imageData = try await client.send(Paths.getUserImage(parameters: .init(userID: userID, tag: tag))).value
            } else {
                imageData = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Fetch before updating so unrelated server settings are preserved.
    func save(name: String, audioLanguage: String, subtitleLanguage: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSaving, !isLoading, !name.isEmpty else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            var current = try await client.send(Paths.getUserByID(userID: userID)).value
            if current.name != name {
                current.name = name
                try await client.send(Paths.updateUser(userID: userID, current))
            }
            var configuration = current.configuration ?? UserConfiguration()
            let audio = audioLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitles = subtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            configuration.audioLanguagePreference = audio.isEmpty ? nil : audio
            configuration.subtitleLanguagePreference = subtitles.isEmpty ? nil : subtitles
            try await client.send(Paths.updateUserConfiguration(userID: userID, configuration))
            await load()
            return errorMessage == nil
        } catch {
            errorMessage = error.localizedDescription
            // A preceding request may have succeeded. Reload canonical server state
            // without hiding the failed operation from the editor.
            let failure = errorMessage
            await load()
            errorMessage = failure
            return false
        }
    }
}
