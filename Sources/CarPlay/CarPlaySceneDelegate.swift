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
        private var successfulSections: [ObjectIdentifier: [CPListSection]] = [:]
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

        func start(interfaceController: CPInterfaceController) async {
            self.interfaceController = interfaceController
            observeSession()
            await appModel.restoreLastSession()

            guard let session = appModel.currentSession else {
                await setSignedOutRoot()
                return
            }
            await setLibraryRoot(session: session)
        }

        func teardown() {
            observationGeneration += 1
            playbackChoiceGeneration += 1
            audioPlayer?.teardown()
            audioPlayer = nil
            interfaceController = nil
            successfulSections = [:]
            loadingTemplates = []
        }

        private func observeSession() {
            let generation = observationGeneration
            withObservationTracking { _ = appModel.currentSession } onChange: { [weak self] in
                Task { @MainActor in
                    guard let self, self.observationGeneration == generation, self.interfaceController != nil else { return }
                    self.audioPlayer?.teardown()
                    self.audioPlayer = nil
                    self.playbackChoiceGeneration += 1
                    self.successfulSections = [:]
                    self.loadingTemplates = []
                    self.observeSession()
                    if let session = self.appModel.currentSession {
                        await self.setLibraryRoot(session: session)
                    } else {
                        await self.setSignedOutRoot()
                    }
                }
            }
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
            let albums = CPListTemplate(title: String(localized: "Albums"), sections: [])
            albums.tabImage = UIImage(systemName: "music.note.list")
            let books = CPListTemplate(title: String(localized: "Audiobooks"), sections: [])
            books.tabImage = UIImage(systemName: "book")
            let tabBar = CPTabBarTemplate(templates: [albums, books])
            await performTemplateOperation("set library root") { controller in
                try await controller.setRootTemplate(tabBar, animated: false)
            }
            async let albumLoad: Void = loadLibraryPage(template: albums, types: [.musicAlbum], offset: 0, session: session)
            async let bookLoad: Void = loadLibraryPage(template: books, types: [.audioBook], offset: 0, session: session)
            _ = await(albumLoad, bookLoad)
        }

        private func loadLibraryPage(template: CPListTemplate, types: [MediaItemType], offset: Int, previousTotal: Int? = nil, session: SessionStore) async {
            let key = ObjectIdentifier(template)
            guard session.isActive, loadingTemplates.insert(key).inserted else { return }
            defer { loadingTemplates.remove(key) }
            let size = CarPlayPaging.pageSize(capacity: Int(CPListTemplate.maximumItemCount))
            do {
                let page = try await session.mediaProvider.items(query: .init(includeTypes: types, startIndex: offset, limit: size, isRecursive: true, sort: .name))
                try Task.checkCancellation()
                guard session.isActive, interfaceController != nil else { return }
                let total = try MediaPageLoader.validatedTotal(for: page, startIndex: offset, previousTotal: previousTotal)
                let items = ContentRatingGate.filter(MediaPageLoader.unique(page.items))
                let next = CarPlayPaging.nextIndex(start: offset, rawCount: page.items.count, total: total, pageSize: size)
                let continuation = next.map { AudioQueueContinuation(query: .init(includeTypes: types, startIndex: 0, limit: size, isRecursive: true, sort: .name), nextStartIndex: $0, totalRecordCount: total) }
                let content = types == [.musicAlbum] ? albumSection(items, template: template, session: session) : audiobookSection(items, template: template, continuation: continuation, session: session)
                var controls: [CPListItem] = []
                if offset > 0 {
                    controls.append(pageItem("Previous Page") { [weak self, weak template] in
                        guard let self, let template else { return }
                        await self.loadLibraryPage(template: template, types: types, offset: max(0, offset - size), previousTotal: total, session: session)
                    })
                }
                if let next {
                    controls.append(pageItem("Next Page") { [weak self, weak template] in
                        guard let self, let template else { return }
                        await self.loadLibraryPage(template: template, types: types, offset: next, previousTotal: total, session: session)
                    })
                }
                let sections = [content] + (controls.isEmpty ? [] : [CPListSection(items: controls)])
                successfulSections[key] = sections
                template.updateSections(sections)
            } catch {
                let failure = GusError(from: error)
                guard !failure.isCancellation, session.isActive, interfaceController != nil else { return }
                failure.handleIfUnauthorized(session: session)
                let retry = pageItem("Try Again", detail: failure.localizedDescription) { [weak self, weak template] in
                    guard let self, let template else { return }
                    await self.loadLibraryPage(template: template, types: types, offset: offset, previousTotal: previousTotal, session: session)
                }
                template.updateSections((successfulSections[key] ?? []) + [CPListSection(items: [retry])])
            }
        }

        private func pageItem(_ title: String.LocalizationValue, detail: String? = nil, action: @escaping @MainActor () async -> Void) -> CPListItem {
            let item = CPListItem(text: String(localized: title), detailText: detail)
            item.handler = { _, completion in
                Task { @MainActor in await action(); completion() }
            }
            return item
        }

        private func audiobookSection(_ books: [MediaItem], template: CPListTemplate, continuation: AudioQueueContinuation?, session: SessionStore) -> CPListSection {
            trackSection(books, template: template, continuation: continuation, session: session)
        }

        private func albumSection(_ albums: [MediaItem], template: CPListTemplate, session: SessionStore) -> CPListSection {
            let items = albums.map { album in
                let listItem = CPListItem(
                    text: album.displayTitle,
                    detailText: album.albumArtist ?? album.artists.first
                )
                listItem.handler = { [weak self, weak template] _, completion in
                    Task { @MainActor in
                        await self?.openAlbum(album, origin: template, session: session)
                        completion()
                    }
                }
                return listItem
            }
            return CPListSection(items: items)
        }

        /// Rows that play directly (album tracks, audiobooks).
        private func trackSection(_ tracks: [MediaItem], template: CPListTemplate, offset: Int = 0, limit: Int? = nil, continuation: AudioQueueContinuation? = nil, session: SessionStore) -> CPListSection {
            let items = tracks.dropFirst(offset).prefix(limit ?? tracks.count).enumerated().map { index, track in
                let listItem = CPListItem(text: track.displayTitle, detailText: track.runtimeText)
                listItem.handler = { [weak self, weak template] _, completion in
                    Task { @MainActor in
                        if let template {
                            await self?.selectPlayback(tracks: tracks, startIndex: index + offset, origin: template, continuation: continuation, session: session)
                        }
                        completion()
                    }
                }
                return listItem
            }
            return CPListSection(items: items)
        }

        private func openAlbum(_ album: MediaItem, origin: CPListTemplate?, session: SessionStore) async {
            do {
                let query = MediaItemQuery(parentID: album.id, startIndex: 0, limit: 200, sort: .trackOrder)
                let page = try await session.mediaProvider.items(query: query)
                try Task.checkCancellation()
                guard session.isActive else { return }
                let total = try MediaPageLoader.validatedTotal(for: page, startIndex: 0)
                let tracks = ContentRatingGate.filter(page.items).filter(\.isAudioPlayable)
                let next = CarPlayPaging.nextIndex(start: 0, rawCount: page.items.count, total: total, pageSize: query.limit)
                let continuation = next.map { AudioQueueContinuation(query: query, nextStartIndex: $0, totalRecordCount: total) }
                let template = CPListTemplate(title: album.displayTitle, sections: [])
                await showAlbumPage(template: template, tracks: tracks, continuation: continuation, offset: 0, session: session)
                await performTemplateOperation("push album template") { controller in try await controller.pushTemplate(template, animated: true) }
            } catch {
                let failure = GusError(from: error)
                guard !failure.isCancellation, session.isActive, let origin else { return }
                let retry = pageItem("Try Again", detail: failure.localizedDescription) { [weak self, weak origin] in
                    await self?.openAlbum(album, origin: origin, session: session)
                }
                origin.updateSections((successfulSections[ObjectIdentifier(origin)] ?? []) + [CPListSection(items: [retry])])
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
                let retry = pageItem("Try Again", detail: failure.localizedDescription) { [weak self, weak origin] in
                    guard let self, let origin else { return }
                    await self.selectPlayback(tracks: tracks, startIndex: startIndex, origin: origin, continuation: continuation, session: session)
                }
                origin.updateSections((successfulSections[ObjectIdentifier(origin)] ?? []) + [CPListSection(items: [retry])])
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
            template.updateSections([CPListSection(items: rows)])
        }

        private static func audioTitle(_ stream: MediaStreamInfo) -> String {
            stream.displayTitle ?? stream.title ?? stream.language ?? String(localized: "Audio \((stream.index ?? 0).formatted())")
        }

        /// Reuse one native list for option pages; no extra navigation-stack depth.
        private func showSourceChoices(_ choices: PlaybackChoices, offset: Int = 0) {
            guard isCurrent(choices), let template = choices.template else { return }
            let sources = CarPlayPlaybackChoices.sources(for: choices.request.item)
            let size = CarPlayPaging.pageSize(capacity: Int(CPListTemplate.maximumItemCount))
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
            template.updateSections([CPListSection(items: rows), CPListSection(items: controls)])
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
            let size = CarPlayPaging.pageSize(capacity: Int(CPListTemplate.maximumItemCount))
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
            template.updateSections([CPListSection(items: rows), CPListSection(items: controls)])
        }

        private func play(tracks: [MediaItem], startIndex: Int, request: PlaybackRequest, origin: CPListTemplate, continuation: AudioQueueContinuation?, session: SessionStore) async {
            guard isCurrent(session: session, lease: session.lease), tracks.indices.contains(startIndex) else { return }
            audioPlayer?.teardown()
            let player = AudioPlayerStore(session: session, tracks: tracks, startIndex: startIndex, request: request, continuation: continuation)
            audioPlayer = player
            await prepareAndPresent(player, origin: origin, session: session, lease: session.lease)
        }

        private func isCurrent(session: SessionStore, lease: SessionLease) -> Bool {
            interfaceController != nil && session.isActive && appModel.currentSession === session && appModel.currentSession?.lease == lease
        }

        private func prepareAndPresent(_ player: AudioPlayerStore, origin: CPListTemplate, session: SessionStore, lease: SessionLease, restoringSections: [CPListSection]? = nil) async {
            guard isCurrent(session: session, lease: lease), audioPlayer === player else { return }
            let sections = restoringSections ?? successfulSections[ObjectIdentifier(origin)] ?? origin.sections
            await player.start()
            // Preparation can suspend through account replacement, disconnect, or
            // another selection. None may publish this player's old presentation.
            guard isCurrent(session: session, lease: lease), audioPlayer === player else { return }
            guard player.state == .loaded, player.hasPreparedContent else {
                if case let .failed(message) = player.state {
                    let retry = pageItem("Try Again", detail: message) { [weak self, weak player, weak origin] in
                        guard let self, let player, let origin else { return }
                        await self.prepareAndPresent(player, origin: origin, session: session, lease: lease, restoringSections: sections)
                    }
                    origin.updateSections(sections + [CPListSection(items: [retry])])
                }
                return
            }
            origin.updateSections(sections)
            guard isVisible(origin) else { return }
            await performTemplateOperation("push now playing template") { interfaceController in
                try await interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
            }
        }

        private func showAlbumPage(template: CPListTemplate, tracks initialTracks: [MediaItem], continuation initialContinuation: AudioQueueContinuation?, offset: Int, session: SessionStore) async {
            guard session.isActive else { return }
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
                        guard session.isActive else { return }
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
                    let retry = pageItem("Try Again", detail: failure.localizedDescription) { [weak self, weak template] in
                        guard let self, let template else { return }
                        await self.showAlbumPage(template: template, tracks: initialTracks, continuation: initialContinuation, offset: offset, session: session)
                    }
                    template.updateSections((successfulSections[ObjectIdentifier(template)] ?? []) + [CPListSection(items: [retry])])
                    return
                }
            }
            let size = CarPlayPaging.pageSize(capacity: Int(CPListTemplate.maximumItemCount))
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
            successfulSections[ObjectIdentifier(template)] = sections
            template.updateSections(sections)
        }

        private func performTemplateOperation(
            _ operation: String,
            _ body: (CPInterfaceController) async throws -> Void
        ) async {
            guard let interfaceController else { return }
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
