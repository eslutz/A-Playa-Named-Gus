#if os(iOS) && canImport(WatchConnectivity)
    import Foundation
    import OSLog
    import WatchConnectivity

    /// iOS-side WatchConnectivity relay: mirrors the active session's credential to a
    /// paired watch so the watch app signs in without re-entering anything. This is an
    /// *accelerator* per the watchOS brief — the watch signs in standalone (Quick
    /// Connect) without it. Transport is Apple's encrypted device-to-device channel;
    /// the token never touches a third party.
    final class WatchSessionRelay: NSObject, WCSessionDelegate {
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
                logger.info("Watch hand-off skipped: \(error.localizedDescription, privacy: .public)")
            }
        }

        // MARK: - WCSessionDelegate

        func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
            guard activationState == .activated, let pendingPayload else { return }
            self.pendingPayload = nil
            send(pendingPayload)
        }

        func sessionDidBecomeInactive(_ session: WCSession) {}

        func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
        }
    }
#endif
