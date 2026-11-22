import AppIntents
import CryptoKit
import Foundation
import Observation
#if os(tvOS)
    import TVServices
#elseif canImport(WidgetKit)
    import WidgetKit
#endif

@MainActor @Observable
final class SystemSurfacePreferences {
    private let defaults: UserDefaults
    private let key: String
    var personalHistoryEnabled: Bool {
        didSet { defaults.set(personalHistoryEnabled, forKey: key + ".history") }
    }

    var showsLockScreenTitles: Bool {
        didSet { defaults.set(showsLockScreenTitles, forKey: key + ".titles") }
    }

    init(credential: SessionCredential, defaults: UserDefaults) {
        let parts = [credential.providerKind.rawValue, credential.serverID, credential.userID]
        let identity = parts.map { "\($0.utf8.count):\($0)" }.joined()
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        key = "dev.ericslutz.gus.systemSurfaces.v1." + digest
        self.defaults = defaults
        personalHistoryEnabled = defaults.bool(forKey: key + ".history")
        showsLockScreenTitles = defaults.bool(forKey: key + ".titles")
    }

    func forget() {
        personalHistoryEnabled = false
        showsLockScreenTitles = false
        defaults.removeObject(forKey: key + ".history")
        defaults.removeObject(forKey: key + ".titles")
    }
}

extension SessionStore {
    func setPersonalHistoryEnabled(_ enabled: Bool) {
        guard isActive, systemSurfacePreferences.personalHistoryEnabled != enabled else { return }
        systemSurfacePreferences.personalHistoryEnabled = enabled
        if !enabled {
            SpotlightIndexer.deleteIndex(serverID: server.id, userID: user.id)
        }
        systemPrivacyDidChange()
    }

    func setShowsLockScreenTitles(_ enabled: Bool) {
        guard isActive, systemSurfacePreferences.showsLockScreenTitles != enabled else { return }
        systemSurfacePreferences.showsLockScreenTitles = enabled
        systemPrivacyDidChange()
    }

    static func clearPersonalSurfaces() {
        #if os(watchOS)
            GusWatchShortcuts.updateAppShortcutParameters()
        #else
            GusAppShortcuts.updateAppShortcutParameters()
        #endif
        #if os(tvOS)
            TopShelfSnapshot.clear()
            TVTopShelfContentProvider.topShelfContentDidChange()
        #elseif canImport(WidgetKit)
            GusWidgetSnapshot.clear(at: GusWidgetSnapshot.fileURL())
            WidgetCenter.shared.reloadTimelines(ofKind: GusWidgetSnapshot.kind)
        #endif
        #if os(iOS)
            DownloadLiveActivityController.shared.endAll()
            if #available(iOS 27, *) {
                GusRemoteNowPlayingPublisher.shared.stop()
            }
        #endif
    }

    func systemPrivacyDidChange(restoring: Bool = false) {
        guard isActive, AppModel.shared.currentSession === self else { return }
        #if os(tvOS)
            // Preserve a tapped card across an ordinary cold launch of the same
            // profile. A different account, restriction, or prior format clears it.
            if restoring, systemSurfacePreferences.personalHistoryEnabled,
               let prior = TopShelfSnapshot.load(), prior.publicationID != nil,
               prior.serverID == server.id, prior.userID == user.id,
               prior.restrictionRevision == ContentRatingGate.storedPolicy().revision
            {
                GusAppShortcuts.updateAppShortcutParameters()
                return
            }
        #endif
        Self.clearPersonalSurfaces()
        #if os(tvOS)
            if systemSurfacePreferences.personalHistoryEnabled {
                homeStore().refreshTopShelf()
            }
        #elseif !os(watchOS)
            if systemSurfacePreferences.personalHistoryEnabled {
                homeStore().refreshWidget()
            }
        #endif
    }

    func publishWidget(items: [MediaItem]) {
        #if canImport(WidgetKit) && !os(tvOS)
            guard isActive, AppModel.shared.currentSession === self,
                  systemSurfacePreferences.personalHistoryEnabled else { return }
            #if canImport(DeclaredAgeRange) && (os(iOS) || os(macOS))
                guard ageRangeAccess.stage == .optional || ageRangeAccess.stage == .ready else { return }
            #endif
            let url = GusWidgetSnapshot.fileURL()
            guard let item = ContentRatingGate.filter(items).first(where: { $0.id != nil }) else {
                if GusWidgetSnapshot.load(from: url) != nil {
                    GusWidgetSnapshot.clear(at: url)
                    WidgetCenter.shared.reloadTimelines(ofKind: GusWidgetSnapshot.kind)
                }
                return
            }
            let visibleTitle: String?
            #if os(iOS) || os(watchOS)
                // Today View can expose even a medium Home Screen widget while locked.
                visibleTitle = systemSurfacePreferences.showsLockScreenTitles ? String(item.displayTitle.prefix(256)) : nil
            #else
                visibleTitle = String(item.displayTitle.prefix(256))
            #endif
            let snapshot = GusWidgetSnapshot(
                title: visibleTitle,
                showsLockScreenTitles: systemSurfacePreferences.showsLockScreenTitles,
                progress: item.cardProgress(showSeriesProgress: false).map { ($0 * 20).rounded(.down) / 20 },
                updatedAt: .now
            )
            if snapshot.store(at: url) {
                WidgetCenter.shared.reloadTimelines(ofKind: GusWidgetSnapshot.kind)
            }
        #endif
    }
}
