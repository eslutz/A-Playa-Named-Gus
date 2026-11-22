import Foundation
import JellyfinAPI
import Observation

enum ProfilePictureChange: Equatable {
    case unchanged
    case replace(Data)
    case remove

    func preview(current: Data?) -> Data? {
        switch self {
        case .unchanged: current
        case let .replace(data): data
        case .remove: nil
        }
    }
}

enum QuickConnectAuthorizationResult: Equatable {
    case authorized
    case rejected
    case unavailable
    case unconfirmed
}

/// Authenticated, session-scoped profile state. Secrets never enter image URLs.
@MainActor @Observable
final class UserProfileStore {
    private let client: JellyfinClient
    private let userID: String
    private let verificationSessionConfiguration: URLSessionConfiguration
    private(set) var profile: UserDto?
    private(set) var imageData: Data?
    private(set) var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?
    private(set) var saveOutcome: ActionOutcome?
    private(set) var currentUsernameAfterPartialSave: String?
    private(set) var needsSaveReadback = false
    private(set) var didSavePicture = false
    private var isActive = true
    private(set) var quickConnectEnabled = false
    private(set) var isAuthorizingQuickConnect = false

    init(client: JellyfinClient, userID: String, verificationSessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.verificationSessionConfiguration = verificationSessionConfiguration
        self.client = client
        self.userID = userID
    }

    func invalidate() {
        isActive = false
        saveOutcome = nil
    }

    func refreshQuickConnectAvailability() async {
        guard isActive else { return }
        let enabled: Bool
        do {
            let result = try await client.send(Paths.getQuickConnectEnabled)
            enabled = try QuickConnectAvailability.isEnabled(result.value)
        } catch {
            enabled = false
        }
        guard isActive, !Task.isCancelled else { return }
        quickConnectEnabled = enabled
    }

    static func validQuickConnectCode(_ code: String) -> Bool {
        code.utf8.count == 6 && code.utf8.allSatisfy { (48 ... 57).contains($0) }
    }

    func authorizeQuickConnect(code: String) async -> QuickConnectAuthorizationResult? {
        guard isActive, quickConnectEnabled, !isAuthorizingQuickConnect, Self.validQuickConnectCode(code) else { return nil }
        isAuthorizingQuickConnect = true
        defer { isAuthorizingQuickConnect = false }
        do {
            let reply = try await client.send(Paths.authorizeQuickConnect(code: code, userID: userID))
            guard isActive, !Task.isCancelled else { return nil }
            return try JSONDecoder().decode(Bool.self, from: reply.value) ? .authorized : .rejected
        } catch {
            guard isActive, !Task.isCancelled else { return nil }
            switch GusError(from: error) {
            case .notFound: return .rejected
            case .unauthorized, .forbidden: return .unavailable
            default: return .unconfirmed
            }
        }
    }

    func load() async {
        guard !isSaving else { return }
        await refresh()
    }

    private func refresh() async {
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

    /// Authenticate before the first edit. Change the password last, once the other
    /// fields have been read back, so a partial save can still use the old password.
    @discardableResult
    func save(
        name: String,
        audioLanguage: String,
        subtitleLanguage: String,
        currentPassword: String,
        newPassword: String = "",
        picture: ProfilePictureChange = .unchanged
    ) async -> ActionOutcome? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, !isSaving, !isLoading, !needsSaveReadback, !name.isEmpty else { return nil }
        isSaving = true
        defer { isSaving = false }
        saveOutcome = .pending
        didSavePicture = false
        errorMessage = nil
        currentUsernameAfterPartialSave = nil
        let audio = audioLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitles = subtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        var transmitted = false
        var usernameAccepted = false
        var passwordSubmitted = false
        var profileEditsConfirmed = false
        do {
            var current = try await client.send(Paths.getUserByID(userID: userID)).value
            guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: false) }
            guard current.id == userID, let username = current.name else { throw GusError.forbidden }
            guard !currentPassword.isEmpty || current.hasPassword == false else {
                throw GusError.server(String(localized: "Enter your current Jellyfin password to save profile changes."))
            }
            let preferencesChanged = (current.configuration?.audioLanguagePreference ?? "") != audio
                || (current.configuration?.subtitleLanguagePreference ?? "") != subtitles
            let profileChanged = username != name || preferencesChanged || picture != .unchanged
            if profileChanged || newPassword.isEmpty {
                try await verifyPassword(currentPassword, username: username)
                guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: false) }
            }
            if profileChanged {
                if username != name {
                    current.name = name
                    transmitted = true
                    try await client.send(Paths.updateUser(userID: userID, current))
                    usernameAccepted = true
                    guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: true) }
                }
                if preferencesChanged {
                    var configuration = current.configuration ?? UserConfiguration()
                    configuration.audioLanguagePreference = audio.isEmpty ? nil : audio
                    configuration.subtitleLanguagePreference = subtitles.isEmpty ? nil : subtitles
                    transmitted = true
                    try await client.send(Paths.updateUserConfiguration(userID: userID, configuration))
                    guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: true) }
                }
                switch picture {
                case .unchanged:
                    break
                case .remove:
                    if current.primaryImageTag != nil {
                        transmitted = true
                        try await client.send(Paths.deleteUserImage(userID: userID))
                        guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: true) }
                    }
                case let .replace(picture):
                    // Jellyfin's image controller decodes a base64 body with an image MIME type.
                    let body = picture.base64EncodedData()
                    let configure: @Sendable (inout URLRequest) -> Void = { request in
                        request.httpBody = body
                        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
                    }
                    transmitted = true
                    try await client.send(Paths.postUserImage(userID: userID), configure: configure)
                    guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: true) }
                }
                saveOutcome = .accepted
                await refresh()
                guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: true) }
                let pictureConfirmed = switch picture {
                case .unchanged: true
                case .remove: profile?.primaryImageTag == nil
                case let .replace(data): profile?.primaryImageTag != nil && (profile?.primaryImageTag != current.primaryImageTag || imageData == data)
                }
                guard errorMessage == nil, profile?.name == name,
                      (profile?.configuration?.audioLanguagePreference ?? "") == audio,
                      (profile?.configuration?.subtitleLanguagePreference ?? "") == subtitles, pictureConfirmed
                else {
                    saveOutcome = .uncertain
                    needsSaveReadback = true
                    errorMessage = String(localized: "Jellyfin accepted the changes, but the saved profile could not be confirmed. Reload the profile before trying again.")
                    return saveOutcome
                }
                profileEditsConfirmed = true
                didSavePicture = picture != .unchanged
            }
            if !newPassword.isEmpty {
                // Explicitly identify our own user so Jellyfin checks CurrentPw even for admins.
                transmitted = true
                passwordSubmitted = true
                try await client.send(Paths.updateUserPassword(userID: userID, .init(currentPw: currentPassword, newPw: newPassword)))
                guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: true) }
                profile?.hasPassword = true
            }
            saveOutcome = .confirmed
            return saveOutcome
        } catch {
            guard isActive else { return nil }
            let failure = GusError(from: error)
            if failure.isCancellation || Task.isCancelled {
                return cancelSave(afterTransmission: transmitted)
            }
            guard transmitted else {
                errorMessage = failure.localizedDescription
                saveOutcome = .failed(failure)
                return saveOutcome
            }
            let uncertain: Bool = switch failure {
            case .timeout, .offline, .network, .server: true
            default: false
            }
            await refresh()
            guard isActive, !Task.isCancelled else { return cancelSave(afterTransmission: true) }
            let usernameConfirmed = usernameAccepted && errorMessage == nil && profile?.name == name
            let unconfirmedUsername = usernameAccepted && !usernameConfirmed
            let outcome: ActionOutcome = uncertain || unconfirmedUsername ? .uncertain : .failed(failure)
            if usernameConfirmed {
                currentUsernameAfterPartialSave = profile?.name
            }
            if passwordSubmitted, uncertain {
                errorMessage = String(localized: "Jellyfin may have changed your password. Check which password works before trying again.")
            } else if passwordSubmitted, failure == .forbidden {
                errorMessage = String(localized: "Jellyfin could not change your password. Check your current password and account permissions.")
            } else if usernameConfirmed {
                errorMessage = String(localized: "Your username was saved. Some other changes could not be confirmed.") + " " + failure.localizedDescription
            } else if unconfirmedUsername || uncertain {
                errorMessage = String(localized: "Jellyfin may have saved some changes. Reload the profile before trying again.")
            } else {
                errorMessage = failure.localizedDescription
            }
            if profileEditsConfirmed, let message = errorMessage {
                errorMessage = String(localized: "Your other profile changes were saved.") + " " + message
            }
            needsSaveReadback = uncertain || unconfirmedUsername
            saveOutcome = outcome
            return outcome
        }
    }

    private func verifyPassword(_ password: String, username: String) async throws {
        // Authenticating the real device ID would revoke its active token. Use a
        // separate device identity and close that session before editing the profile.
        let active = client.configuration
        let verifier = JellyfinClient(configuration: .init(
            url: active.url, client: active.client, deviceName: active.deviceName,
            deviceID: active.deviceID + "-profile-verification", version: active.version
        ), sessionConfiguration: verificationSessionConfiguration)
        let result: AuthenticationResult
        do {
            result = try await verifier.signIn(username: username, password: password)
        } catch {
            if GusError(from: error) == .unauthorized {
                throw GusError.server(String(localized: "Jellyfin could not verify your current password."))
            }
            throw error
        }
        // Cancellation must not strand the verification token. Sessions/Logout
        // revokes only this client, unlike the administrative API-key endpoint.
        _ = try await Task { try await verifier.send(Paths.reportSessionEnded) }.value
        guard result.user?.id == userID else { throw GusError.forbidden }
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
