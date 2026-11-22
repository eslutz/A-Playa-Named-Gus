#if os(iOS) && canImport(CarPlay)
    import CarPlay
    import Observation
    import OSLog
    import UIKit

    /// CarPlay audio companion: native CarPlay templates over the active Jellyfin
    /// session — music albums and audiobooks only, never video.
    ///
    /// The scene activates only when the app carries the Apple-granted
    /// `com.apple.developer.carplay-audio` entitlement (see
    /// `Config/Gus-iOS.entitlements` and
    /// `Documentation/AppStore/signing-capabilities.md`); without it this code is inert.
    @MainActor
    final class GusCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
        private var contentController: CarPlayContentController?

        func templateApplicationScene(
            _ templateApplicationScene: CPTemplateApplicationScene,
            didConnect interfaceController: CPInterfaceController
        ) {
            let controller = CarPlayContentController()
            contentController = controller
            controller.start(interfaceController: interfaceController)
        }

        func templateApplicationScene(
            _ templateApplicationScene: CPTemplateApplicationScene,
            didDisconnectInterfaceController interfaceController: CPInterfaceController
        ) {
            contentController?.teardown()
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
        private var playback: AudioPlaybackCoordinator {
            appModel.audioPlayback
        }

        private let downloads = OfflineDownloadStore.shared
        private var restoreTask: Task<Void, Never>?
        private var libraryTask: Task<Void, Never>?
        private var rowTasks: [UUID: Task<Void, Never>] = [:]
        private var renderedLease: SessionLease?
        private var renderedSession = false
        private weak var interfaceController: CPInterfaceController?
        private var loadingTemplates: Set<ObjectIdentifier> = []
        private var observationGeneration = 0
        private var playbackChoiceGeneration = 0

        /// The native template owns this draft through its row handlers. It never
        /// changes the active player until the user selects Play.
        @MainActor private final class PlaybackChoices {
            var request: PlaybackRequest
            var startOverride: PlaybackStartOverride?
            var isStarting = false
            var tracks: [MediaItem]
            let startIndex: Int
            let continuation: AudioQueueContinuation?
            let session: SessionStore
            let lease: SessionLease
            let generation: Int
            weak var template: CPListTemplate?

            init(request: PlaybackRequest, tracks: [MediaItem], startIndex: Int, continuation: AudioQueueContinuation?, session: SessionStore, generation: Int) {
                self.request = request
                self.tracks = tracks
                self.startIndex = startIndex
                self.continuation = continuation
                self.session = session
                self.lease = session.lease
                self.generation = generation
            }

            var source: MediaSource? {
                let sources = CarPlayPlaybackChoices.sources(for: request.item)
                return sources.first { $0.id == request.streamSelection.mediaSourceID } ?? sources.first
            }

            var effectiveRequest: PlaybackRequest {
                startOverride?.applying(to: request, session: session, progress: .shared) ?? request
            }

            var positionTicks: Int {
                PlaybackChoicePosition.ticks(for: effectiveRequest, session: session, progress: .shared) ?? 0
            }

            func selectSource(_ selected: PlaybackRequest, ticks: Int, fromBeginning: Bool) {
                request = selected
                request.start = .automatic
                request.startPositionTicks = nil
                startOverride = PlaybackStartOverride(request: request, ticks: ticks, fromBeginning: fromBeginning, session: session, progress: .shared)
            }
        }

        func start(interfaceController: CPInterfaceController) {
            self.interfaceController = interfaceController
            let loading = statusTemplate("Loading Gus…")
            let nowPlaying = CPNowPlayingTemplate.shared
            nowPlaying.isUpNextButtonEnabled = false
            nowPlaying.isAlbumArtistButtonEnabled = false
            interfaceController.setRootTemplate(loading, animated: false) { [weak self] _, error in
                if let error {
                    self?.logger.error("CarPlay loading root failed: \(error.localizedDescription, privacy: .private)")
                }
            }
            observeSession()
            restoreSession()
        }

        func teardown() {
            observationGeneration += 1
            restoreTask?.cancel()
            restoreTask = nil
            resetLibrary()
            interfaceController = nil
        }

        private func resetLibrary() {
            playbackChoiceGeneration += 1
            libraryTask?.cancel()
            libraryTask = nil
            for task in rowTasks.values {
                task.cancel()
            }
            rowTasks.removeAll()
            loadingTemplates.removeAll()
        }

        private func restoreSession() {
            restoreTask?.cancel()
            restoreTask = Task {
                await appModel.restoreLastSession()
                guard !Task.isCancelled, interfaceController != nil else { return }
                if appModel.currentSession == nil, !UIApplication.shared.isProtectedDataAvailable {
                    // An after-first-unlock credential normally works with the screen locked.
                    // Retry only when the first read actually failed.
                    for await _ in NotificationCenter.default.notifications(named: UIApplication.protectedDataDidBecomeAvailableNotification) {
                        guard !Task.isCancelled, interfaceController != nil else { return }
                        appModel.reloadSavedAccountsForSessionRestore()
                        await appModel.restoreLastSession()
                        break
                    }
                }
                guard !Task.isCancelled else { return }
                renderSession()
            }
        }

        private func observeSession() {
            let generation = observationGeneration
            withObservationTracking {
                _ = appModel.currentSession?.lease
                _ = appModel.currentSession?.isActive
            } onChange: { [weak self] in
                Task { @MainActor in
                    guard let self, self.observationGeneration == generation, self.interfaceController != nil else { return }
                    self.observeSession()
                    self.renderSession()
                }
            }
        }

        private func renderSession() {
            let session = appModel.currentSession.flatMap { $0.isActive ? $0 : nil }
            guard !renderedSession || renderedLease != session?.lease else { return }
            renderedSession = true
            renderedLease = session?.lease
            resetLibrary()
            libraryTask = Task {
                if let session {
                    await setLibraryRoot(session: session)
                } else {
                    let status = statusTemplate("Sign-in required")
                    await performTemplateOperation("set signed-out root") { controller in
                        try await controller.setRootTemplate(status, animated: false)
                    }
                }
            }
        }

        // MARK: - Templates

        private func statusTemplate(_ status: String.LocalizationValue) -> CPListTemplate {
            let row = CPListItem(text: String(localized: status), detailText: nil)
            row.isEnabled = false
            return CPListTemplate(title: String(localized: "Gus"), sections: [CPListSection(items: [row])])
        }

        private func setLibraryRoot(session: SessionStore) async {
            let albums = CPListTemplate(title: String(localized: "Albums"), sections: [])
            albums.tabImage = UIImage(systemName: "music.note.list")
            let books = CPListTemplate(title: String(localized: "Audiobooks"), sections: [])
            books.tabImage = UIImage(systemName: "book")
            let downloaded = CPListTemplate(title: String(localized: "Downloaded"), sections: [])
            downloaded.tabImage = UIImage(systemName: "arrow.down.circle")
            for template in [albums, books, downloaded] {
                template.emptyViewTitleVariants = [String(localized: "Loading Gus…")]
            }
            let root: CPTemplate
            if CPTabBarTemplate.maximumTabCount >= 3 {
                root = CPTabBarTemplate(templates: [albums, books, downloaded])
            } else {
                let rows = [
                    categoryItem("Albums", template: albums, session: session),
                    categoryItem("Audiobooks", template: books, session: session),
                    categoryItem("Downloaded", template: downloaded, session: session),
                ]
                root = CPListTemplate(title: String(localized: "Gus"), sections: [CPListSection(items: rows)])
            }
            await performTemplateOperation("set library root") { controller in
                try await controller.setRootTemplate(root, animated: false)
            }
            guard isCurrent(session: session, lease: session.lease) else { return }
            downloads.load(serverID: session.server.id, userID: session.user.id)
            showDownloads(downloaded, session: session)
            observeDownloads(downloaded, session: session)
            async let albumLoad: Void = loadLibraryPage(template: albums, types: [.musicAlbum], offset: 0, session: session)
            async let bookLoad: Void = loadLibraryPage(template: books, types: [.audioBook], offset: 0, session: session)
            _ = await(albumLoad, bookLoad)
        }

        private func categoryItem(_ title: String.LocalizationValue, template: CPListTemplate, session: SessionStore) -> CPListItem {
            let row = pageItem(title) { [weak self] in
                guard let self, self.isCurrent(session: session, lease: session.lease) else { return }
                await self.performTemplateOperation("open category") { controller in
                    try await controller.pushTemplate(template, animated: true)
                }
            }
            row.accessoryType = .disclosureIndicator
            return row
        }

        private func observeDownloads(_ template: CPListTemplate, session: SessionStore) {
            withObservationTracking {
                _ = downloads.records
                _ = downloads.loadState
            } onChange: { [weak self, weak template] in
                Task { @MainActor in
                    guard let self, let template, self.isCurrent(session: session, lease: session.lease) else { return }
                    self.observeDownloads(template, session: session)
                    self.showDownloads(template, session: session)
                }
            }
        }

        private func showDownloads(_ template: CPListTemplate, offset: Int = 0, session: SessionStore) {
            guard isCurrent(session: session, lease: session.lease) else { return }
            let records = downloads.completedRecords(serverID: session.server.id, userID: session.user.id)
            let audio = DownloadedLibrary.sections(records: records, filter: .audio, search: "").flatMap(\.records)
            let size = pageSize
            let start = min(offset, max(0, (max(0, audio.count - 1) / size) * size))
            var rows = audio.dropFirst(start).prefix(size).map { record in
                actionItem(record.item.displayTitle, detail: record.item.runtimeText) { [weak self, weak template] in
                    guard let self, let template, self.isCurrent(session: session, lease: session.lease),
                          ContentRatingGate.admitsStored(record.item) else { return }
                    guard self.downloads.localFileURL(for: record.item, serverID: session.server.id, userID: session.user.id, mediaSourceID: record.mediaSourceID) != nil else {
                        self.showDownloads(template, offset: start, session: session)
                        return
                    }
                    let request = record.playbackRequest
                    await self.play(tracks: [request.item], startIndex: 0, request: request, origin: template, continuation: nil, session: session, localOnly: true)
                }
            }
            if start > 0 {
                rows.append(pageItem("Previous Page") { [weak self, weak template] in
                    guard let template else { return }
                    self?.showDownloads(template, offset: start - size, session: session)
                })
            }
            if start + size < audio.count {
                rows.append(pageItem("Next Page") { [weak self, weak template] in
                    guard let template else { return }
                    self?.showDownloads(template, offset: start + size, session: session)
                })
            }
            if downloads.loadErrorMessage != nil {
                rows.append(pageItem("Try Again", detail: String(localized: "Downloads are unavailable.")) { [weak self, weak template] in
                    guard let self, let template, self.isCurrent(session: session, lease: session.lease) else { return }
                    self.downloads.load(serverID: session.server.id, userID: session.user.id)
                    self.showDownloads(template, offset: start, session: session)
                })
            }
            template.emptyViewTitleVariants = [String(localized: "No Downloaded Audio")]
            updateSections([CPListSection(items: rows)], on: template)
        }

        private var pageSize: Int {
            CarPlayPaging.pageSize(capacity: CPListTemplate.maximumItemCount)
        }

        private func updateSections(_ sections: [CPListSection], on template: CPListTemplate) {
            let capacity = CPListTemplate.maximumItemCount
            if CPListTemplate.maximumSectionCount < sections.count ||
                sections.reduce(0, { $0 + $1.items.count }) > capacity
            {
                template.updateSections([CPListSection(items: Array(sections.flatMap(\.items).prefix(capacity)))])
            } else {
                template.updateSections(sections)
            }
        }

        private func loadLibraryPage(template: CPListTemplate, types: [MediaItemType], offset: Int, previousOffsets: [Int] = [], previousTotal: Int? = nil, session: SessionStore) async {
            let key = ObjectIdentifier(template)
            guard isCurrent(session: session, lease: session.lease), loadingTemplates.insert(key).inserted else { return }
            defer { loadingTemplates.remove(key) }
            let size = CarPlayPaging.pageSize(capacity: CPListTemplate.maximumItemCount)
            do {
                let page = try await session.mediaProvider.items(query: .init(includeTypes: types, startIndex: offset, limit: size, isRecursive: true, sort: .name))
                try Task.checkCancellation()
                guard isCurrent(session: session, lease: session.lease) else { return }
                let total = try MediaPageLoader.validatedTotal(for: page, startIndex: offset, previousTotal: previousTotal)
                let items = ContentRatingGate.filter(MediaPageLoader.unique(page.items))
                let next = CarPlayPaging.nextIndex(start: offset, rawCount: page.items.count, total: total, pageSize: size)
                template.emptyViewTitleVariants = [types == [.musicAlbum] ? String(localized: "No Albums") : String(localized: "No Audiobooks")]
                let content = types == [.musicAlbum] ? albumSection(items.filter { $0.type == .musicAlbum }, template: template, session: session) : audiobookSection(items.filter { $0.type == .audioBook }, template: template, session: session)
                var controls: [CPListItem] = []
                if let previous = previousOffsets.last {
                    controls.append(pageItem("Previous Page") { [weak self, weak template] in
                        guard let self, let template else { return }
                        await self.loadLibraryPage(template: template, types: types, offset: previous, previousOffsets: Array(previousOffsets.dropLast()), previousTotal: total, session: session)
                    })
                }
                if let next {
                    controls.append(pageItem("Next Page") { [weak self, weak template] in
                        guard let self, let template else { return }
                        await self.loadLibraryPage(template: template, types: types, offset: next, previousOffsets: previousOffsets + [offset], previousTotal: total, session: session)
                    })
                }
                let sections = [content] + (controls.isEmpty ? [] : [CPListSection(items: controls)])
                template.userInfo = sections
                updateSections(sections, on: template)
            } catch {
                let failure = GusError(from: error)
                guard !failure.isCancellation, isCurrent(session: session, lease: session.lease) else { return }
                failure.handleIfUnauthorized(session: session)
                let retry = pageItem("Try Again", detail: String(localized: "Jellyfin is unavailable.")) { [weak self, weak template] in
                    guard let self, let template else { return }
                    await self.loadLibraryPage(template: template, types: types, offset: offset, previousOffsets: previousOffsets, previousTotal: previousTotal, session: session)
                }
                updateSections((template.userInfo as? [CPListSection] ?? []) + [CPListSection(items: [retry])], on: template)
            }
        }

        private func pageItem(_ title: String.LocalizationValue, detail: String? = nil, action: @escaping @MainActor () async -> Void) -> CPListItem {
            actionItem(String(localized: title), detail: detail, action: action)
        }

        private func actionItem(_ title: String, detail: String?, action: @escaping @MainActor () async -> Void) -> CPListItem {
            let item = CPListItem(text: title, detailText: detail)
            item.handler = { [weak self] _, completion in
                guard let self, self.interfaceController != nil else { completion(); return }
                let id = UUID()
                self.rowTasks[id] = Task { [weak self] in
                    defer {
                        self?.rowTasks[id] = nil
                        completion()
                    }
                    guard !Task.isCancelled else { return }
                    await action()
                }
            }
            return item
        }

        private func audiobookSection(_ books: [MediaItem], template: CPListTemplate, session: SessionStore) -> CPListSection {
            let rows = books.map { book in
                actionItem(book.displayTitle, detail: book.runtimeText) { [weak self, weak template] in
                    guard let self, let template else { return }
                    await self.selectPlayback(tracks: [book], startIndex: 0, origin: template, continuation: nil, session: session)
                }
            }
            return CPListSection(items: rows)
        }

        private func albumSection(_ albums: [MediaItem], template: CPListTemplate, session: SessionStore) -> CPListSection {
            let items = albums.map { album in
                let row = actionItem(album.displayTitle, detail: album.albumArtist ?? album.artists.first) { [weak self, weak template] in
                    await self?.openAlbum(album, origin: template, session: session)
                }
                row.accessoryType = .disclosureIndicator
                return row
            }
            return CPListSection(items: items)
        }

        private func trackSection(_ tracks: [MediaItem], template: CPListTemplate, offset: Int, limit: Int, continuation: AudioQueueContinuation?, session: SessionStore) -> CPListSection {
            let rows = tracks.dropFirst(offset).prefix(limit).enumerated().map { index, track in
                actionItem(track.displayTitle, detail: track.runtimeText) { [weak self, weak template] in
                    guard let self, let template else { return }
                    await self.selectPlayback(tracks: tracks, startIndex: index + offset, origin: template, continuation: continuation, session: session)
                }
            }
            return CPListSection(items: rows)
        }

        private func openAlbum(_ album: MediaItem, origin: CPListTemplate?, session: SessionStore) async {
            guard let origin, isVisible(origin), isCurrent(session: session, lease: session.lease) else { return }
            do {
                let query = MediaItemQuery(parentID: album.id, includeTypes: [.audio], startIndex: 0, limit: 200, sort: .trackOrder)
                let page = try await session.mediaProvider.items(query: query)
                try Task.checkCancellation()
                guard isCurrent(session: session, lease: session.lease) else { return }
                let total = try MediaPageLoader.validatedTotal(for: page, startIndex: 0)
                let tracks = ContentRatingGate.filter(page.items).filter(\.isAudioPlayable)
                let next = CarPlayPaging.nextIndex(start: 0, rawCount: page.items.count, total: total, pageSize: query.limit)
                let continuation = next.map { AudioQueueContinuation(query: query, nextStartIndex: $0, totalRecordCount: total) }
                let template = CPListTemplate(title: album.displayTitle, sections: [])
                await showAlbumPage(template: template, tracks: tracks, continuation: continuation, offset: 0, session: session)
                guard isCurrent(session: session, lease: session.lease), isVisible(origin) else { return }
                await performTemplateOperation("push album template") { controller in try await controller.pushTemplate(template, animated: true) }
            } catch {
                let failure = GusError(from: error)
                guard !failure.isCancellation, isCurrent(session: session, lease: session.lease), isVisible(origin) else { return }
                failure.handleIfUnauthorized(session: session)
                guard session.isActive else { return }
                let retry = pageItem("Try Again", detail: String(localized: "Jellyfin is unavailable.")) { [weak self, weak origin] in
                    await self?.openAlbum(album, origin: origin, session: session)
                }
                updateSections((origin.userInfo as? [CPListSection] ?? []) + [CPListSection(items: [retry])], on: origin)
            }
        }

        private func selectPlayback(tracks: [MediaItem], startIndex: Int, origin: CPListTemplate, continuation: AudioQueueContinuation?, session: SessionStore) async {
            guard isCurrent(session: session, lease: session.lease), tracks.indices.contains(startIndex) else { return }
            playbackChoiceGeneration += 1
            let generation = playbackChoiceGeneration
            let lease = session.lease
            do {
                let item = try await session.references.currentItem(tracks[startIndex])
                guard isCurrent(session: session, lease: lease), generation == playbackChoiceGeneration, isVisible(origin) else { return }
                guard item.isAudioPlayable, ContentRatingGate.admitsStored(item) else { throw GusError.notFound }
                var currentTracks = tracks
                currentTracks[startIndex] = item
                let request = CarPlayPlaybackChoices.initialRequest(for: item)
                guard CarPlayPlaybackChoices.requiresSelection(item) else {
                    await play(tracks: currentTracks, startIndex: startIndex, request: request, origin: origin, continuation: continuation, session: session)
                    return
                }
                let choices = PlaybackChoices(request: request, tracks: currentTracks, startIndex: startIndex, continuation: continuation, session: session, generation: generation)
                let template = CPListTemplate(title: String(localized: "Playback Choices"), sections: [])
                choices.template = template
                showPlaybackChoices(choices)
                await performTemplateOperation("push playback choices") { controller in try await controller.pushTemplate(template, animated: true) }
            } catch {
                let failure = GusError(from: error)
                guard !failure.isCancellation, isCurrent(session: session, lease: lease), generation == playbackChoiceGeneration, isVisible(origin) else { return }
                failure.handleIfUnauthorized(session: session)
                guard isCurrent(session: session, lease: lease) else { return }
                let retry = pageItem("Try Again", detail: String(localized: "Jellyfin is unavailable.")) { [weak self, weak origin] in
                    guard let self, let origin else { return }
                    await self.selectPlayback(tracks: tracks, startIndex: startIndex, origin: origin, continuation: continuation, session: session)
                }
                updateSections((origin.userInfo as? [CPListSection] ?? []) + [CPListSection(items: [retry])], on: origin)
            }
        }

        private func isCurrent(_ choices: PlaybackChoices) -> Bool {
            choices.generation == playbackChoiceGeneration && isCurrent(session: choices.session, lease: choices.lease)
        }

        private func isVisible(_ template: CPListTemplate) -> Bool {
            interfaceController?.topTemplate === template || (interfaceController?.topTemplate as? CPTabBarTemplate)?.selectedTemplate === template
        }

        private func showPlaybackChoices(_ choices: PlaybackChoices) {
            guard isCurrent(choices), let template = choices.template else { return }
            var rows = [pageItem("Play", detail: choices.request.item.displayTitle) { [weak self, weak template] in
                guard let self, let template, self.isCurrent(choices), !choices.isStarting else { return }
                choices.isStarting = true
                defer { choices.isStarting = false }
                let request = choices.effectiveRequest
                await self.play(tracks: choices.tracks, startIndex: choices.startIndex, request: request, origin: template, continuation: choices.continuation, session: choices.session)
            }]
            let sources = CarPlayPlaybackChoices.sources(for: choices.request.item)
            if sources.count > 1 {
                let selectedIndex = sources.firstIndex { $0.id == choices.source?.id } ?? 0
                let title = choices.source?.name ?? String(localized: "Version \(selectedIndex + 1)")
                let row = pageItem("Version", detail: title) { [weak self] in self?.showSourceChoices(choices) }
                row.accessoryType = .disclosureIndicator
                rows.append(row)
            }
            if let source = choices.source, CarPlayPlaybackChoices.audioStreams(in: source).count > 1 {
                let selected = choices.request.selection(in: source).audioStreamIndex
                let stream = source.mediaStreams.first { $0.type == .audio && $0.index == selected }
                let title = stream.map(Self.audioTitle) ?? choices.request.audioTrack.map(Self.audioTitle) ?? String(localized: "Automatic")
                let row = pageItem("Audio", detail: title) { [weak self] in self?.showAudioChoices(choices) }
                row.accessoryType = .disclosureIndicator
                rows.append(row)
            }
            if let source = choices.source, choices.request.audioTrack != nil, choices.request.selection(in: source).audioStreamIndex == nil {
                rows.append(CPListItem(text: String(localized: "A selected track was unavailable. The player will use its default tracks."), detailText: nil))
            }
            updateSections([CPListSection(items: rows)], on: template)
        }

        private static func audioTitle(_ stream: MediaStreamInfo) -> String {
            stream.displayTitle ?? stream.title ?? stream.language ?? String(localized: "Audio \((stream.index ?? 0).formatted())")
        }

        /// Reuse one native list for option pages; no extra navigation-stack depth.
        private func showSourceChoices(_ choices: PlaybackChoices, offset: Int = 0) {
            guard isCurrent(choices), let template = choices.template else { return }
            let sources = CarPlayPlaybackChoices.sources(for: choices.request.item)
            let size = CarPlayPaging.pageSize(capacity: CPListTemplate.maximumItemCount)
            let rows = sources.dropFirst(offset).prefix(size).enumerated().map { position, source in
                let row = CPListItem(text: source.name ?? String(localized: "Version \(offset + position + 1)"), detailText: nil)
                if source.id == choices.source?.id {
                    row.setAccessoryImage(UIImage(systemName: "checkmark"))
                }
                row.handler = { [weak self] _, completion in
                    Task { @MainActor in
                        self?.chooseSource(source, choices: choices, offset: offset)
                        completion()
                    }
                }
                return row
            }
            var controls = [pageItem("Back") { [weak self] in self?.showPlaybackChoices(choices) }]
            if offset > 0 {
                controls.append(pageItem("Previous Page") { [weak self] in self?.showSourceChoices(choices, offset: max(0, offset - size)) })
            }
            if offset + size < sources.count {
                controls.append(pageItem("Next Page") { [weak self] in self?.showSourceChoices(choices, offset: offset + size) })
            }
            updateSections([CPListSection(items: rows), CPListSection(items: controls)], on: template)
        }

        private func chooseSource(_ source: MediaSource, choices: PlaybackChoices, offset: Int) {
            guard isCurrent(choices), let template = choices.template, source.id != choices.source?.id else { return }
            let ticks = choices.positionTicks
            guard ticks > 0 else {
                if let request = CarPlayPlaybackChoices.selectingSource(source, request: choices.request, startTicks: 0) {
                    choices.selectSource(request, ticks: 0, fromBeginning: true)
                }
                showPlaybackChoices(choices)
                return
            }
            let startOver = pageItem("Start Over") { [weak self] in
                guard let self, self.isCurrent(choices), let request = CarPlayPlaybackChoices.selectingSource(source, request: choices.request, startTicks: 0) else { return }
                choices.selectSource(request, ticks: 0, fromBeginning: true)
                self.showPlaybackChoices(choices)
            }
            let resume = pageItem("Resume at Timestamp", detail: PlaybackTime.accessibilityDuration(seconds: PlaybackTime.seconds(fromTicks: ticks))) { [weak self] in
                guard let self, self.isCurrent(choices), let request = CarPlayPlaybackChoices.selectingSource(source, request: choices.request, startTicks: ticks) else { return }
                choices.selectSource(request, ticks: ticks, fromBeginning: false)
                self.showPlaybackChoices(choices)
            }
            resume.isEnabled = CarPlayPlaybackChoices.selectingSource(source, request: choices.request, startTicks: ticks) != nil
            let cancel = pageItem("Cancel") { [weak self] in self?.showSourceChoices(choices, offset: offset) }
            template.updateSections([CPListSection(items: [startOver, resume, cancel], header: String(localized: "Different versions may have different timelines."), sectionIndexTitle: nil)])
        }

        private func showAudioChoices(_ choices: PlaybackChoices, offset: Int = 0) {
            guard isCurrent(choices), let template = choices.template, let source = choices.source else { return }
            // Automatic is a real choice alongside source-local indexed tracks.
            let options: [MediaStreamInfo?] = [nil] + CarPlayPlaybackChoices.audioStreams(in: source).map(Optional.some)
            let size = CarPlayPaging.pageSize(capacity: CPListTemplate.maximumItemCount)
            let rows = options.dropFirst(offset).prefix(size).map { stream in
                let row = CPListItem(text: stream.map(Self.audioTitle) ?? String(localized: "Automatic"), detailText: nil)
                if CarPlayPlaybackChoices.isAudioSelected(stream, source: source, request: choices.request) {
                    row.setAccessoryImage(UIImage(systemName: "checkmark"))
                }
                row.handler = { [weak self] _, completion in
                    Task { @MainActor in
                        if let self, self.isCurrent(choices) {
                            choices.request = CarPlayPlaybackChoices.selectingAudio(stream, source: source, request: choices.request)
                            self.showPlaybackChoices(choices)
                        }
                        completion()
                    }
                }
                return row
            }
            var controls = [pageItem("Back") { [weak self] in self?.showPlaybackChoices(choices) }]
            if offset > 0 {
                controls.append(pageItem("Previous Page") { [weak self] in self?.showAudioChoices(choices, offset: max(0, offset - size)) })
            }
            if offset + size < options.count {
                controls.append(pageItem("Next Page") { [weak self] in self?.showAudioChoices(choices, offset: offset + size) })
            }
            updateSections([CPListSection(items: rows), CPListSection(items: controls)], on: template)
        }

        private func play(tracks: [MediaItem], startIndex: Int, request: PlaybackRequest, origin: CPListTemplate, continuation: AudioQueueContinuation?, session: SessionStore, localOnly: Bool = false) async {
            guard isCurrent(session: session, lease: session.lease), isVisible(origin), tracks.indices.contains(startIndex) else { return }
            let player = playback.play(tracks: tracks, startIndex: startIndex, localOnly: localOnly, request: request, continuation: continuation, session: session, downloads: downloads, presentOnPhone: false)
            await presentPlayback(player, origin: origin, session: session, restoringSections: origin.userInfo as? [CPListSection] ?? origin.sections)
        }

        private func isCurrent(session: SessionStore, lease: SessionLease) -> Bool {
            !Task.isCancelled && interfaceController != nil && session.isActive && appModel.currentSession === session && session.lease == lease
        }

        private func presentPlayback(_ player: AudioPlayerStore, origin: CPListTemplate, session: SessionStore, restoringSections sections: [CPListSection]) async {
            await playback.waitForPreparation(of: player)
            guard isCurrent(session: session, lease: session.lease), playback.store === player, isVisible(origin) else { return }
            guard player.state == .loaded, player.hasPreparedContent else {
                if case .failed = player.state {
                    let retry = pageItem("Try Again", detail: String(localized: "Audio playback is unavailable.")) { [weak self, weak player, weak origin] in
                        guard let self, let player, let origin,
                              self.isCurrent(session: session, lease: session.lease), self.playback.store === player else { return }
                        self.playback.retry()
                        await self.presentPlayback(player, origin: origin, session: session, restoringSections: sections)
                    }
                    updateSections(sections + [CPListSection(items: [retry])], on: origin)
                }
                return
            }
            updateSections(sections, on: origin)
            await performTemplateOperation("push now playing template") { interfaceController in
                guard interfaceController.topTemplate !== CPNowPlayingTemplate.shared,
                      interfaceController.templates.count < 5 else { return }
                try await interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
            }
        }

        private func showAlbumPage(template: CPListTemplate, tracks initialTracks: [MediaItem], continuation initialContinuation: AudioQueueContinuation?, offset: Int, session: SessionStore) async {
            guard isCurrent(session: session, lease: session.lease) else { return }
            var tracks = initialTracks
            var continuation = initialContinuation
            if offset >= tracks.count, continuation != nil {
                do {
                    for _ in 0 ..< 3 {
                        guard var next = continuation else { break }
                        var query = next.query
                        query.startIndex = next.nextStartIndex
                        let page = try await session.mediaProvider.items(query: query)
                        try Task.checkCancellation()
                        guard isCurrent(session: session, lease: session.lease) else { return }
                        let total = try MediaPageLoader.validatedTotal(for: page, startIndex: query.startIndex, previousTotal: next.totalRecordCount)
                        let additions = MediaPageLoader.unique(ContentRatingGate.filter(page.items).filter(\.isAudioPlayable), after: tracks)
                        tracks += additions
                        next.nextStartIndex += page.items.count
                        next.totalRecordCount = total
                        continuation = CarPlayPaging.nextIndex(start: query.startIndex, rawCount: page.items.count, total: total, pageSize: query.limit) == nil ? nil : next
                        if !additions.isEmpty || continuation == nil {
                            break
                        }
                    }
                } catch {
                    let failure = GusError(from: error)
                    guard !failure.isCancellation, session.isActive else { return }
                    let retry = pageItem("Try Again", detail: String(localized: "Jellyfin is unavailable.")) { [weak self, weak template] in
                        guard let self, let template else { return }
                        await self.showAlbumPage(template: template, tracks: initialTracks, continuation: initialContinuation, offset: offset, session: session)
                    }
                    updateSections((template.userInfo as? [CPListSection] ?? []) + [CPListSection(items: [retry])], on: template)
                    return
                }
            }
            let size = CarPlayPaging.pageSize(capacity: CPListTemplate.maximumItemCount)
            let visibleOffset = min(offset, max(0, tracks.count - 1))
            let loadedTracks = tracks
            let pending = continuation
            var controls: [CPListItem] = []
            if visibleOffset > 0 {
                controls.append(pageItem("Previous Page") { [weak self, weak template] in
                    guard let self, let template else { return }
                    await self.showAlbumPage(template: template, tracks: loadedTracks, continuation: pending, offset: max(0, visibleOffset - size), session: session)
                })
            }
            if visibleOffset + size < tracks.count || continuation != nil {
                controls.append(pageItem("Next Page") { [weak self, weak template] in
                    guard let self, let template else { return }
                    await self.showAlbumPage(template: template, tracks: loadedTracks, continuation: pending, offset: visibleOffset + size, session: session)
                })
            }
            let sections = [trackSection(tracks, template: template, offset: visibleOffset, limit: size, continuation: continuation, session: session)] + (controls.isEmpty ? [] : [CPListSection(items: controls)])
            template.userInfo = sections
            template.emptyViewTitleVariants = [String(localized: "No Tracks")]
            updateSections(sections, on: template)
        }

        private func performTemplateOperation(
            _ operation: String,
            _ body: (CPInterfaceController) async throws -> Void
        ) async {
            guard !Task.isCancelled, let interfaceController else { return }
            do {
                try await body(interfaceController)
            } catch {
                logger.error("CarPlay template operation failed: \(operation, privacy: .public), \(error.localizedDescription, privacy: .private)")
            }
        }
    }
#endif

/// Pure intent policy shared by native CarPlay rows and regression checks.
enum CarPlayPlaybackChoices {
    static func sources(for item: MediaItem) -> [MediaSource] {
        var seen = Set<String>()
        return item.mediaSources.filter { source in
            guard let id = source.id, !id.isEmpty else { return false }
            return seen.insert(id).inserted
        }
    }

    static func audioStreams(in source: MediaSource) -> [MediaStreamInfo] {
        var seen = Set<Int>()
        return source.mediaStreams.filter { stream in
            guard stream.type == .audio, let index = stream.index, index >= 0 else { return false }
            return seen.insert(index).inserted
        }
    }

    static func requiresSelection(_ item: MediaItem) -> Bool {
        let sources = sources(for: item)
        return sources.count > 1 || sources.first.map { audioStreams(in: $0).count > 1 } == true
    }

    static func initialRequest(for item: MediaItem) -> PlaybackRequest {
        var request = PlaybackRequest(item: item)
        request.streamSelection.mediaSourceID = sources(for: item).first?.id
        return request
    }

    static func selectingSource(_ source: MediaSource, request: PlaybackRequest, startTicks: Int) -> PlaybackRequest? {
        guard let id = source.id, !id.isEmpty, startTicks >= 0, PlaybackActionPosition.canResume(at: startTicks, durationTicks: source.runTimeTicks) else { return nil }
        return request.selectingMediaSource(id, startPositionTicks: startTicks)
    }

    static func selectingAudio(_ stream: MediaStreamInfo?, source: MediaSource, request: PlaybackRequest) -> PlaybackRequest {
        var result = request
        result.streamSelection.mediaSourceID = source.id
        result.streamSelection.audioStreamIndex = stream?.index
        result.audioTrack = stream
        return result
    }

    @MainActor static func isAudioSelected(_ stream: MediaStreamInfo?, source: MediaSource, request: PlaybackRequest) -> Bool {
        let selected = request.selection(in: source).audioStreamIndex
        guard let stream else { return request.audioTrack == nil && selected == nil }
        return selected == stream.index
    }
}

/// Leave native capacity for navigation and retry, counting raw server records.
enum CarPlayPaging {
    static func pageSize(capacity: Int) -> Int {
        max(1, min(100, capacity - 3))
    }

    static func nextIndex(start: Int, rawCount: Int, total: Int?, pageSize: Int) -> Int? {
        guard rawCount > 0 else { return nil }
        let next = start + rawCount
        return total.map { next < $0 } ?? (rawCount >= pageSize) ? next : nil
    }
}
