#if os(iOS) && canImport(CarPlay)
    import CarPlay
    import OSLog
    import UIKit

    /// CarPlay audio companion: native CarPlay templates over the active Jellyfin
    /// session — music albums and audiobooks only, never video.
    ///
    /// The scene activates only when the app carries the Apple-granted
    /// `com.apple.developer.carplay-audio` entitlement (see
    /// `Config/Gus-CarPlay.entitlements` and
    /// `Documentation/AppStore/signing-capabilities.md`); without it this code is inert.
    final class GusCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
        private var contentController: CarPlayContentController?

        func templateApplicationScene(
            _ templateApplicationScene: CPTemplateApplicationScene,
            didConnect interfaceController: CPInterfaceController
        ) {
            let controller = CarPlayContentController()
            contentController = controller
            Task { @MainActor in
                await controller.start(interfaceController: interfaceController)
            }
        }

        func templateApplicationScene(
            _ templateApplicationScene: CPTemplateApplicationScene,
            didDisconnectInterfaceController interfaceController: CPInterfaceController
        ) {
            Task { @MainActor [contentController] in
                contentController?.teardown()
            }
            contentController = nil
        }
    }

    /// Builds CarPlay templates from the active session and drives audio playback
    /// through the same `AudioPlayerStore` used in the app.
    @MainActor
    final class CarPlayContentController {
        // The shared instance — CarPlay must see the same session the app does, so
        // sign-out and account switches propagate.
        private let appModel = AppModel.shared
        private let logger = Logger(category: .carPlay)
        private var audioPlayer: AudioPlayerStore?
        private weak var interfaceController: CPInterfaceController?

        func start(interfaceController: CPInterfaceController) async {
            self.interfaceController = interfaceController
            appModel.restoreLastSession()

            guard let session = appModel.currentSession else {
                await setSignedOutRoot()
                return
            }
            await setLibraryRoot(session: session)
        }

        func teardown() {
            audioPlayer?.teardown()
            audioPlayer = nil
            interfaceController = nil
        }

        // MARK: - Templates

        private func setSignedOutRoot() async {
            let item = CPListItem(
                text: String(localized: "Open Gus on iPhone to sign in", comment: "CarPlay signed-out title"),
                detailText: String(localized: "CarPlay plays music and audiobooks from your active Jellyfin session.", comment: "CarPlay signed-out detail")
            )
            let list = CPListTemplate(
                title: String(localized: "Gus", comment: "CarPlay root title"),
                sections: [CPListSection(items: [item])]
            )
            await performTemplateOperation("set signed-out root") { interfaceController in
                try await interfaceController.setRootTemplate(list, animated: false)
            }
        }

        private func setLibraryRoot(session: SessionStore) async {
            async let albumsLoad = loadItems(types: [.musicAlbum], session: session)
            async let audiobooksLoad = loadItems(types: [.audioBook], session: session)
            let (albums, audiobooks) = await(albumsLoad, audiobooksLoad)

            let albumsTemplate = CPListTemplate(
                title: String(localized: "Albums", comment: "CarPlay albums tab"),
                sections: [albumSection(albums, session: session)]
            )
            albumsTemplate.tabImage = UIImage(systemName: "music.note.list")

            let audiobooksTemplate = CPListTemplate(
                title: String(localized: "Audiobooks", comment: "CarPlay audiobooks tab"),
                sections: [trackSection(audiobooks, session: session)]
            )
            audiobooksTemplate.tabImage = UIImage(systemName: "book")

            let tabBar = CPTabBarTemplate(templates: [albumsTemplate, audiobooksTemplate])
            await performTemplateOperation("set library root") { interfaceController in
                try await interfaceController.setRootTemplate(tabBar, animated: false)
            }
        }

        private func albumSection(_ albums: [MediaItem], session: SessionStore) -> CPListSection {
            let items = albums.map { album in
                let listItem = CPListItem(
                    text: album.displayTitle,
                    detailText: album.albumArtist ?? album.artists.first
                )
                listItem.handler = { [weak self] _, completion in
                    Task { @MainActor in
                        await self?.openAlbum(album, session: session)
                        completion()
                    }
                }
                return listItem
            }
            return CPListSection(items: items)
        }

        /// Rows that play directly (album tracks, audiobooks).
        private func trackSection(_ tracks: [MediaItem], session: SessionStore) -> CPListSection {
            let items = tracks.enumerated().map { index, track in
                let listItem = CPListItem(text: track.displayTitle, detailText: track.runtimeText)
                listItem.handler = { [weak self] _, completion in
                    Task { @MainActor in
                        await self?.play(tracks: tracks, startIndex: index, session: session)
                        completion()
                    }
                }
                return listItem
            }
            return CPListSection(items: items)
        }

        private func openAlbum(_ album: MediaItem, session: SessionStore) async {
            let page = try? await session.mediaProvider.items(query: MediaItemQuery(
                parentID: album.id,
                startIndex: 0,
                limit: 300,
                sort: .trackOrder
            ))
            let tracks = (page?.items ?? []).filter(\.isAudioPlayable)
            guard !tracks.isEmpty else { return }

            let template = CPListTemplate(
                title: album.displayTitle,
                sections: [trackSection(tracks, session: session)]
            )
            await performTemplateOperation("push album template") { interfaceController in
                try await interfaceController.pushTemplate(template, animated: true)
            }
        }

        private func play(tracks: [MediaItem], startIndex: Int, session: SessionStore) async {
            audioPlayer?.teardown()
            let player = AudioPlayerStore(session: session, tracks: tracks, startIndex: startIndex)
            audioPlayer = player
            await player.start()
            await performTemplateOperation("push now playing template") { interfaceController in
                try await interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
            }
        }

        private func loadItems(types: [MediaItemType], session: SessionStore) async -> [MediaItem] {
            let page = try? await session.mediaProvider.items(query: MediaItemQuery(
                includeTypes: types,
                startIndex: 0,
                limit: 100,
                isRecursive: true,
                sort: .name
            ))
            // The household content-rating limit applies in the car too.
            return ContentRatingGate.filter(page?.items ?? [])
        }

        private func performTemplateOperation(
            _ operation: String,
            _ body: (CPInterfaceController) async throws -> Void
        ) async {
            guard let interfaceController else { return }
            do {
                try await body(interfaceController)
            } catch {
                logger.error("CarPlay template operation failed: \(operation, privacy: .public), \(error.localizedDescription, privacy: .public)")
            }
        }
    }
#endif
