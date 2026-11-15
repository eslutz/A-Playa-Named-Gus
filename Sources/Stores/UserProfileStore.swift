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
    private(set) var saveOutcome: ActionOutcome?
    private(set) var currentUsernameAfterPartialSave: String?
    private(set) var needsSaveReadback = false
    private var isActive = true

    init(client: JellyfinClient, userID: String) {
        self.client = client
        self.userID = userID
    }

    func invalidate() {
        isActive = false
        saveOutcome = nil
    }

    func load() async {
        guard isActive, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let value = try await client.send(Paths.getUserByID(userID: userID)).value
            guard isActive, !Task.isCancelled else { return }
            if profile?.primaryImageTag != value.primaryImageTag {
                imageData = nil
            }
            profile = value
            errorMessage = nil
            needsSaveReadback = false
            currentUsernameAfterPartialSave = nil
            if !isSaving {
                saveOutcome = nil
            }
            if let tag = value.primaryImageTag {
                // An optional image failure must not invalidate a confirmed profile
                // refresh or save. Preserve cached data only for the same image tag.
                if let data = try? await client.send(Paths.getUserImage(parameters: .init(userID: userID, tag: tag))).value {
                    guard isActive, !Task.isCancelled else { return }
                    imageData = data
                }
            } else {
                imageData = nil
            }
        } catch {
            guard isActive, !Task.isCancelled else { return }
            errorMessage = GusError(from: error).localizedDescription
        }
    }

    /// Fetch before updating so unrelated server settings are preserved. A write
    /// response is accepted until canonical profile readback confirms its values.
    @discardableResult
    func save(name: String, audioLanguage: String, subtitleLanguage: String) async -> ActionOutcome? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, !isSaving, !isLoading, !needsSaveReadback, !name.isEmpty else { return nil }
        isSaving = true
        saveOutcome = .pending
        currentUsernameAfterPartialSave = nil
        let audio = audioLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitles = subtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        var transmitted = false
        var usernameAccepted = false
        defer { isSaving = false }
        do {
            var current = try await client.send(Paths.getUserByID(userID: userID)).value
            guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: transmitted) }
            if current.name != name {
                current.name = name
                transmitted = true
                try await client.send(Paths.updateUser(userID: userID, current))
                usernameAccepted = true
                guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: transmitted) }
            }
            var configuration = current.configuration ?? UserConfiguration()
            configuration.audioLanguagePreference = audio.isEmpty ? nil : audio
            configuration.subtitleLanguagePreference = subtitles.isEmpty ? nil : subtitles
            transmitted = true
            try await client.send(Paths.updateUserConfiguration(userID: userID, configuration))
            guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: transmitted) }
            saveOutcome = .accepted
            await load()
            guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: transmitted) }
            guard errorMessage == nil, profile?.name == name,
                  (profile?.configuration?.audioLanguagePreference ?? "") == audio,
                  (profile?.configuration?.subtitleLanguagePreference ?? "") == subtitles
            else {
                saveOutcome = .uncertain
                needsSaveReadback = true
                errorMessage = String(localized: "Jellyfin accepted the changes, but the saved profile could not be confirmed. Reload the profile before trying again.")
                return saveOutcome
            }
            saveOutcome = .confirmed
            return saveOutcome
        } catch {
            guard isActive else { return nil }
            let failure = GusError(from: error)
            if failure.isCancellation || Task.isCancelled {
                return cancelSave(afterTransmission: transmitted)
            }
            let uncertain: Bool = switch failure {
            case .timeout, .offline, .network: transmitted
            default: false
            }
            // A preceding update may have succeeded. Read current values without
            // converting a rejected or uncertain write into apparent success.
            await load()
            guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: transmitted) }
            let usernameConfirmed = usernameAccepted && errorMessage == nil && profile?.name == name
            let unconfirmedUsername = usernameAccepted && !usernameConfirmed
            let outcome: ActionOutcome = uncertain || unconfirmedUsername ? .uncertain : .failed(failure)
            let message: String
            if usernameConfirmed {
                currentUsernameAfterPartialSave = profile?.name
                message = uncertain
                    ? String(localized: "Your username was saved, but the playback preferences could not be confirmed. Reload the profile before trying again.")
                    : String(localized: "Your username was saved. The playback preferences were not saved. Check the current username below before signing in again.") + " " + failure.localizedDescription
            } else if unconfirmedUsername {
                message = String(localized: "Jellyfin accepted the username change, but its current profile could not be confirmed. Reload the profile before trying again.")
            } else {
                message = uncertain
                    ? String(localized: "Jellyfin may have saved some changes. Reload the profile before trying again.")
                    : failure.localizedDescription
            }
            needsSaveReadback = uncertain || unconfirmedUsername
            errorMessage = message
            saveOutcome = outcome
            return outcome
        }
    }

    private func cancelSave(afterTransmission transmitted: Bool) -> ActionOutcome? {
        saveOutcome = nil
        guard isActive, transmitted else { return nil }
        needsSaveReadback = true
        currentUsernameAfterPartialSave = nil
        errorMessage = String(localized: "Jellyfin may have saved some changes. Reload the profile before trying again.")
        return nil
    }
}
