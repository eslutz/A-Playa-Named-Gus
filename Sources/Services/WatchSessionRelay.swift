#if os(iOS) && canImport(WatchConnectivity)
    import Foundation
    import OSLog
    import WatchConnectivity

    /// iOS-side WatchConnectivity relay: mirrors the active session's credential to a
    /// paired watch so the watch app signs in without re-entering anything. This is an
    /// *accelerator* per the watchOS brief — the watch signs in standalone (Quick
    /// Connect) without it. Transport is Apple's encrypted device-to-device channel;
    /// the token never touches a third party.
    @MainActor final class WatchSessionRelay: NSObject, WCSessionDelegate {
        static let shared = WatchSessionRelay()

        private let logger = Logger(subsystem: Logger.subsystem, category: "WatchRelay")
        private var pendingPayload: [String: Any]?

        func activate() {
            guard WCSession.isSupported() else { return }
            WCSession.default.delegate = self
            WCSession.default.activate()
        }

        /// Publishes the signed-in session to the watch. `updateApplicationContext`
        /// keeps only the latest snapshot, which is exactly the hand-off semantic.
        func publish(server: ServerConnection, user: StoredUser, token: String) {
            guard WCSession.isSupported(),
                  let serverData = try? JSONEncoder().encode(server),
                  let userData = try? JSONEncoder().encode(user)
            else { return }

            let payload: [String: Any] = [
                "server": serverData,
                "user": userData,
                "token": token,
            ]

            guard WCSession.default.activationState == .activated else {
                pendingPayload = payload
                activate()
                return
            }
            send(payload)
        }

        func clear(server: ServerConnection, user: StoredUser) {
            guard WCSession.isSupported() else { return }

            let payload: [String: Any] = [
                "clearCredential": true,
                "serverID": server.id,
                "userID": user.id,
            ]

            guard WCSession.default.activationState == .activated else {
                pendingPayload = payload
                activate()
                return
            }
            send(payload)
        }

        private func send(_ payload: [String: Any]) {
            do {
                try WCSession.default.updateApplicationContext(payload)
            } catch {
                logger.info("Watch hand-off skipped: \(error.localizedDescription, privacy: .private)")
            }
        }

        /// Explicit user request only. WatchConnectivity queues it for reconnection;
        /// a queued request is not a claim that current Watch logs were received.
        @discardableResult
        func requestDiagnostics() -> Bool {
            guard WCSession.isSupported(), WCSession.default.activationState == .activated,
                  WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return false }
            let session = WCSession.default
            for transfer in session.outstandingUserInfoTransfers where transfer.userInfo["requestDiagnostics"] as? Bool == true {
                transfer.cancel()
            }
            session.transferUserInfo(["requestDiagnostics": true])
            return true
        }

        nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
            guard let data = applicationContext["diagnosticSnapshot"] as? Data else { return }
            WatchDiagnosticSnapshotStore.shared.receive(data)
        }

        // MARK: - WCSessionDelegate

        nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
            guard activationState == .activated else { return }
            if let data = session.receivedApplicationContext["diagnosticSnapshot"] as? Data {
                WatchDiagnosticSnapshotStore.shared.receive(data)
            }
            Task { @MainActor [weak self] in
                guard let self, let pendingPayload = self.pendingPayload else { return }
                self.pendingPayload = nil
                self.send(pendingPayload)
            }
        }

        nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

        nonisolated func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
        }
    }
#endif
