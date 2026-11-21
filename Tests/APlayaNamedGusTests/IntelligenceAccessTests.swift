import Foundation
@testable import Gus
import Testing

@MainActor
struct IntelligenceAccessTests {
    private let defaults = UserDefaults(suiteName: UUID().uuidString)!
    private let scope = AccountScope(serverID: "server", userID: "user")
    private var prefs: GusIntelligencePreferences {
        GusIntelligencePreferences(scope: scope, defaults: defaults)
    }

    @Test func preferencesMigrateAndRemainScoped() {
        let settings = prefs
        #expect(settings.naturalSearchEnabled)
        #expect(settings.cloudDecision == nil && settings.recommendationDecision == nil)
        settings.naturalSearchEnabled = false
        settings.cloudEnabled = false
        settings.recommendationsEnabled = true
        let restored = prefs
        #expect(!restored.naturalSearchEnabled && restored.cloudDecision == false && restored.recommendationsEnabled)
        let other = GusIntelligencePreferences(scope: .init(serverID: "server", userID: "someone"), defaults: defaults)
        #expect(other.naturalSearchEnabled && other.recommendationDecision == nil)
        let otherServer = AccountScope(serverID: "another-server", userID: scope.userID)
        GusIntelligencePreferences(scope: otherServer, defaults: defaults).recommendationsEnabled = false
        GusIntelligencePreferences.delete(scope: scope, defaults: defaults)
        #expect(prefs.naturalSearchEnabled && prefs.cloudDecision == nil && prefs.recommendationDecision == nil)
        #expect(GusIntelligencePreferences(scope: otherServer, defaults: defaults).recommendationDecision == false)
    }

    @Test func forYouSyncChoiceAndRevocationRemainLocalToTheAccount() {
        let settings = prefs
        #if os(iOS) || os(tvOS)
            let otherAccount = AccountScope(serverID: scope.serverID, userID: "other-user")
            let otherServer = AccountScope(serverID: "other-server", userID: scope.userID)
        #endif
        #if os(iOS)
            #expect(!settings.forYouSyncEnabled)
            #expect(settings.forYouSyncRevocations.isEmpty)
            let revocation = Date(timeIntervalSince1970: 1000)
            settings.forYouSyncRevocations["original-iCloud-account"] = revocation
            #expect(!prefs.forYouSyncEnabled)

            settings.forYouSyncIdentity = "newly-approved-iCloud-account"
            let restored = prefs
            #expect(restored.forYouSyncEnabled)
            #expect(restored.forYouSyncIdentity == "newly-approved-iCloud-account")
            #expect(restored.forYouSyncRevocations["original-iCloud-account"] == revocation)
            #expect(restored.forYouSyncRevocations["newly-approved-iCloud-account"] == nil)

            for otherScope in [otherAccount, otherServer] {
                let other = GusIntelligencePreferences(scope: otherScope, defaults: defaults)
                #expect(!other.forYouSyncEnabled)
                #expect(other.forYouSyncRevocations.isEmpty)
            }
            restored.forYouSyncRevocations["original-iCloud-account"] = nil
            #expect(prefs.forYouSyncRevocations.isEmpty)
            GusIntelligencePreferences.delete(scope: scope, defaults: defaults)
            #expect(!prefs.forYouSyncEnabled)
            #expect(prefs.forYouSyncRevocations.isEmpty)
        #elseif os(tvOS)
            #expect(settings.forYouSyncEnabled)
            settings.forYouSyncEnabled = false
            #expect(!prefs.forYouSyncEnabled)
            for otherScope in [otherAccount, otherServer] {
                #expect(GusIntelligencePreferences(scope: otherScope, defaults: defaults).forYouSyncEnabled)
            }
            GusIntelligencePreferences.delete(scope: scope, defaults: defaults)
            #expect(prefs.forYouSyncEnabled)
        #else
            #expect(!settings.forYouSyncEnabled)
        #endif
    }

    @Test func invitationWaitsForCloudLocaleAndPreservesTheDecision() async {
        let settings = prefs
        var serviceAvailable = false
        let routes = IntelligenceModelRoutes(cloud: { .ready }, supportsCloudLocale: { _ in
            guard serviceAvailable else { throw URLError(.notConnectedToInternet) }
            return true
        })
        let access = GusIntelligenceAccess(preferences: settings, routes: routes) {}
        let window = UUID()
        await access.refreshCloudLocale()
        #expect(access.supportsCloud && !access.hasCheckedCloudLocale)
        #expect(access.claimPrompt(for: window) == nil && settings.recommendationDecision == nil)
        serviceAvailable = true
        await access.refreshCloudLocale()
        #expect(access.claimPrompt(for: window) == .forYou)
        access.respond(to: .forYou, from: window, allow: false)
        let reopened = GusIntelligenceAccess(preferences: prefs, routes: routes) {}
        await reopened.refreshCloudLocale()
        #expect(reopened.claimPrompt(for: UUID()) == nil)
    }

    @Test func foregroundWindowsShareOneInvitation() {
        var local = IntelligenceModelStatus.preparing
        let settings = prefs
        let access = GusIntelligenceAccess(preferences: settings, routes: .init(local: { local })) {}
        let first = UUID(), second = UUID()
        #expect(access.usesNaturalSearch && !access.canOfferForYou)
        #expect(access.claimPrompt(for: first) == nil)
        local = .ready
        #expect(access.claimPrompt(for: first) == .forYou)
        #expect(access.claimPrompt(for: second) == nil)
        access.releasePrompt(from: first)
        #expect(access.claimPrompt(for: second) == .forYou)
        access.respond(to: .forYou, from: first, allow: true)
        #expect(settings.recommendationDecision == nil)
        access.respond(to: .forYou, from: second, allow: false)
        #expect(prefs.recommendationDecision == false && access.availablePrompt(for: first) == nil)
        access.setForYouEnabled(true)
        #expect(settings.recommendationsEnabled)
    }

    @Test(arguments: [true, false]) func cloudDecisionForEnablement(allow: Bool) async {
        var cloud = IntelligenceModelStatus.ready
        let settings = prefs
        let access = GusIntelligenceAccess(preferences: settings, routes: .init(cloud: { cloud }, supportsCloudLocale: { _ in true })) {}
        await access.refreshCloudLocale()
        let window = UUID()
        #expect(access.usesNaturalSearch && access.supportsCloud)
        #expect(access.claimPrompt(for: window) == .forYou)
        access.respond(to: .forYou, from: window, allow: true)
        #expect(!settings.recommendationsEnabled && access.claimPrompt(for: window) == .cloud)
        access.respond(to: .cloud, from: window, allow: allow)
        #expect(settings.recommendationDecision == allow && settings.cloudDecision == allow)
        #expect(access.availablePrompt(for: window) == nil)
        cloud = .preparing
        #expect(access.usesNaturalSearch && access.supportsCloud && !access.cloudReady)
        access.setCloudEnabled(false)
        #expect(settings.cloudDecision == false)
    }

    @Test(arguments: [true, false]) func searchResumesAfterOneCloudDecision(allow: Bool) async throws {
        let settings = prefs
        let access = GusIntelligenceAccess(preferences: settings, routes: .init(cloud: { .ready }, supportsCloudLocale: { _ in true })) {}
        let host = UUID()
        defer { access.invalidate() }
        let request = Task { try await access.requestSearchAccess() }
        for _ in 0 ..< 100 where access.availablePrompt(for: host) != .cloud {
            await Task.yield()
        }
        try #require(access.claimPrompt(for: host) == .cloud)
        access.respond(to: .cloud, from: host, allow: allow)
        #expect(try await request.value == allow)
        #expect(try await access.requestSearchAccess() == allow)
        settings.naturalSearchEnabled = false
        #expect(try await !access.requestSearchAccess())
    }

    @Test func pendingSearchRetiresOnSignOutOrCancellation() async {
        let access = GusIntelligenceAccess(preferences: prefs, routes: .init(cloud: { .ready }, supportsCloudLocale: { _ in true })) {}
        let host = UUID()
        for cancel in [true, false] {
            let request = Task { try await access.requestSearchAccess() }
            for _ in 0 ..< 100 where access.availablePrompt(for: host) != .cloud {
                await Task.yield()
            }
            #expect(access.availablePrompt(for: host) == .cloud)
            if cancel {
                request.cancel()
            } else {
                access.invalidate()
            }
            await #expect(throws: CancellationError.self) { try await request.value }
            #expect(access.availablePrompt(for: host) != .cloud)
        }
        #expect(prefs.cloudDecision == nil)
    }

    @Test func disablingSearchRetiresPendingConsentWithoutAffectingForYou() async throws {
        let settings = prefs
        let access = GusIntelligenceAccess(preferences: settings, routes: .init(cloud: { .ready }, supportsCloudLocale: { _ in true })) {}
        defer { access.invalidate() }
        await access.refreshCloudLocale()
        let host = UUID()
        access.setForYouEnabled(true)
        let request = Task { try await access.requestSearchAccess() }
        try #require(access.claimPrompt(for: host) == .cloud)
        access.setNaturalSearchEnabled(false)
        access.respond(to: .cloud, from: host, allow: true)
        #expect(try await !request.value)
        #expect(settings.cloudEnabled && settings.recommendationsEnabled && !access.usesNaturalSearch)
    }

    @Test func ineligibleAndUnsupportedLocale() async throws {
        let access = GusIntelligenceAccess(preferences: prefs, routes: .init()) {}
        #expect(!access.supportsSearch && !access.supportsCloud && !access.canOfferForYou)
        let cloud = GusIntelligenceAccess(preferences: prefs, routes: .init(cloud: { .ready })) {}
        await cloud.refreshCloudLocale()
        #expect(!cloud.usesNaturalSearch && !cloud.canOfferForYou)
        #expect(try await !cloud.requestSearchAccess())
    }
}
