import Foundation
import Observation
#if canImport(FoundationModels) && !os(tvOS)
    import FoundationModels
#endif

enum IntelligencePrompt: String, Identifiable {
    case forYou, cloud
    var id: Self {
        self
    }
}

enum IntelligenceModelStatus {
    case unsupported, preparing, ready
}

/// Keep the observable Apple model instances alive across SwiftUI body evaluations.
@MainActor
struct IntelligenceModelRoutes {
    var local: () -> IntelligenceModelStatus = { .unsupported }
    var cloud: () -> IntelligenceModelStatus = { .unsupported }
    var supportsCloudLocale: (Locale) async throws -> Bool = { _ in false }

    static func system() -> Self {
        #if DEBUG && targetEnvironment(simulator) && !os(tvOS)
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--gus-demo-server") || args.contains("--gus-debug-preview-session") {
                if args.contains("--gus-intelligence-test-cloud") {
                    return Self(cloud: { .ready }, supportsCloudLocale: { _ in true })
                }
                if args.contains("--gus-intelligence-test-local") {
                    return Self(local: { .ready })
                }
            }
        #endif
        #if canImport(FoundationModels) && !os(tvOS)
            var routes = Self()
            #if !os(watchOS)
                let local = SystemLanguageModel.default
                routes.local = {
                    guard local.supportsLocale() else { return .unsupported }
                    switch local.availability {
                    case .available: return .ready
                    case .unavailable(.appleIntelligenceNotEnabled), .unavailable(.modelNotReady): return .preparing
                    default: return .unsupported
                    }
                }
            #endif
            if #available(iOS 27, macOS 27, visionOS 27, watchOS 27, *),
               Bundle.main.object(forInfoDictionaryKey: "GusPrivateCloudComputeEntitled") as? String == "YES"
            {
                let cloud = PrivateCloudComputeLanguageModel()
                routes.cloud = {
                    switch cloud.availability {
                    case .available: return .ready
                    case .unavailable(.systemNotReady): return .preparing
                    default: return .unsupported
                    }
                }
                routes.supportsCloudLocale = { try await cloud.supportsLocale($0) }
            }
            return routes
        #else
            return Self()
        #endif
    }
}

/// Shared by all windows for one authenticated session. A cancelled submission releases
/// its own waiter without dismissing a cloud decision another submission still needs.
@MainActor @Observable
final class GusIntelligenceAccess {
    private let preferences: GusIntelligencePreferences
    private let routes: IntelligenceModelRoutes
    private let clearRecommendations: () -> Void
    private var active = true
    private var checkedLocale: Locale?
    private var localeSupported = false
    private var host: UUID?
    private var claimed: IntelligencePrompt?
    private var waitingForYou = false
    private var searches: [UUID: CheckedContinuation<Bool, any Error>] = [:]

    init(preferences: GusIntelligencePreferences, routes: IntelligenceModelRoutes, clearRecommendations: @escaping () -> Void) {
        self.preferences = preferences
        self.routes = routes
        self.clearRecommendations = clearRecommendations
    }

    var supportsCloud: Bool {
        active && routes.cloud() != .unsupported
    }

    var cloudReady: Bool {
        active && routes.cloud() == .ready
    }

    private var cloudLocaleEligible: Bool {
        checkedLocale != Locale.current || localeSupported
    }

    var supportsSearch: Bool {
        active && (routes.local() != .unsupported || (supportsCloud && cloudLocaleEligible))
    }

    var usesNaturalSearch: Bool {
        supportsSearch && preferences.naturalSearchEnabled
    }

    var requiresCloud: Bool {
        routes.local() != .ready && supportsCloud
    }

    var canOfferForYou: Bool {
        active && (routes.local() == .ready || (cloudReady && preferences.cloudDecision != false && checkedLocale == Locale.current && localeSupported))
    }

    func refreshCloudLocale() async {
        guard cloudReady else { return }
        let locale = Locale.current
        do {
            let supported = try await routes.supportsCloudLocale(locale)
            guard active, !Task.isCancelled, locale == Locale.current else { return }
            checkedLocale = locale
            localeSupported = supported
        } catch {
            // A transient transport error cannot establish that a locale is unsupported.
        }
    }

    private var nextPrompt: IntelligencePrompt? {
        guard active else { return nil }
        if !searches.isEmpty || waitingForYou {
            return .cloud
        }
        return canOfferForYou && preferences.recommendationDecision == nil ? .forYou : nil
    }

    func availablePrompt(for window: UUID) -> IntelligencePrompt? {
        guard host == nil || host == window else { return nil }
        if let claimed {
            switch claimed {
            case .cloud: return !searches.isEmpty || waitingForYou ? .cloud : nil
            case .forYou: return canOfferForYou && preferences.recommendationDecision == nil ? .forYou : nil
            }
        }
        return nextPrompt
    }

    func claimPrompt(for window: UUID) -> IntelligencePrompt? {
        guard let prompt = availablePrompt(for: window) else { return nil }
        host = window
        claimed = prompt
        return prompt
    }

    func releasePrompt(from window: UUID) {
        guard host == window else { return }
        host = nil
        claimed = nil
    }

    func respond(to prompt: IntelligencePrompt, from window: UUID, allow: Bool) {
        guard active, host == window, claimed == prompt else { return }
        releasePrompt(from: window)
        switch prompt {
        case .forYou: setForYouEnabled(allow)
        case .cloud:
            if !searches.isEmpty || waitingForYou {
                setCloudEnabled(allow)
            }
        }
    }

    func setNaturalSearchEnabled(_ enabled: Bool) {
        guard active else { return }
        preferences.naturalSearchEnabled = enabled
        if !enabled {
            resolveSearches(allow: false)
        }
    }

    func setForYouEnabled(_ enabled: Bool) {
        guard active else { return }
        if enabled, routes.local() != .ready {
            guard cloudReady, cloudLocaleEligible else { return }
            switch preferences.cloudDecision {
            case nil:
                waitingForYou = true
                return
            case false:
                preferences.recommendationsEnabled = false
                return
            default: break
            }
        }
        waitingForYou = false
        preferences.recommendationsEnabled = enabled
        if !enabled {
            clearRecommendations()
        }
    }

    func setCloudEnabled(_ enabled: Bool) {
        guard active else { return }
        preferences.cloudEnabled = enabled
        if waitingForYou {
            waitingForYou = false
            preferences.recommendationsEnabled = enabled
        }
        resolveSearches(allow: enabled)
        clearRecommendations()
    }

    private func resolveSearches(allow: Bool) {
        let pending = searches
        searches.removeAll()
        for waiter in pending.values {
            waiter.resume(returning: allow)
        }
    }

    func requestSearchAccess() async throws -> Bool {
        try Task.checkCancellation()
        guard usesNaturalSearch else { return false }
        if routes.local() == .ready {
            return true
        }
        return try await requestSearchCloudAccess()
    }

    func requestSearchCloudAccess() async throws -> Bool {
        try Task.checkCancellation()
        guard active, preferences.naturalSearchEnabled, cloudReady else { return false }
        if checkedLocale != .current {
            await refreshCloudLocale()
        }
        try Task.checkCancellation()
        guard active, preferences.naturalSearchEnabled, cloudReady, cloudLocaleEligible else { return false }
        if let decision = preferences.cloudDecision {
            return decision
        }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                searches[id] = continuation
            }
        } onCancel: {
            Task { @MainActor in self.searches.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
        }
    }

    func invalidate() {
        active = false
        claimed = nil
        host = nil
        waitingForYou = false
        let pending = searches
        searches.removeAll()
        for waiter in pending.values {
            waiter.resume(throwing: CancellationError())
        }
    }
}
