import Foundation

/// Credential material: callers may save this representation in Keychain, never preferences or diagnostics.
struct SeerrSessionCookie: Codable, Hashable, Sendable {
    let origin: URL
    let name: String
    let value: String
    let path: String
    let expiresAt: Date?
    let secure: Bool
}

enum SeerrClientError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL
    case unsupportedVersion
    case uninitializedServer
    case invalidResponse
    case invalidPayload
    case unauthorized
    case forbidden
    case notFound
    case conflict
    case quotaExceeded
    case redirectRejected
    case httpStatus(Int)
    case mutationOutcomeUnknown

    var errorDescription: String? {
        switch self {
        case .invalidURL: String(localized: "Enter a valid Seerr HTTP or HTTPS address without credentials, query, or fragment.")
        case .unsupportedVersion: String(localized: "This server requires a supported stable Seerr 3 release (3.0.0 or newer).")
        case .uninitializedServer: String(localized: "Finish setting up Seerr in its web interface before connecting Gus.")
        case .invalidResponse: String(localized: "Seerr returned an unexpected response.")
        case .invalidPayload: String(localized: "Check the media and seasons selected for this request.")
        case .unauthorized: String(localized: "Sign in to Seerr again.")
        case .forbidden: String(localized: "Seerr did not allow this action. Refresh your account permissions and try again.")
        case .notFound: String(localized: "This Seerr item is no longer available.")
        case .conflict: String(localized: "This request changed on Seerr. Refresh it before taking another action.")
        case .quotaExceeded: String(localized: "Your Seerr request quota has been reached.")
        case .redirectRejected: String(localized: "Seerr redirected outside its configured address. Check the server address.")
        case let .httpStatus(code): String(localized: "Seerr returned HTTP \(code).")
        case .mutationOutcomeUnknown: String(localized: "Seerr may have completed this action. Refresh requests before trying again.")
        }
    }
}

/// A cookie-authenticated Seerr 3 client. Cookies are isolated from URLSession's shared cookie stores.
/// No operation retries a mutation; an interrupted response can conceal a committed server change.
actor SeerrClient {
    nonisolated let baseURL: URL
    private let session: URLSession
    private let redirectPolicy: SeerrRedirectPolicy
    private var cookies: [SeerrSessionCookie]

    init(baseURL: URL, session: URLSession? = nil, cookies: [SeerrSessionCookie] = []) throws {
        let normalized = try Self.normalizeURL(baseURL.absoluteString)
        self.baseURL = normalized
        redirectPolicy = SeerrRedirectPolicy(baseURL: normalized)
        self.cookies = cookies.filter { Self.validCookie($0, for: normalized) }
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: configuration)
        }
    }

    nonisolated static func normalizeURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard !trimmed.isEmpty, var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty, !host.contains(where: \.isWhitespace),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1 ... 65535).contains($0) }) ?? true
        else { throw SeerrClientError.invalidURL }
        components.scheme = scheme
        components.host = host.lowercased()
        var path = components.percentEncodedPath
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if path.hasSuffix("/api/v1") {
            path.removeLast("/api/v1".count)
        }
        let decodedSegments = path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard decodedSegments.allSatisfy({ $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\\") }),
              !path.contains("//"), !path.contains("\\")
        else { throw SeerrClientError.invalidURL }
        components.percentEncodedPath = path
        guard let url = components.url else { throw SeerrClientError.invalidURL }
        return url
    }

    func sessionCookies() -> [SeerrSessionCookie] {
        cookies.removeAll { !Self.validCookie($0, for: baseURL) }
        return cookies
    }

    func clearSession() {
        cookies.removeAll()
    }

    func validateServer() async throws -> SeerrServerInfo {
        let status = try await status()
        guard status.isSupported else { throw SeerrClientError.unsupportedVersion }
        let settings = try await publicSettings()
        guard settings.initialized else { throw SeerrClientError.uninitializedServer }
        guard settings.localLogin != nil, settings.mediaServerLogin != nil, settings.mediaServerType != nil else {
            throw SeerrClientError.invalidResponse
        }
        return SeerrServerInfo(status: status, settings: settings)
    }

    func status() async throws -> SeerrStatus {
        try await get("status", query: [URLQueryItem(name: "checkUpdateAvailable", value: "false")])
    }

    func publicSettings() async throws -> SeerrPublicSettings {
        try await get("settings/public")
    }

    func discoverSliders() async throws -> [SeerrDiscoverSlider] {
        try await get("settings/discover")
    }

    func me() async throws -> SeerrUser {
        try await get("auth/me")
    }

    func loginLocal(email: String, password: String) async throws -> SeerrUser {
        let info = try await validateServer()
        guard info.settings.supportsLocalLogin else { throw SeerrClientError.forbidden }
        return try await send("auth/local", body: LocalCredentials(email: email, password: password), mutation: false)
    }

    func loginJellyfin(username: String, password: String) async throws -> SeerrUser {
        let info = try await validateServer()
        guard info.settings.supportsJellyfinLogin else { throw SeerrClientError.forbidden }
        // The configured Seerr backend selects its Jellyfin server; never supply a different hostname.
        return try await send("auth/jellyfin", body: JellyfinCredentials(username: username, password: password), mutation: false)
    }

    func logout() async throws {
        defer { cookies.removeAll() }
        _ = try await perform("auth/logout", method: "POST", mutation: false)
    }

    func browse(
        _ feed: SeerrDiscoveryFeed,
        page: Int = 1,
        mediaType: SeerrMediaType? = nil,
        language: String? = nil
    ) async throws -> SeerrPage {
        var query = Self.pageQuery(page, language: language)
        if feed == .trending, let mediaType, mediaType == .movie || mediaType == .tv {
            query.append(URLQueryItem(name: "mediaType", value: mediaType.rawValue))
        }
        return try await get(feed.path, query: query)
    }

    func search(query: String, page: Int = 1, language: String? = nil) async throws -> SeerrPage {
        try await get("search", query: [URLQueryItem(name: "query", value: query)] + Self.pageQuery(page, language: language))
    }

    func details(mediaType: SeerrMediaType, id: Int) async throws -> SeerrTitle {
        let path = try Self.mediaPath(mediaType, id: id)
        var title: SeerrTitle = try await get(path)
        title.mediaType = mediaType
        return title
    }

    func recommendations(mediaType: SeerrMediaType, id: Int, page: Int = 1) async throws -> SeerrPage {
        try await get(Self.mediaPath(mediaType, id: id) + "/recommendations", query: Self.pageQuery(page))
    }

    func similar(mediaType: SeerrMediaType, id: Int, page: Int = 1) async throws -> SeerrPage {
        try await get(Self.mediaPath(mediaType, id: id) + "/similar", query: Self.pageQuery(page))
    }

    func person(id: Int) async throws -> SeerrPerson {
        try Self.validateID(id)
        return try await get("person/\(id)")
    }

    func personCredits(id: Int) async throws -> SeerrPersonCredits {
        try Self.validateID(id)
        return try await get("person/\(id)/combined_credits")
    }

    func season(tvID: Int, number: Int) async throws -> SeerrSeason {
        try Self.validateID(tvID)
        guard number >= 0 else { throw SeerrClientError.invalidPayload }
        return try await get("tv/\(tvID)/season/\(number)")
    }

    func collection(id: Int) async throws -> SeerrCollection {
        try Self.validateID(id)
        return try await get("collection/\(id)")
    }

    func requests(
        filter: SeerrRequestFilter = .all,
        requestedBy: Int? = nil,
        take: Int = 20,
        skip: Int = 0
    ) async throws -> SeerrRequestPage {
        var query = Self.requestPageQuery(take: take, skip: skip)
        query += [URLQueryItem(name: "filter", value: filter.rawValue), URLQueryItem(name: "sort", value: "added")]
        if let requestedBy {
            try Self.validateID(requestedBy)
            query.append(URLQueryItem(name: "requestedBy", value: String(requestedBy)))
        }
        return try await get("request", query: query)
    }

    func userRequests(userID: Int, take: Int = 20, skip: Int = 0) async throws -> SeerrRequestPage {
        try Self.validateID(userID)
        return try await get("user/\(userID)/requests", query: Self.requestPageQuery(take: take, skip: skip))
    }

    func request(id: Int) async throws -> SeerrRequest {
        try Self.validateID(id)
        return try await get("request/\(id)")
    }

    func quota(userID: Int) async throws -> SeerrQuota {
        try Self.validateID(userID)
        return try await get("user/\(userID)/quota")
    }

    func createRequest(_ payload: SeerrRequestPayload) async throws -> SeerrRequest {
        guard payload.isValid else { throw SeerrClientError.invalidPayload }
        return try await send("request", body: payload, mutation: true)
    }

    func approveRequest(id: Int) async throws -> SeerrRequest {
        try await updateRequest(id: id, action: "approve")
    }

    func declineRequest(id: Int) async throws -> SeerrRequest {
        try await updateRequest(id: id, action: "decline")
    }

    func retryRequest(id: Int) async throws -> SeerrRequest {
        try await updateRequest(id: id, action: "retry")
    }

    func cancelRequest(id: Int) async throws {
        try Self.validateID(id)
        _ = try await perform("request/\(id)", method: "DELETE", mutation: true)
    }

    func serviceServers(mediaType: SeerrMediaType) async throws -> [SeerrServiceServer] {
        try await get(Self.servicePath(mediaType))
    }

    func serviceDetails(mediaType: SeerrMediaType, serverID: Int) async throws -> SeerrServiceDetails {
        guard serverID >= 0 else { throw SeerrClientError.invalidPayload }
        return try await get(Self.servicePath(mediaType) + "/\(serverID)")
    }

    private func updateRequest(id: Int, action: String) async throws -> SeerrRequest {
        try Self.validateID(id)
        let data = try await perform("request/\(id)/\(action)", method: "POST", mutation: true)
        return try decode(data, mutation: true)
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await perform(path, query: query)
        return try decode(data)
    }

    func send<T: Decodable>(_ path: String, body: some Encodable, mutation: Bool) async throws -> T {
        let encoded = try JSONEncoder().encode(body)
        let data = try await perform(path, method: "POST", body: encoded, mutation: mutation)
        return try decode(data, mutation: mutation)
    }

    func decode<T: Decodable>(_ data: Data, mutation: Bool = false) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw mutation ? SeerrClientError.mutationOutcomeUnknown : .invalidResponse }
    }

    func perform(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        mutation: Bool = false
    ) async throws -> Data {
        try Task.checkCancellation()
        guard var components = URLComponents(url: baseURL.appending(path: "api/v1/\(path)"), resolvingAgainstBaseURL: false) else {
            throw SeerrClientError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw SeerrClientError.invalidURL }
        cookies.removeAll { !Self.validCookie($0, for: baseURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let matching = cookies.filter { Self.cookie($0, matches: url) }
        if !matching.isEmpty {
            request.setValue(matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }
        if method != "GET", let token = matching.first(where: { $0.name == "XSRF-TOKEN" })?.value {
            request.setValue(token.removingPercentEncoding ?? token, forHTTPHeaderField: "X-CSRF-Token")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: redirectPolicy)
        } catch {
            if mutation {
                throw SeerrClientError.mutationOutcomeUnknown
            }
            throw error
        }
        guard let response = response as? HTTPURLResponse, let responseURL = response.url,
              redirectPolicy.allows(responseURL)
        else { throw mutation ? SeerrClientError.mutationOutcomeUnknown : .invalidResponse }
        if (300 ... 399).contains(response.statusCode) {
            throw SeerrClientError.redirectRejected
        }
        absorbCookies(response: response, url: responseURL)
        switch response.statusCode {
        case 200 ... 299: return data
        case 401:
            cookies.removeAll()
            throw SeerrClientError.unauthorized
        case 403: throw SeerrClientError.forbidden
        case 404: throw SeerrClientError.notFound
        case 409: throw SeerrClientError.conflict
        case 429: throw SeerrClientError.quotaExceeded
        case 500 ... 599 where mutation: throw SeerrClientError.mutationOutcomeUnknown
        default: throw SeerrClientError.httpStatus(response.statusCode)
        }
    }

    private func absorbCookies(response: HTTPURLResponse, url: URL) {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            // Even a parent-domain cookie stays confined to the configured exact origin.
            guard domain == baseURL.host?.lowercased(),
                  !cookie.name.isEmpty, !cookie.value.contains(where: { $0 == "\r" || $0 == "\n" })
            else { continue }
            cookies.removeAll { $0.name == cookie.name && $0.path == cookie.path }
            let value = SeerrSessionCookie(
                origin: baseURL,
                name: cookie.name,
                value: cookie.value,
                path: cookie.path,
                expiresAt: cookie.expiresDate,
                secure: cookie.isSecure
            )
            if Self.validCookie(value, for: baseURL) {
                cookies.append(value)
            }
        }
    }

    private nonisolated static func validCookie(_ cookie: SeerrSessionCookie, for baseURL: URL) -> Bool {
        cookie.origin == baseURL && !cookie.name.isEmpty && cookie.path.hasPrefix("/")
            && (cookie.expiresAt.map { $0 > Date() } ?? true)
            && !cookie.name.contains(where: { $0.isWhitespace || $0 == ";" || $0 == "=" })
            && !cookie.value.contains(where: { $0.isNewline || $0 == ";" })
            && (!cookie.secure || baseURL.scheme == "https")
    }

    private nonisolated static func cookie(_ cookie: SeerrSessionCookie, matches url: URL) -> Bool {
        let path = url.path
        return path == cookie.path || (path.hasPrefix(cookie.path) && (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
    }

    private nonisolated static func pageQuery(_ page: Int, language: String? = nil) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "page", value: String(max(1, page)))]
        if let language, !language.isEmpty {
            query.append(URLQueryItem(name: "language", value: language))
        }
        return query
    }

    private nonisolated static func requestPageQuery(take: Int, skip: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "take", value: String(min(100, max(1, take)))), URLQueryItem(name: "skip", value: String(max(0, skip)))]
    }

    private nonisolated static func mediaPath(_ type: SeerrMediaType, id: Int) throws -> String {
        try validateID(id)
        guard type == .movie || type == .tv else { throw SeerrClientError.invalidPayload }
        return "\(type.rawValue)/\(id)"
    }

    private nonisolated static func servicePath(_ type: SeerrMediaType) throws -> String {
        guard type == .movie || type == .tv else { throw SeerrClientError.invalidPayload }
        return type == .movie ? "service/radarr" : "service/sonarr"
    }

    private nonisolated static func validateID(_ id: Int) throws {
        guard id > 0 else { throw SeerrClientError.invalidPayload }
    }

    private struct LocalCredentials: Encodable { let email: String; let password: String }
    private struct JellyfinCredentials: Encodable { let username: String; let password: String }
}

/// Credentials and cookies may only follow a redirect inside the configured exact origin and base path.
final class SeerrRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    private let baseURL: URL
    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == baseURL.scheme?.lowercased(),
              url.host?.lowercased() == baseURL.host?.lowercased(),
              (url.port ?? (url.scheme == "https" ? 443 : 80)) == (baseURL.port ?? (baseURL.scheme == "https" ? 443 : 80)),
              url.user == nil, url.password == nil,
              !url.pathComponents.contains(".."), !url.pathComponents.contains(".") else { return false }
        let basePath = baseURL.path
        return basePath.isEmpty || basePath == "/" || url.path == basePath || url.path.hasPrefix(basePath + "/")
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url, allows(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
