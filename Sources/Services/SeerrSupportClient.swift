import Foundation

extension SeerrClient {
    func issues(filter: SeerrIssueFilter = .all, createdBy: Int? = nil, take: Int = 20, skip: Int = 0) async throws -> SeerrIssuePage {
        var query = supportPage(take: take, skip: skip)
        query.append(URLQueryItem(name: "filter", value: filter.rawValue))
        if let createdBy {
            query.append(URLQueryItem(name: "createdBy", value: String(createdBy)))
        }
        return try await get("issue", query: query)
    }

    func issue(id: Int) async throws -> SeerrIssue {
        guard id > 0 else { throw SeerrClientError.invalidPayload }
        return try await get("issue/\(id)")
    }

    /// Reporting uses Seerr's internal media ID, not its TMDB ID.
    func reportIssue(mediaID: Int, type: SeerrIssueType, message: String, season: Int? = nil, episode: Int? = nil) async throws -> SeerrIssue {
        let user = try await me()
        guard user.canCreateIssues else { throw SeerrClientError.forbidden }
        guard mediaID > 0, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              season.map({ $0 >= 0 }) ?? true, episode.map({ $0 >= 0 }) ?? true
        else { throw SeerrClientError.invalidPayload }
        return try await send("issue", body: SeerrIssueBody(
            mediaId: mediaID,
            issueType: type.rawValue,
            message: message,
            problemSeason: season,
            problemEpisode: episode
        ), mutation: true)
    }

    func commentOnIssue(id: Int, message: String) async throws -> SeerrIssue {
        let user = try await me()
        let current = try await issue(id: id)
        guard current.canModify(user: user) else { throw SeerrClientError.forbidden }
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SeerrClientError.invalidPayload }
        return try await send("issue/\(id)/comment", body: SeerrCommentBody(message: message), mutation: true)
    }

    func setIssueResolved(id: Int, resolved: Bool) async throws -> SeerrIssue {
        let user = try await me()
        let current = try await issue(id: id)
        guard current.canModify(user: user) else { throw SeerrClientError.forbidden }
        let data = try await perform("issue/\(id)/\(resolved ? "resolved" : "open")", method: "POST", mutation: true)
        return try decode(data, mutation: true)
    }

    func blocklist(take: Int = 20, skip: Int = 0, search: String = "") async throws -> SeerrBlocklistPage {
        var query = supportPage(take: take, skip: skip)
        if !search.isEmpty {
            query.append(URLQueryItem(name: "search", value: search))
        }
        return try await get("blocklist", query: query)
    }

    func addToBlocklist(title: SeerrTitle) async throws {
        let user = try await me()
        guard user.canManageBlocklist else { throw SeerrClientError.forbidden }
        guard let type = title.mediaType, type == .movie || type == .tv, title.id > 0 else { throw SeerrClientError.invalidPayload }
        let body = SeerrBlocklistBody(tmdbId: title.id, mediaType: type, title: title.displayTitle, user: user.id)
        _ = try await perform("blocklist", method: "POST", body: JSONEncoder().encode(body), mutation: true)
    }

    /// The upstream removal also removes Seerr's associated media record and history; callers must disclose that in confirmation.
    func removeFromBlocklist(tmdbID: Int, mediaType: SeerrMediaType) async throws {
        let user = try await me()
        guard user.canManageBlocklist else { throw SeerrClientError.forbidden }
        guard tmdbID > 0, mediaType == .movie || mediaType == .tv else { throw SeerrClientError.invalidPayload }
        _ = try await perform("blocklist/\(tmdbID)", method: "DELETE", query: [URLQueryItem(name: "mediaType", value: mediaType.rawValue)], mutation: true)
    }

    func regions() async throws -> [SeerrRegion] {
        try await get("regions")
    }

    func languages() async throws -> [SeerrLanguage] {
        try await get("languages")
    }

    func regionalPreferences() async throws -> SeerrRegionalPreferences {
        let user = try await me()
        let values: [String: SeerrSettingValue] = try await get("user/\(user.id)/settings/main")
        return SeerrRegionalPreferences(
            discoverRegion: values["discoverRegion"]?.string ?? "",
            streamingRegion: values["streamingRegion"]?.string ?? "",
            originalLanguage: values["originalLanguage"]?.string ?? ""
        )
    }

    func updateRegionalPreferences(_ preferences: SeerrRegionalPreferences, changedFields: SeerrRegionalPreferenceFields = .all) async throws {
        guard !changedFields.isEmpty else { return }
        let user = try await me()
        var values: [String: SeerrSettingValue] = try await get("user/\(user.id)/settings/main")
        if changedFields.contains(.discovery) {
            values["discoverRegion"] = .string(preferences.discoverRegion)
        }
        if changedFields.contains(.streaming) {
            values["streamingRegion"] = .string(preferences.streamingRegion)
        }
        if changedFields.contains(.language) {
            values["originalLanguage"] = .string(preferences.originalLanguage)
        }
        let _: [String: SeerrSettingValue] = try await send("user/\(user.id)/settings/main", body: values, mutation: true)
    }

    func emailNotificationPreferences() async throws -> SeerrEmailNotificationPreferences {
        let user = try await me()
        let values: [String: SeerrSettingValue] = try await get("user/\(user.id)/settings/notifications")
        return SeerrEmailNotificationPreferences(
            enabled: values["emailEnabled"]?.boolean == true,
            events: values["notificationTypes"]?.object?["email"]?.integer ?? 8190
        )
    }

    /// Fetch and merge inside the actor so provider tokens are neither exposed to forms nor accidentally cleared.
    func updateEmailNotificationPreferences(events: Int, changedMask: Int = SeerrEmailNotificationPreferences.editableEventsMask) async throws {
        guard events >= 0, changedMask >= 0 else { throw SeerrClientError.invalidPayload }
        let changedMask = changedMask & SeerrEmailNotificationPreferences.editableEventsMask
        guard changedMask != 0 else { return }
        let user = try await me()
        var values: [String: SeerrSettingValue] = try await get("user/\(user.id)/settings/notifications")
        guard values["emailEnabled"]?.boolean == true else { throw SeerrClientError.forbidden }
        var types = values["notificationTypes"]?.object ?? [:]
        let current = types["email"]?.integer ?? 8190
        types["email"] = .integer((current & ~changedMask) | (events & changedMask))
        values["notificationTypes"] = .object(types)
        let _: [String: SeerrSettingValue] = try await send("user/\(user.id)/settings/notifications", body: values, mutation: true)
    }

    private func supportPage(take: Int, skip: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "take", value: String(min(100, max(1, take)))), URLQueryItem(name: "skip", value: String(max(0, skip)))]
    }
}

private struct SeerrIssueBody: Encodable {
    let mediaId: Int
    let issueType: Int
    let message: String
    let problemSeason: Int?
    let problemEpisode: Int?
}

private struct SeerrCommentBody: Encodable { let message: String }
private struct SeerrBlocklistBody: Encodable {
    let tmdbId: Int
    let mediaType: SeerrMediaType
    let title: String
    let user: Int
}
