import Foundation

/// Each component is independently encoded so provider IDs can contain arbitrary Unicode or separators.
/// Keep the version and component order stable for actions that people have already saved.
enum GusIntentID {
    static func make(resource: String, id: String, provider: MediaProviderKind, scope: AccountScope) -> String {
        let components = [resource, provider.rawValue, scope.serverID, scope.userID, id]
        return "1." + components.map { Data($0.utf8).base64EncodedString() }.joined(separator: ".")
    }

    static func value(_ identifier: String, resource: String, provider: MediaProviderKind, scope: AccountScope) -> String? {
        guard identifier.utf8.count <= 8192 else { return nil }
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 6, parts.first == "1",
              let data = Data(base64Encoded: String(parts[5])),
              let id = String(data: data, encoding: .utf8), !id.isEmpty,
              make(resource: resource, id: id, provider: provider, scope: scope) == identifier else { return nil }
        return id
    }
}
