#if os(iOS)
    import AppIntents
    import CryptoKit
    import Foundation
    import NowPlaying
    import UIKit

    @available(iOS 27, *)
    @MainActor
    final class GusRemoteNowPlayingPublisher {
        static let shared = GusRemoteNowPlayingPublisher()
        private typealias Publication = RemoteMediaSession<GusRemotePlaybackAttributes>
        private var publication: Publication?
        private var generation = UUID()
        private var updates: Task<Void, Never>?
        private var cleanup: Task<Void, Never>?
        private var checkedForOrphans = false
        private var previousItemID: String?
        private var contentID = UUID()

        func stop() {
            generation = UUID()
            updates?.cancel()
            updates = nil
            previousItemID = nil
            let retired = publication
            publication = nil
            let cleanOrphans = !checkedForOrphans
            guard retired != nil || cleanOrphans else { return }
            checkedForOrphans = true
            let previous = cleanup
            cleanup = Task {
                await previous?.value
                if let retired {
                    try? await retired.end()
                }
                if cleanOrphans, let sessions = try? await Publication.sessions() {
                    for session in sessions {
                        try? await session.end()
                    }
                }
            }
        }

        func stopAndWait() async throws {
            stop()
            let expected = generation
            await cleanup?.value
            guard generation == expected else { throw GusError.cancelled }
            for remaining in try await Publication.sessions() {
                guard generation == expected else { throw GusError.cancelled }
                try await remaining.end()
            }
        }

        func start(_ player: GusRemotePlayerEntity, deviceType: MediaDevice.DeviceType, session: SessionStore) async throws {
            stop()
            let expected = generation
            await cleanup?.value
            try check(session, expected: expected)
            let store = RemoteSessionsStore(session: session)
            let first = try await attributes(for: player, deviceType: deviceType, using: store, session: session, expected: expected)
            let created = try await Publication.start(attributes: first)
            guard generation == expected, session.isActive else {
                try? await created.end()
                throw GusError.cancelled
            }
            publication = created
            do {
                try check(session, expected: expected)
                try await created.requestToBecomeSystemPrimary()
                try check(session, expected: expected)
            } catch {
                if generation == expected {
                    stop()
                }
                throw error
            }
            updates = Task { [weak self] in
                do {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(15))
                        guard let self else { return }
                        let fresh = try await attributes(for: player, deviceType: deviceType, using: store, session: session, expected: expected)
                        try await created.update(fresh)
                    }
                } catch {
                    if let self, generation == expected {
                        stop()
                    }
                }
            }
        }

        private func check(_ session: SessionStore, expected: UUID) throws {
            try GusIntentRuntime.validate(session)
            guard generation == expected, UIApplication.shared.applicationState != .background else { throw GusError.cancelled }
            guard session.systemSurfacePreferences.personalHistoryEnabled else {
                throw GusError.server(String(localized: "Enable personal history in Gus Settings to publish this player."))
            }
        }

        private func attributes(for player: GusRemotePlayerEntity, deviceType: MediaDevice.DeviceType, using store: RemoteSessionsStore, session: SessionStore, expected: UUID) async throws -> GusRemotePlaybackAttributes {
            try check(session, expected: expected)
            let current = try await GusRemotePlayerQuery().resolve(player, in: session, using: store)
            try check(session, expected: expected)
            guard current.userID == session.user.id, current.hasReportedPauseState, let checkedIn = current.lastPlaybackCheckIn,
                  (0 ..< 45).contains(Date.now.timeIntervalSince(checkedIn)), let item = current.nowPlaying,
                  let itemID = item.id, ContentRatingGate.admitsStored(item),
                  item.isAudioPlayable || [.movie, .episode, .video, .trailer, .liveChannel, .recording].contains(item.type)
            else { throw GusError.server(String(localized: "Choose an active player that is playing media for this Jellyfin account.")) }
            if previousItemID != itemID {
                contentID = UUID()
                previousItemID = itemID
            }
            return GusRemotePlaybackAttributes(
                id: expected.uuidString, deviceID: SHA256.hash(data: Data(player.id.utf8)).map { String(format: "%02x", $0) }.joined(),
                deviceType: deviceType, contentID: contentID.uuidString,
                title: session.systemSurfacePreferences.showsLockScreenTitles ? String(item.displayTitle.prefix(256)) : nil,
                isAudio: item.isAudioPlayable, isPaused: current.isPaused,
                duration: item.runTimeTicks.flatMap { $0 > 0 ? PlaybackTime.seconds(fromTicks: $0) : nil },
                elapsed: current.positionTicks.flatMap { $0 >= 0 ? PlaybackTime.seconds(fromTicks: $0) : nil }, observedAt: checkedIn
            )
        }
    }

    @available(iOS 27, *)
    enum GusRemoteDeviceType: String, AppEnum {
        case tv, speaker, setTopBox, mediaStick, desktop, laptop, phone, tablet, gamingConsole, wearable, car, web

        static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Player Type")
        static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
            .tv: "Television", .speaker: "Speaker", .setTopBox: "Set-Top Box", .mediaStick: "Streaming Stick",
            .desktop: "Desktop Computer", .laptop: "Laptop", .phone: "Phone", .tablet: "Tablet",
            .gamingConsole: "Game Console", .wearable: "Wearable", .car: "Car", .web: "Web Browser",
        ]

        var deviceType: MediaDevice.DeviceType {
            switch self {
            case .tv: .tv
            case .speaker: .speaker
            case .setTopBox: .setTopBox
            case .mediaStick: .mediaStick
            case .desktop: .desktop
            case .laptop: .laptop
            case .phone: .phone
            case .tablet: .tablet
            case .gamingConsole: .gamingConsole
            case .wearable: .wearable
            case .car: .car
            case .web: .web
            }
        }
    }

    @available(iOS 27, *)
    struct ShowGusRemoteNowPlayingIntent: AppIntent {
        static let title: LocalizedStringResource = "Show Jellyfin Player in Now Playing"
        static let description = IntentDescription("Shows the selected player’s status in Control Center while Gus is open.", categoryName: "Remote Playback")
        static let supportedModes: IntentModes = .foreground(.immediate)
        static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

        @Parameter(title: "Player") var player: GusRemotePlayerEntity
        @Parameter(title: "Player Type") var kind: GusRemoteDeviceType

        @MainActor
        func perform() async throws -> some IntentResult {
            let session = try await GusIntentRuntime.session()
            try await requestConfirmation(dialog: "Show this player in system Now Playing while Gus is open?")
            try GusIntentRuntime.validate(session)
            try await GusRemoteNowPlayingPublisher.shared.start(player, deviceType: kind.deviceType, session: session)
            return .result()
        }
    }

    @available(iOS 27, *)
    struct StopGusRemoteNowPlayingIntent: AppIntent {
        static let title: LocalizedStringResource = "Stop Showing Jellyfin Player"
        static let description = IntentDescription("Removes the external player from system Now Playing.", categoryName: "Remote Playback")
        static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

        @MainActor func perform() async throws -> some IntentResult {
            try await GusRemoteNowPlayingPublisher.shared.stopAndWait()
            return .result()
        }
    }
#endif
