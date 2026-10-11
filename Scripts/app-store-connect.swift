#!/usr/bin/env swift
// Native, read-only App Store Connect inspection. JWTs and private keys never print.
import CryptoKit
import Foundation

enum ASCError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message): return message
        }
    }
}

let repositoryRoot = URL(fileURLWithPath: #filePath).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent()

func emit(_ value: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

func parseEnvironment(_ contents: String) -> [String: String] {
    var values: [String: String] = [:]
    for rawLine in contents.components(separatedBy: .newlines) {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("export ") {
            line.removeFirst(7)
        }
        guard !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
        let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
        guard name.hasPrefix("ASC_") else { continue }
        var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first,
           first == "\"" || first == "'", value.last == first
        {
            value = String(value.dropFirst().dropLast())
        }
        // Data only: never evaluate shell expressions or unrelated Jellyfin settings.
        values[name] = value
    }
    return values
}

struct Configuration {
    var values: [String: String]

    init(root: URL = repositoryRoot, environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        values = [:]
        let accountURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".appstoreconnect/config.env")
        if FileManager.default.fileExists(atPath: accountURL.path) {
            values = try parseEnvironment(String(contentsOf: accountURL, encoding: .utf8))
        }
        for name in [".env.local", ".env.asc.local"] {
            let url = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                try values.merge(parseEnvironment(String(contentsOf: url, encoding: .utf8))) { _, new in new }
            }
        }
        values.merge(environment.filter { $0.key.hasPrefix("ASC_") }) { _, new in new }
    }

    init(values: [String: String]) {
        self.values = values
    }

    var kind: String {
        values["ASC_KEY_TYPE"] ?? "team"
    }

    var bundleID: String {
        values["ASC_BUNDLE_ID"] ?? "dev.ericslutz.gus"
    }

    var keyURL: URL? {
        guard let path = values["ASC_PRIVATE_KEY_PATH"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    func missing() -> [String] {
        var required = ["ASC_KEY_ID", "ASC_PRIVATE_KEY_PATH"]
        if kind == "team" {
            required.append("ASC_ISSUER_ID")
        }
        return required.filter { name in
            guard let value = values[name], !value.isEmpty else { return true }
            return value.contains("YOUR_")
        }
    }

    func privateKey(root: URL = repositoryRoot) throws -> P256.Signing.PrivateKey {
        guard kind == "team" || kind == "individual" else {
            throw ASCError.message("ASC_KEY_TYPE must be team or individual.")
        }
        guard missing().isEmpty else {
            throw ASCError.message("API access pending: configure \(missing().joined(separator: ", ")) in .env.asc.local.")
        }
        guard let keyID = values["ASC_KEY_ID"],
              keyID.range(of: "^[A-Za-z0-9]{8,20}$", options: .regularExpression) != nil
        else {
            throw ASCError.message("ASC_KEY_ID is not a valid Apple key identifier.")
        }
        if kind == "team", UUID(uuidString: values["ASC_ISSUER_ID"] ?? "") == nil {
            throw ASCError.message("ASC_ISSUER_ID must be the team API issuer UUID, not the developer Team ID.")
        }
        guard let keyURL else { throw ASCError.message("ASC_PRIVATE_KEY_PATH is missing.") }
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard !keyURL.path.hasPrefix(rootPath) else {
            throw ASCError.message("Store the private key outside the Gus repository.")
        }
        guard FileManager.default.fileExists(atPath: keyURL.path) else {
            throw ASCError.message("The configured .p8 file has not been downloaded.")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: keyURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard permissions & 0o077 == 0 else {
            throw ASCError.message("The private key is accessible to other users; set its permissions to 600.")
        }
        do {
            return try P256.Signing.PrivateKey(pemRepresentation: String(contentsOf: keyURL, encoding: .utf8))
        } catch {
            throw ASCError.message("The .p8 file is not a valid P-256 PEM private key.")
        }
    }
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

func claims(configuration: Configuration, path: String, now: Int) -> [String: Any] {
    var result: [String: Any] = [
        "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1", "scope": ["GET \(path)"],
    ]
    if configuration.kind == "individual" {
        result["sub"] = "user"
    } else {
        result["iss"] = configuration.values["ASC_ISSUER_ID"]
    }
    return result
}

func token(configuration: Configuration, key: P256.Signing.PrivateKey, path: String, now: Int) throws -> String {
    let header: [String: String] = ["alg": "ES256", "kid": configuration.values["ASC_KEY_ID"]!, "typ": "JWT"]
    let message = try [
        base64URL(JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])),
        base64URL(JSONSerialization.data(
            withJSONObject: claims(configuration: configuration, path: path, now: now),
            options: [.sortedKeys]
        )),
    ].joined(separator: ".")
    // JOSE uses the raw 64-byte R || S signature, not ASN.1 DER.
    let signature = try key.signature(for: Data(message.utf8)).rawRepresentation
    return message + "." + base64URL(signature)
}

func checkedURL(_ url: URL) throws -> URL {
    guard url.scheme == "https", url.host == "api.appstoreconnect.apple.com",
          url.port == nil, url.user == nil, url.password == nil,
          url.path.hasPrefix("/v1/") || url.path.hasPrefix("/v2/")
    else {
        throw ASCError.message("Refusing an API or pagination URL outside Apple's HTTPS API.")
    }
    return url
}

final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct Client {
    let configuration: Configuration
    let key: P256.Signing.PrivateKey
    let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)

    func list(_ path: String, query: [String: String] = [:]) async throws -> [[String: Any]] {
        var components = URLComponents(string: "https://api.appstoreconnect.apple.com" + path)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var next = components.url
        var seen: Set<URL> = []
        var resources: [[String: Any]] = []
        while let url = next {
            let url = try checkedURL(url)
            guard seen.insert(url).inserted, seen.count <= 100 else {
                throw ASCError.message("API pagination repeated a page or exceeded 100 pages.")
            }
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.httpMethod = "GET"
            let jwt = try token(
                configuration: configuration,
                key: key,
                path: url.path + (url.query.map { "?" + $0 } ?? ""),
                now: Int(Date().timeIntervalSince1970)
            )
            request.setValue("Bearer " + jwt, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw ASCError.message("No HTTP response from Apple.")
            }
            guard (200 ..< 300).contains(response.statusCode) else {
                // Do not dump server bodies or Authorization headers into logs.
                let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let codes = (document?["errors"] as? [[String: Any]])?
                    .compactMap { $0["code"] as? String }
                    .filter { $0.range(of: "^[A-Z0-9_.-]+$", options: .regularExpression) != nil }
                    .joined(separator: ", ") ?? "unknown"
                throw ASCError.message("Apple returned HTTP \(response.statusCode) for GET \(url.path) (\(codes)).")
            }
            guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let page = document["data"] as? [[String: Any]]
            else {
                throw ASCError.message("Unexpected JSON:API list response for \(url.path).")
            }
            resources += page
            if let value = (document["links"] as? [String: Any])?["next"] as? String {
                guard let url = URL(string: value, relativeTo: url)?.absoluteURL else {
                    throw ASCError.message("Invalid API pagination URL.")
                }
                next = try checkedURL(url)
            } else {
                next = nil
            }
        }
        return resources
    }
}

func inspect(_ configuration: Configuration) async throws {
    let client = try Client(configuration: configuration, key: configuration.privateKey())
    defer { client.session.invalidateAndCancel() }
    let apps = try await client.list("/v1/apps", query: [
        "filter[bundleId]": configuration.bundleID, "fields[apps]": "name,bundleId,sku",
    ])
    var report: [String: Any] = ["bundleId": configuration.bundleID, "apps": apps, "readOnly": true]
    guard let appID = apps.first?["id"] as? String else {
        report["nextStep"] = "Create the app record and onboard Xcode Cloud through Apple's UI."
        try emit(report)
        return
    }
    guard apps.count == 1 else { throw ASCError.message("More than one app matched the bundle ID.") }
    let products = try await client.list("/v1/ciProducts", query: ["filter[app]": appID])
    report["products"] = products
    report["betaGroups"] = try await client.list("/v1/apps/\(appID)/betaGroups", query: [
        "fields[betaGroups]": "name,isInternalGroup",
    ])
    report["builds"] = try await client.list("/v1/builds", query: [
        "filter[app]": appID,
        "sort": "-uploadedDate", "limit": "10", "fields[builds]": "version,processingState,uploadedDate",
    ])
    var cloud: [[String: Any]] = []
    for product in products {
        guard let id = product["id"] as? String else { continue }
        let repositories = try await client.list("/v1/ciProducts/\(id)/primaryRepositories", query: [
            "fields[scmRepositories]": "repositoryName,defaultBranch",
        ])
        var references: [[String: Any]] = []
        for repository in repositories {
            guard let repositoryID = repository["id"] as? String else { continue }
            try references.append([
                "repositoryID": repositoryID,
                "gitReferences": await client.list("/v1/scmRepositories/\(repositoryID)/gitReferences"),
            ])
        }
        try cloud.append([
            "productID": id,
            "workflows": await client.list("/v1/ciProducts/\(id)/workflows"),
            "repositories": repositories,
            "references": references,
        ])
    }
    report["cloud"] = cloud
    report["xcodeVersions"] = try await client.list("/v1/ciXcodeVersions")
    report["macOSVersions"] = try await client.list("/v1/ciMacOsVersions")
    try emit(report)
}

func selfTest() throws {
    func check(_ condition: @autoclosure () -> Bool, _ description: String) throws {
        if !condition() {
            throw ASCError.message("Self-test failed: " + description)
        }
    }
    let values = parseEnvironment("GUS_JELLYFIN_ACCESS_TOKEN=excluded\nASC_KEY_ID='ABC1234567'\nASC_ISSUER_ID=$(do-not-execute)\n")
    try check(values["GUS_JELLYFIN_ACCESS_TOKEN"] == nil, "unrelated credentials excluded")
    try check(values["ASC_KEY_ID"] == "ABC1234567", "quoted dotenv data")
    try check(values["ASC_ISSUER_ID"] == "$(do-not-execute)", "no shell evaluation")
    let team = Configuration(values: [
        "ASC_KEY_ID": "ABC1234567", "ASC_ISSUER_ID": "00000000-0000-0000-0000-000000000001",
    ])
    let key = P256.Signing.PrivateKey()
    let restored = try P256.Signing.PrivateKey(pemRepresentation: key.pemRepresentation)
    let jwt = try token(configuration: team, key: restored, path: "/v1/apps", now: 1000)
    let parts = jwt.split(separator: ".").map(String.init)
    func decode(_ value: String) -> Data {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return Data(base64Encoded: base64)!
    }
    let signatureData = decode(parts[2])
    try check(signatureData.count == 64, "JOSE signature length")
    let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
    try check(
        key.publicKey.isValidSignature(signature, for: Data((parts[0] + "." + parts[1]).utf8)),
        "signed JWT verifies"
    )
    let payload = try JSONSerialization.jsonObject(with: decode(parts[1])) as! [String: Any]
    try check(payload["iss"] as? String == team.values["ASC_ISSUER_ID"], "team issuer")
    try check(payload["exp"] as? Int == 1600, "ten-minute expiry")
    try check(payload["scope"] as? [String] == ["GET /v1/apps"], "read-only request scope")
    let queryPath = "/v1/apps?filter%5BbundleId%5D=dev.ericslutz.gus"
    try check(claims(configuration: team, path: queryPath, now: 1000)["scope"] as? [String] == ["GET " + queryPath], "query parameters retained in scope")
    let individual = Configuration(values: ["ASC_KEY_TYPE": "individual", "ASC_KEY_ID": "ABC1234567"])
    let individualClaims = claims(configuration: individual, path: "/v1/apps", now: 1000)
    try check(individualClaims["sub"] as? String == "user" && individualClaims["iss"] == nil, "individual claims")
    for address in [
        "http://api.appstoreconnect.apple.com/v1/apps",
        "https://example.com/v1/apps",
        "https://api.appstoreconnect.apple.com.evil.test/v1/apps",
        "https://api.appstoreconnect.apple.com:8443/v1/apps",
        "https://user:password@api.appstoreconnect.apple.com/v1/apps",
    ] {
        do { _ = try checkedURL(URL(string: address)!); throw ASCError.message("Accepted unsafe URL.") }
        catch ASCError.message("Refusing an API or pagination URL outside Apple's HTTPS API.") { /* expected */ }
    }
    _ = try checkedURL(URL(string: "https://api.appstoreconnect.apple.com/v1/apps?cursor=next")!)
    try check(Configuration(values: [:]).missing().count == 3, "missing credentials reported before network")
    print("API self-test passed: PEM round-trip, ES256 signature, team/individual claims, expiry, GET scope, dotenv parsing, and URL boundaries.")
}

do {
    let command = CommandLine.arguments.dropFirst().first ?? "help"
    switch command {
    case "self-test":
        try selfTest()
    case "preflight":
        let configuration = try Configuration()
        var status: [String: Any] = [
            "bundleId": configuration.bundleID, "keyType": configuration.kind,
            "missingSettings": configuration.missing(), "networkRequests": 0,
            "privateKeyFileExists": configuration.keyURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
        ]
        do {
            _ = try configuration.privateKey()
            status["authentication"] = "ready-for-read-only-verification"
        } catch {
            status["authentication"] = "pending"
            status["reason"] = String(describing: error)
        }
        try emit(status)
    case "inspect":
        try await inspect(Configuration())
    case "apps":
        let configuration = try Configuration()
        let client = try Client(configuration: configuration, key: configuration.privateKey())
        defer { client.session.invalidateAndCancel() }
        try await emit(client.list("/v1/apps", query: ["fields[apps]": "name,bundleId,sku", "limit": "200"]))
    default:
        print("""
        Usage: swift Scripts/app-store-connect.swift preflight | self-test | inspect | apps
        preflight: check local configuration without network access.
        self-test: test authentication with an ephemeral, non-Apple key.
        inspect: GET Gus app, Cloud workflow/repository IDs, builds, beta groups, and available toolchains.
        apps: list every app accessible to the account key, without a bundle-ID filter.
        Configuration: ~/.appstoreconnect/config.env, then .env.local, .env.asc.local, and ASC_* environment overrides.
        Private keys and JWTs never print. This tool cannot create workflows or start/distribute builds.
        """)
        if command != "help" {
            exit(64)
        }
    }
} catch {
    FileHandle.standardError.write(Data("App Store Connect: \(error)\n".utf8))
    exit(1)
}
