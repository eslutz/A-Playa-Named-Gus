import Foundation
import Observation

/// Choices belong to this installation and Jellyfin server/user pair. Missing opt-in keys
/// mean the user hasn't answered yet. Older builds already wrote explicit Boolean choices.
@MainActor @Observable
final class GusIntelligencePreferences {
    private let defaults: UserDefaults
    private let prefix: String

    var naturalSearchEnabled: Bool {
        didSet { defaults.set(naturalSearchEnabled, forKey: prefix + ".naturalSearch") }
    }

    private(set) var cloudDecision: Bool?
    var cloudEnabled: Bool {
        get { cloudDecision == true }
        set {
            cloudDecision = newValue
            defaults.set(newValue, forKey: prefix + ".cloud")
        }
    }

    private(set) var recommendationDecision: Bool?
    var recommendationsEnabled: Bool {
        get { recommendationDecision == true }
        set {
            recommendationDecision = newValue
            defaults.set(newValue, forKey: prefix + ".recommendations")
        }
    }

    init(scope: AccountScope, defaults: UserDefaults = .standard) {
        let defaults = Self.storage(defaults)
        let key = Self.keyPrefix(for: scope)
        self.defaults = defaults
        self.prefix = key
        func choice(_ suffix: String) -> Bool? {
            let name = key + suffix
            return defaults.object(forKey: name) == nil ? nil : defaults.bool(forKey: name)
        }
        self.naturalSearchEnabled = choice(".naturalSearch") ?? true
        self.cloudDecision = choice(".cloud")
        self.recommendationDecision = choice(".recommendations")
    }

    static func delete(scope: AccountScope, defaults: UserDefaults) {
        let defaults = storage(defaults)
        let key = keyPrefix(for: scope)
        for suffix in [".naturalSearch", ".cloud", ".recommendations"] {
            defaults.removeObject(forKey: key + suffix)
        }
    }

    private static func storage(_ defaults: UserDefaults) -> UserDefaults {
        #if DEBUG && targetEnvironment(simulator)
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--gus-demo-server") || args.contains("--gus-debug-preview-session"),
               let index = args.firstIndex(of: "--gus-intelligence-test-suite"), args.indices.contains(index + 1),
               let suite = UserDefaults(suiteName: args[index + 1])
            {
                return suite
            }
        #endif
        return defaults
    }

    private static func keyPrefix(for scope: AccountScope) -> String {
        let server = Data(scope.serverID.utf8).base64EncodedString()
        let user = Data(scope.userID.utf8).base64EncodedString()
        return "dev.ericslutz.gus.intelligence.\(server).\(user)"
    }
}
