#if canImport(WatchConnectivity)
    import Foundation
    import OSLog
    import WatchConnectivity

    /// Watch-side WatchConnectivity receiver: adopts the session credential the iPhone
    /// app publishes after sign-in/restore, so the watch is signed in without typing.
    /// Standalone Quick Connect sign-in works without this — it is an accelerator.
    final class WatchCredentialReceiver: NSObject, WCSessionDelegate {
        static let shared = WatchCredentialReceiver()

        private let logger = Logger(subsystem: Logger.subsystem, category: "WatchRelay")

        func activate() {
            guard WCSession.isSupported() else { return }
            WCSession.default.delegate = self
            WCSession.default.activate()
        }

        func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
            guard activationState == .activated else { return }
            // A context published while the watch app was not running is delivered as
            // the receivedApplicationContext snapshot.
            adopt(session.receivedApplicationContext)
        }

        func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
            adopt(applicationContext)
        }

        private func adopt(_ context: [String: Any]) {
            if let shouldClear = context["clearCredential"] as? Bool,
               shouldClear,
               let serverID = context["serverID"] as? String,
               let userID = context["userID"] as? String
            {
                Task { @MainActor in
                    AppModel.shared.clearHandedOffSession(serverID: serverID, userID: userID)
                }
                return
            }

            guard let serverData = context["server"] as? Data,
                  let userData = context["user"] as? Data,
                  let token = context["token"] as? String,
                  let server = try? JSONDecoder().decode(ServerConnection.self, from: serverData),
                  let user = try? JSONDecoder().decode(StoredUser.self, from: userData)
            else { return }

            Task { @MainActor in
                AppModel.shared.adoptHandedOffSession(server: server, user: user, token: token)
            }
        }
    }
#endif
