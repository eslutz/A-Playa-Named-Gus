import Foundation
import Observation

/// Separate opt-ins belong to this device and the authenticated server/user pair.
@MainActor @Observable
final class GusIntelligencePreferences {
    private let defaults: UserDefaults
    private let prefix: String

    var cloudEnabled: Bool {
        didSet { defaults.set(cloudEnabled, forKey: prefix + ".cloud") }
    }

    var recommendationsEnabled: Bool {
        didSet { defaults.set(recommendationsEnabled, forKey: prefix + ".recommendations") }
    }

    init(scope: AccountScope, defaults: UserDefaults = .standard) {
        let key = Self.keyPrefix(for: scope)
        self.defaults = defaults
        self.prefix = key
        self.cloudEnabled = defaults.bool(forKey: key + ".cloud")
        self.recommendationsEnabled = defaults.bool(forKey: key + ".recommendations")
    }

    static func delete(scope: AccountScope, defaults: UserDefaults) {
        let key = keyPrefix(for: scope)
        defaults.removeObject(forKey: key + ".cloud")
        defaults.removeObject(forKey: key + ".recommendations")
    }

    private static func keyPrefix(for scope: AccountScope) -> String {
        let server = Data(scope.serverID.utf8).base64EncodedString()
        let user = Data(scope.userID.utf8).base64EncodedString()
        return "dev.ericslutz.gus.intelligence.\(server).\(user)"
    }
}
