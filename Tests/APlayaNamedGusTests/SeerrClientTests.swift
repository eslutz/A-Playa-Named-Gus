import Foundation
@testable import Gus
import os
import Testing

@Suite("Seerr contracts and isolation")
struct SeerrClientTests {
    @Test("4K-only requesters can open review independently of standard availability", arguments: [SeerrMediaStatus.available, .pending, .processing])
    func fourKReviewEntry(standard: SeerrMediaStatus) throws {
        var title = try Self.title(#"{"id":10,"mediaType":"movie","mediaInfo":{"id":1,"status":5,"status4k":1}}"#)
        title.mediaInfo?.status = standard
        let user = SeerrUser(id: 1, permissions: .request4KMovie)
        #expect(SeerrRequestEligibility.canOpenReview(title: title, type: .movie, user: user))
        #expect(SeerrRequestEligibility.canOpenReview(title: title, type: .movie, user: SeerrUser(id: 2, permissions: .admin)))
    }

    @Test("review entry respects format permissions, availability and global blocklisting")
    func reviewEntryBoundaries() throws {
        var title = try Self.title(#"{"id":10,"mediaType":"movie","mediaInfo":{"id":1,"status":5,"status4k":1}}"#)
        let standard = SeerrUser(id: 1, permissions: .requestMovie)
        let administrator = SeerrUser(id: 2, permissions: .admin)
        #expect(!SeerrRequestEligibility.canOpenReview(title: title, type: .movie, user: standard))
        #expect(!SeerrRequestEligibility.canOpenReview(title: title, type: .movie, user: nil))
        title.mediaInfo?.status4k = .available
        #expect(!SeerrRequestEligibility.canOpenReview(title: title, type: .movie, user: administrator))
        title.mediaInfo?.status = .notRequested
        #expect(SeerrRequestEligibility.canOpenReview(title: title, type: .movie, user: standard))
        title.mediaInfo?.status = .blocklisted
        title.mediaInfo?.status4k = .notRequested
        #expect(!SeerrRequestEligibility.canOpenReview(title: title, type: .movie, user: administrator))
        title.mediaInfo?.status = .processing
        #expect(SeerrRequestEligibility.canOpenReview(title: title, type: .tv, user: SeerrUser(id: 3, permissions: .requestTV)))
    }

    @Test("normalizes secure defaults, ports and reverse-proxy base paths")
    func normalizesURLs() throws {
        #expect(try SeerrClient.normalizeURL(" media.example:5055/seerr/ ").absoluteString == "https://media.example:5055/seerr")
        #expect(try SeerrClient.normalizeURL("https://MEDIA.example/seerr/api/v1/").absoluteString == "https://media.example/seerr")
        #expect(try SeerrClient.normalizeURL("http://127.0.0.1:5055///").absoluteString == "http://127.0.0.1:5055")
    }

    @Test("rejects credential-bearing, ambiguous and non-HTTP addresses", arguments: [
        "", "https://", "file:///tmp/seerr", "ftp://media.example", "https://user:password@media.example",
        "https://media.example?apiKey=secret", "https://media.example/#token", "https://media.example/a/../b",
        "https://media.example/seerr/%2fprivate", "https://media.example:70000", "https://media.example/a//b",
    ])
    func rejectsInvalidURLs(raw: String) {
        #expect(throws: SeerrClientError.invalidURL) { try SeerrClient.normalizeURL(raw) }
    }

    @Test("accepts only the verified stable Seerr major")
    func supportedVersions() {
        for version in ["3.0.0", "v3.5.1", "3.100.0"] {
            #expect(SeerrStatus(version: version).isSupported)
        }
        for version in ["2.7.3", "4.0.0", "3.0", "3.5.1-develop", "develop-123", "3..0", "3.5.1+abc"] {
            #expect(!SeerrStatus(version: version).isSupported)
        }
    }

    @Test("unknown numeric statuses fail closed and malformed statuses fail decoding")
    func statuses() throws {
        let decoder = JSONDecoder()
        let status = try decoder.decode(SeerrMediaStatus.self, from: Data("99".utf8))
        #expect(status == .unknown(99))
        #expect(!status.isRequestable)
        #expect(try decoder.decode(SeerrMediaStatus.self, from: Data("6".utf8)) == .blocklisted)
        #expect(try decoder.decode(SeerrMediaStatus.self, from: Data("7".utf8)) == .deleted)
        #expect(throws: DecodingError.self) { try decoder.decode(SeerrRequestStatus.self, from: Data(#""pending""#.utf8)) }
        let user = SeerrUser(id: 2, permissions: .admin)
        #expect(!SeerrRequest(id: 1, status: .unknown(9)).canCancel(user: user))
    }

    @Test("permission flags preserve type and 4K boundaries with admin override")
    func permissions() throws {
        let movies = SeerrUser(id: 2, permissions: [.requestMovie, .request4KTV])
        #expect(movies.canRequest(.movie))
        #expect(!movies.canRequest(.tv))
        #expect(!movies.canRequest(.movie, is4K: true))
        #expect(movies.canRequest(.tv, is4K: true))
        #expect(!movies.canRequest(.person))
        #expect(!SeerrUser(id: 2, permissions: .manageRequests).canRequest(.movie))
        #expect(SeerrUser(id: 1, permissions: .admin).canRequest(.tv, is4K: true))
        let decoded = try JSONDecoder().decode(SeerrPermissions.self, from: Data("262144".utf8))
        #expect(decoded == .requestMovie)
    }

    @Test("own cancellation is pending-only and manager moderation respects status")
    func requestActions() {
        let owner = SeerrUser(id: 5, permissions: .request)
        let manager = SeerrUser(id: 6, permissions: .manageRequests)
        let pending = SeerrRequest(id: 10, status: .pending, requestedBy: owner)
        let approved = SeerrRequest(id: 11, status: .approved, requestedBy: owner)
        #expect(pending.canCancel(user: owner))
        #expect(!approved.canCancel(user: owner))
        #expect(pending.canModerate(user: manager))
        #expect(!approved.canModerate(user: manager))
        #expect(!pending.canCancel(user: SeerrUser(id: 7, permissions: .request)))
        #expect(SeerrRequest(id: 12, status: .failed).canRetry(user: manager))
    }

    @Test("quota applies to existing metadata as well as new titles")
    func quotaAndAvailability() throws {
        let title = try Self.title(#"{"id":10,"mediaType":"movie","mediaInfo":{"id":1,"status":1}}"#)
        let settings = SeerrPublicSettings(initialized: true)
        let user = SeerrUser(id: 2, permissions: .request)
        let exhausted = SeerrQuotaStatus(limit: 1, used: 1, remaining: 0, restricted: true)
        let unlimited = SeerrQuotaStatus(used: 99, restricted: false)
        #expect(!SeerrRequestEligibility.canRequest(
            title: title,
            type: .movie,
            user: user,
            settings: settings,
            quota: SeerrQuota(movie: exhausted, tv: unlimited)
        ))
        #expect(SeerrRequestEligibility.canRequest(
            title: title,
            type: .movie,
            user: user,
            settings: settings,
            quota: SeerrQuota(movie: unlimited, tv: unlimited)
        ))
        #expect(!SeerrQuotaStatus(limit: 3, used: 0, restricted: false).allows(count: 1))
        #expect(!SeerrQuotaStatus(limit: 3, used: 2, remaining: 1, restricted: false).allows(count: 2))
    }

    @Test("season eligibility omits empty, unavailable, covered and disabled specials")
    func seasonEligibility() throws {
        let title = try Self.title(#"{"id":10,"mediaType":"tv","seasons":[{"seasonNumber":0,"episodeCount":2},{"seasonNumber":1,"episodeCount":10},{"seasonNumber":2,"episodeCount":8},{"seasonNumber":3,"episodeCount":0},{"seasonNumber":4,"episodeCount":7}],"mediaInfo":{"id":1,"status":4,"seasons":[{"seasonNumber":1,"status":5},{"seasonNumber":2,"status":1},{"seasonNumber":4,"status":99}]}}"#)
        var settings = SeerrPublicSettings(initialized: true, partialRequestsEnabled: false, enableSpecialEpisodes: false)
        #expect(SeerrRequestEligibility.requestableSeasons(title: title, settings: settings) == [2])
        settings.enableSpecialEpisodes = true
        #expect(SeerrRequestEligibility.requestableSeasons(title: title, settings: settings) == [0, 2])
        let quota = SeerrQuotaStatus(limit: 2, used: 0, remaining: 2, restricted: false)
        let user = SeerrUser(id: 2, permissions: .request)
        #expect(!SeerrRequestEligibility.canRequest(
            title: title,
            type: .tv,
            user: user,
            settings: settings,
            quota: SeerrQuota(movie: quota, tv: quota),
            seasons: [2]
        ))
        #expect(SeerrRequestEligibility.canRequest(
            title: title,
            type: .tv,
            user: user,
            settings: settings,
            quota: SeerrQuota(movie: quota, tv: quota),
            seasons: [0, 2]
        ))
    }

    @Test("request payloads encode TMDB identity and explicit deduplicated seasons")
    func payloads() throws {
        let payload = SeerrRequestPayload(
            mediaType: .tv,
            mediaId: 170,
            seasons: [2, 0, 2, 1],
            is4k: true,
            serverId: 0,
            profileId: 4,
            rootFolder: "/tv",
            languageProfileId: 1,
            tags: [3]
        )
        #expect(payload.isValid)
        let decoded = try JSONDecoder().decode(SeerrRequestPayload.self, from: JSONEncoder().encode(payload))
        #expect(decoded.seasons == [0, 1, 2])
        #expect(decoded.mediaId == 170)
        #expect(decoded.is4k)
        #expect(!SeerrRequestPayload(mediaType: .tv, mediaId: 170).isValid)
        #expect(!SeerrRequestPayload(mediaType: .tv, mediaId: 170, seasons: [-1]).isValid)
        #expect(!SeerrRequestPayload(mediaType: .movie, mediaId: 170, seasons: [1]).isValid)
        #expect(!SeerrRequestPayload(mediaType: .person, mediaId: 170).isValid)
    }

    @Test("certification uses official wire keys and the gate's US rating scale")
    func certifications() throws {
        let movie = try Self.title(#"{"id":10,"releases":{"results":[{"iso_3166_1":"US","release_dates":[{"certification":"PG-13","type":3}]}]}}"#)
        #expect(movie.certification == "PG-13")
        let tv = try Self.title(#"{"id":20,"contentRatings":{"results":[{"iso_3166_1":"GB","rating":"15"},{"iso_3166_1":"US","rating":"TV-14"}]}}"#)
        #expect(tv.certification == "TV-14")
        #expect(try Self.title(#"{"id":30}"#).certification == nil)
    }

    @Test("redirect policy rejects other schemes, ports, origins and base paths")
    func redirectIsolation() throws {
        let base = try SeerrClient.normalizeURL("https://media.example/seerr")
        let policy = SeerrRedirectPolicy(baseURL: base)
        #expect(try policy.allows(#require(URL(string: "https://media.example/seerr/api/v1/auth/me"))))
        for url in [
            "https://other.example/seerr",
            "http://media.example/seerr",
            "https://media.example:444/seerr",
            "https://media.example/seerr-other",
            "https://media.example/api/v1",
        ] {
            #expect(try !policy.allows(#require(URL(string: url))))
        }
    }

    @Test("each client owns its cookies even when clients share an injected URLSession")
    func cookieIsolation() async throws {
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"version":"3.5.1"}"#, headers: ["Set-Cookie": "connect.sid=client-A; Path=/; HttpOnly; Secure"]),
            .init(json: #"{"id":2,"permissions":32}"#),
            .init(json: #"{"version":"3.5.1"}"#),
        ])
        let first = try fixture.client()
        let second = try fixture.client()
        _ = try await first.status()
        _ = try await first.me()
        _ = try await second.status()
        let requests = fixture.requests
        #expect(requests.count == 3)
        #expect(requests[0].value(forHTTPHeaderField: "Cookie") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "Cookie") == "connect.sid=client-A")
        #expect(requests[2].value(forHTTPHeaderField: "Cookie") == nil)
        #expect(await first.sessionCookies().count == 1)
        #expect(await second.sessionCookies().isEmpty)
    }

    @Test("restored cookies cannot cross base path, origin or expiry boundaries")
    func restoredCookies() async throws {
        let fixture = SeerrFixture(responses: [.init(json: #"{"version":"3.5.1"}"#)])
        let base = try SeerrClient.normalizeURL("https://media.example/seerr")
        let cookie = SeerrSessionCookie(origin: base, name: "connect.sid", value: "secret", path: "/", expiresAt: nil, secure: true)
        let data = try JSONEncoder().encode([cookie])
        #expect(try JSONDecoder().decode([SeerrSessionCookie].self, from: data) == [cookie])
        let different = try fixture.client(base: "https://media.example/other", cookies: [cookie])
        #expect(await different.sessionCookies().isEmpty)
        let expired = SeerrSessionCookie(origin: base, name: "connect.sid", value: "expired", path: "/", expiresAt: .distantPast, secure: true)
        let client = try fixture.client(cookies: [cookie, expired])
        #expect(await client.sessionCookies() == [cookie])
        _ = try await client.status()
        #expect(fixture.requests.first?.url?.path == "/seerr/api/v1/status")
        #expect(fixture.requests.first?.value(forHTTPHeaderField: "Cookie") == "connect.sid=secret")
    }

    @Test("login consults public settings and sends only the configured Jellyfin login fields")
    func loginContract() async throws {
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"version":"3.0.0"}"#),
            .init(json: #"{"initialized":true,"localLogin":true,"mediaServerLogin":true,"mediaServerType":2}"#),
            .init(json: #"{"id":2,"permissions":32}"#),
        ])
        let client = try fixture.client()
        let user = try await client.loginJellyfin(username: "user", password: "transient-password")
        #expect(user.id == 2)
        let request = try #require(fixture.requests.last)
        #expect(request.url?.path == "/seerr/api/v1/auth/jellyfin")
        let object = try #require(JSONSerialization.jsonObject(with: Self.body(of: request)) as? [String: String])
        #expect(object == ["username": "user", "password": "transient-password"])
        #expect(await client.sessionCookies().isEmpty)
    }

    @Test("creation failures have uncertain outcomes and never automatically replay")
    func uncertainMutation() async throws {
        for response in [SeerrStub(json: "{}", status: 201), SeerrStub(json: "{}", status: 502), SeerrStub(error: URLError(.timedOut))] {
            let fixture = SeerrFixture(responses: [response])
            let client = try fixture.client()
            await #expect(throws: SeerrClientError.mutationOutcomeUnknown) {
                try await client.createRequest(SeerrRequestPayload(mediaType: .movie, mediaId: 10))
            }
            #expect(fixture.requests.count == 1)
        }
    }

    @Test("detail routes restore media type omitted by the server and preserve query escaping")
    func catalogRoutes() async throws {
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"id":123,"title":"Title"}"#),
            .init(json: #"{"page":1,"totalPages":1,"totalResults":0,"results":[]}"#),
        ])
        let client = try fixture.client()
        #expect(try await client.details(mediaType: .movie, id: 123).mediaType == .movie)
        _ = try await client.search(query: "one & two?", page: 2, language: "en")
        let url = try #require(fixture.requests.last?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first(where: { $0.name == "query" })?.value == "one & two?")
        #expect(components.queryItems?.first(where: { $0.name == "page" })?.value == "2")
    }

    @Test("CSRF-protected server cookies supply the mutation header without global storage")
    func csrf() async throws {
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"version":"3.5.1"}"#, headers: ["Set-Cookie": "XSRF-TOKEN=server-token; Path=/; Secure"]),
            .init(json: #"{"id":9,"status":1}"#, status: 201),
        ])
        let client = try fixture.client()
        _ = try await client.status()
        _ = try await client.createRequest(SeerrRequestPayload(mediaType: .movie, mediaId: 10))
        #expect(fixture.requests.last?.value(forHTTPHeaderField: "X-CSRF-Token") == "server-token")
    }

    @Test("blocked, undocumented and missing 4K states never enable requests")
    func conservativeEligibility() throws {
        let user = SeerrUser(id: 1, permissions: .admin)
        let settings = SeerrPublicSettings(initialized: true, movie4kEnabled: true)
        let unlimited = SeerrQuotaStatus(used: 0, restricted: false)
        let quota = SeerrQuota(movie: unlimited, tv: unlimited)
        for json in [
            #"{"id":10,"mediaInfo":{"id":1,"status":6,"status4k":1}}"#,
            #"{"id":10,"mediaInfo":{"id":1,"status":99,"status4k":1}}"#,
            #"{"id":10,"mediaInfo":{"id":1,"status":1}}"#,
        ] {
            let title = try Self.title(json)
            #expect(!SeerrRequestEligibility.canRequest(title: title, type: .movie, user: user, settings: settings, quota: quota, is4K: true))
        }
    }

    @Test("issue pagination uses the route's createdBy contract and reporting uses Seerr media identity")
    func issueContracts() async throws {
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"pageInfo":{"pages":0,"pageSize":20,"results":0,"page":1},"results":[]}"#),
            .init(json: #"{"id":3,"permissions":4194304}"#),
            .init(json: #"{"id":7,"issueType":2,"status":1}"#, status: 201),
        ])
        let client = try fixture.client()
        _ = try await client.issues(createdBy: 3, skip: 20)
        let issue = try await client.reportIssue(mediaID: 88, type: .audio, message: "Audio drops out")
        #expect(issue.id == 7)
        let first = try #require(fixture.requests.first?.url)
        let query = try #require(URLComponents(url: first, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first(where: { $0.name == "createdBy" })?.value == "3")
        #expect(!query.contains(where: { $0.name == "requestedBy" }))
        let request = try #require(fixture.requests.last)
        let body = try #require(JSONSerialization.jsonObject(with: Self.body(of: request)) as? [String: Any])
        #expect(body["mediaId"] as? Int == 88)
        #expect(body["issueType"] as? Int == 2)
        #expect(body["userId"] == nil)
    }

    @Test("preference updates merge a fresh full snapshot without dropping profile fields")
    func preserveGeneralPreferences() async throws {
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"id":3,"permissions":32}"#),
            .init(json: #"{"username":"name","email":"example@example.invalid","discordId":"legacy-id","locale":"en","watchlistSyncMovies":true,"streamingRegion":"GB","originalLanguage":"fr","futureField":{"value":7}}"#),
            .init(json: "{}"),
        ])
        let client = try fixture.client()
        try await client.updateRegionalPreferences(SeerrRegionalPreferences(discoverRegion: "US", streamingRegion: "CA", originalLanguage: "en"), changedFields: .discovery)
        let request = try #require(fixture.requests.last)
        let body = try JSONDecoder().decode([String: SeerrSettingValue].self, from: Self.body(of: request))
        #expect(body["discordId"] == .string("legacy-id"))
        #expect(body["username"] == .string("name"))
        #expect(body["watchlistSyncMovies"] == .boolean(true))
        #expect(body["futureField"] == .object(["value": .integer(7)]))
        #expect(body["discoverRegion"] == .string("US"))
        #expect(body["streamingRegion"] == .string("GB"))
        #expect(body["originalLanguage"] == .string("fr"))
    }

    @Test("email event updates preserve notification credentials and unrelated event choices")
    func preserveNotificationPreferences() async throws {
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"id":3,"permissions":32}"#),
            .init(json: #"{"emailEnabled":true,"discordIds":["123"],"pushbulletAccessToken":"synthetic-fixture","notificationTypes":{"email":1048584,"webpush":8190,"futureChannel":64},"futureCredential":"synthetic-future"}"#),
            .init(json: "{}"),
        ])
        let client = try fixture.client()
        try await client.updateEmailNotificationPreferences(events: 4, changedMask: 4)
        let request = try #require(fixture.requests.last)
        let body = try JSONDecoder().decode([String: SeerrSettingValue].self, from: Self.body(of: request))
        #expect(body["pushbulletAccessToken"] == .string("synthetic-fixture"))
        #expect(body["futureCredential"] == .string("synthetic-future"))
        #expect(body["notificationTypes"]?.object?["email"] == .integer(1_048_588))
        #expect(body["notificationTypes"]?.object?["webpush"] == .integer(8190))
        #expect(body["notificationTypes"]?.object?["futureChannel"] == .integer(64))
    }

    @Test("blocklist removal rechecks permission and sends both typed TMDB identity components")
    func blocklistRemoval() async throws {
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"id":3,"permissions":268435456}"#),
            .init(status: 204),
        ])
        try await fixture.client().removeFromBlocklist(tmdbID: 55, mediaType: .tv)
        let request = try #require(fixture.requests.last)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/seerr/api/v1/blocklist/55")
        let url = try #require(request.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first(where: { $0.name == "mediaType" })?.value == "tv")
    }

    @Test("clearing a session rejects a late read before it can restore response cookies")
    func clearSessionRejectsLateRead() async throws {
        let gate = SeerrResponseGate()
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"id":3,"permissions":32}"#, headers: ["Set-Cookie": "connect.sid=late-cookie; Path=/; Secure"], gate: gate),
        ])
        let client = try fixture.client()
        let operation = Task { try await client.me() }
        await gate.waitUntilPaused()
        await client.clearSession()
        gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await client.sessionCookies().isEmpty)
        await #expect(throws: CancellationError.self) { try await client.status() }
        #expect(fixture.requests.count == 1)
    }

    @Test("a deactivated composite support operation cannot dispatch its subsequent POST")
    func clearSessionStopsCompositeSupportMutation() async throws {
        let gate = SeerrResponseGate()
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"id":3,"permissions":4194304}"#, headers: ["Set-Cookie": "connect.sid=late-cookie; Path=/; Secure"], gate: gate),
            .init(json: #"{"version":"3.5.1"}"#),
        ])
        let client = try fixture.client()
        let operation = Task { try await client.reportIssue(mediaID: 88, type: .audio, message: "Synthetic test report") }
        await gate.waitUntilPaused()
        await client.clearSession()
        gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await client.sessionCookies().isEmpty)
        #expect(fixture.requests.count == 1)
        #expect(fixture.requests.first?.httpMethod == "GET")
        #expect(fixture.requests.first?.url?.path == "/seerr/api/v1/auth/me")
        // Deactivation belongs to the client, not its injected transport shared by another client.
        let replacement = try fixture.client()
        #expect(try await replacement.status().version == "3.5.1")
        #expect(fixture.requests.count == 2)
    }

    @Test("a dispatched POST has an uncertain outcome when its client is cleared before the reply")
    func clearSessionPreservesMutationUncertainty() async throws {
        let gate = SeerrResponseGate()
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"id":9,"status":1}"#, status: 201, headers: ["Set-Cookie": "connect.sid=late-cookie; Path=/; Secure"], gate: gate),
        ])
        let client = try fixture.client()
        let operation = Task { try await client.createRequest(SeerrRequestPayload(mediaType: .movie, mediaId: 10)) }
        await gate.waitUntilPaused()
        await client.clearSession()
        gate.release()
        await #expect(throws: SeerrClientError.mutationOutcomeUnknown) { try await operation.value }
        #expect(await client.sessionCookies().isEmpty)
        await #expect(throws: CancellationError.self) { try await client.createRequest(SeerrRequestPayload(mediaType: .movie, mediaId: 10)) }
        #expect(fixture.requests.count == 1)
    }

    @Test("a 401 permanently invalidates sibling reads and their late session cookies")
    func unauthorizedInvalidatesOutstandingResponses() async throws {
        let gate = SeerrResponseGate()
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"id":3,"permissions":32}"#, headers: ["Set-Cookie": "connect.sid=late-cookie; Path=/; Secure"], gate: gate),
            .init(status: 401, headers: ["Set-Cookie": "connect.sid=unauthorized-cookie; Path=/; Secure"]),
        ])
        let client = try fixture.client()
        let operation = Task { try await client.me() }
        await gate.waitUntilPaused()
        await #expect(throws: SeerrClientError.unauthorized) { try await client.status() }
        gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await client.sessionCookies().isEmpty)
        await #expect(throws: SeerrClientError.unauthorized) { try await client.me() }
        #expect(fixture.requests.count == 2)
        await client.clearSession()
        await #expect(throws: CancellationError.self) { try await client.me() }
        #expect(fixture.requests.count == 2)
    }

    @Test("HTTP 429 does not imply that a user's media-request quota is exhausted")
    func throttlingDoesNotInferQuota() async throws {
        let fixture = SeerrFixture(responses: [.init(status: 429), .init(status: 403)])
        let client = try fixture.client()
        await #expect(throws: SeerrClientError.httpStatus(429)) { try await client.status() }
        await #expect(throws: SeerrClientError.forbidden) { try await client.status() }
        #expect(fixture.requests.count == 2)
    }

    @Test("synchronous invalidation rejects late cookies before actor cleanup runs", arguments: [200, 401])
    func synchronousInvalidationRejectsLateCookies(status: Int) async throws {
        let gate = SeerrResponseGate()
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"id":3,"permissions":32}"#, status: status, headers: ["Set-Cookie": "connect.sid=late-cookie; Path=/; Secure"], gate: gate),
        ])
        let client = try fixture.client()
        let operation = Task { try await client.me() }
        await gate.waitUntilPaused()
        client.invalidateSession()
        gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await client.sessionCookies().isEmpty)
        await #expect(throws: CancellationError.self) { try await client.me() }
        #expect(fixture.requests.count == 1)
        await client.clearSession()
        #expect(await client.sessionCookies().isEmpty)
    }

    @Test("synchronous invalidation stops a comment while its internal issue preflight is paused")
    func synchronousInvalidationStopsCompositeContinuation() async throws {
        let gate = SeerrResponseGate()
        let fixture = SeerrFixture(responses: [
            .init(json: #"{"id":3,"permissions":4194304}"#),
            .init(
                json: #"{"id":11,"issueType":2,"status":1,"createdBy":{"id":3,"permissions":4194304}}"#,
                headers: ["Set-Cookie": "connect.sid=late-cookie; Path=/; Secure"],
                gate: gate
            ),
        ])
        let client = try fixture.client()
        let operation = Task { try await client.commentOnIssue(id: 11, message: "Synthetic test comment") }
        await gate.waitUntilPaused()
        client.invalidateSession()
        gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await client.sessionCookies().isEmpty)
        #expect(fixture.requests.map(\.httpMethod) == ["GET", "GET"])
        #expect(fixture.requests.map { $0.url?.path } == ["/seerr/api/v1/auth/me", "/seerr/api/v1/issue/11"])
        await #expect(throws: CancellationError.self) { try await client.commentOnIssue(id: 11, message: "Another comment") }
        #expect(fixture.requests.count == 2)
    }

    private static func title(_ json: String) throws -> SeerrTitle {
        try JSONDecoder().decode(SeerrTitle.self, from: Data(json.utf8))
    }

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count > 0 else { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        return data
    }
}

private struct SeerrStub: Sendable {
    var json = "{}"
    var status = 200
    var headers: [String: String] = [:]
    var error: URLError?
    var gate: SeerrResponseGate?
}

private final class SeerrFixture: Sendable {
    let id = UUID().uuidString
    let state: SeerrProtocolState
    let session: URLSession

    init(responses: [SeerrStub]) {
        state = SeerrProtocolState(responses: responses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SeerrURLProtocol.self]
        configuration.httpAdditionalHeaders = [SeerrURLProtocol.header: id]
        session = URLSession(configuration: configuration)
        SeerrURLProtocol.states.withLock { $0[id] = state }
    }

    deinit {
        session.invalidateAndCancel()
        _ = SeerrURLProtocol.states.withLock { $0.removeValue(forKey: id) }
    }

    var requests: [URLRequest] {
        state.requests
    }

    func client(base: String = "https://media.example/seerr", cookies: [SeerrSessionCookie] = []) throws -> SeerrClient {
        try SeerrClient(baseURL: #require(URL(string: base)), session: session, cookies: cookies)
    }
}

private final class SeerrURLProtocol: URLProtocol {
    static let header = "X-Gus-Seerr-Test-ID"
    static let states = OSAllocatedUnfairLock(initialState: [String: SeerrProtocolState]())
    private let delivery = OSAllocatedUnfairLock<SeerrResponseDelivery?>(initialState: nil)

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: header) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.header),
              let state = Self.states.withLock({ $0[id] }), let url = request.url
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let stub = state.next(request)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers.merging(["Content-Type": "application/json"]) { first, _ in first }
        )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let delivery = SeerrResponseDelivery(owner: self)
        self.delivery.withLock { $0 = delivery }
        let transmit: @Sendable () -> Void = {
            delivery.withOwner { owner in
                if let error = stub.error {
                    owner.client?.urlProtocol(owner, didFailWithError: error)
                } else {
                    owner.client?.urlProtocol(owner, didReceive: response, cacheStoragePolicy: .notAllowed)
                    owner.client?.urlProtocol(owner, didLoad: Data(stub.json.utf8))
                    owner.client?.urlProtocolDidFinishLoading(owner)
                }
            }
        }
        if let gate = stub.gate {
            gate.pause(transmit)
        } else {
            transmit()
        }
    }

    override func stopLoading() {
        let current = delivery.withLock { state in
            let current = state
            state = nil
            return current
        }
        current?.cancel()
    }
}

/// Foundation's protocol handle is deliberately not Sendable. This audited wrapper serializes
/// its weak ownership and callbacks with cancellation; a recursive lock permits reentrant stopLoading.
private final class SeerrResponseDelivery: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private weak var owner: SeerrURLProtocol?
    init(owner: SeerrURLProtocol) {
        self.owner = owner
    }

    func withOwner(_ body: (SeerrURLProtocol) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard let owner else { return }
        body(owner)
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        owner = nil
    }
}

/// The event gate pauses delivery rather than sleeping, so tests control the precise response race.
private final class SeerrResponseGate: Sendable {
    private struct State {
        var paused = false
        var released = false
        var waiters: [CheckedContinuation<Void, Never>] = []
        var transmit: (@Sendable () -> Void)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func waitUntilPaused() async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state in
                if state.paused {
                    return true
                }
                state.waiters.append(continuation)
                return false
            }
            if ready {
                continuation.resume()
            }
        }
    }

    func pause(_ transmit: @escaping @Sendable () -> Void) {
        let delivery = state.withLock { state in
            state.paused = true
            let waiters = state.waiters
            state.waiters = []
            if !state.released {
                state.transmit = transmit
            }
            return (waiters, state.released)
        }
        for waiter in delivery.0 {
            waiter.resume()
        }
        if delivery.1 {
            transmit()
        }
    }

    func release() {
        let transmit = state.withLock { state in
            state.released = true
            let transmit = state.transmit
            state.transmit = nil
            return transmit
        }
        transmit?()
    }
}

private final class SeerrProtocolState: Sendable {
    private struct State {
        var responses: [SeerrStub]
        var requests: [URLRequest] = []
    }

    private let state: OSAllocatedUnfairLock<State>
    init(responses: [SeerrStub]) {
        state = OSAllocatedUnfairLock(initialState: State(responses: responses))
    }

    var requests: [URLRequest] {
        state.withLock { $0.requests }
    }

    func next(_ request: URLRequest) -> SeerrStub {
        state.withLock { state in
            state.requests.append(request)
            return state.responses.isEmpty ? SeerrStub(status: 500) : state.responses.removeFirst()
        }
    }
}
