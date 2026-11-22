#if os(iOS) && canImport(Intents)
    import Foundation
    @preconcurrency import Intents

    final class SiriMediaHandler: NSObject, INPlayMediaIntentHandling {
        private struct Request: Sendable {
            let title: String
            let artist: String?
            let identifier: String?
            let types: [MediaItemType]

            init?(_ intent: INPlayMediaIntent) {
                let requested = intent.mediaItems?.first
                let search = intent.mediaSearch
                guard let title = (requested?.title ?? search?.mediaName)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty else { return nil }
                let type = requested?.type ?? search?.mediaType ?? .unknown
                types = switch type {
                case .song: [.audio]
                case .album: [.musicAlbum]
                case .audioBook: [.audioBook]
                case .unknown: [.audio, .musicAlbum, .audioBook]
                default: []
                }
                guard !types.isEmpty else { return nil }
                self.title = title
                artist = requested?.artist ?? search?.artistName
                identifier = requested?.identifier
            }
        }

        func resolveMediaItems(for intent: INPlayMediaIntent) async -> [INPlayMediaMediaItemResolutionResult] {
            guard let request = Request(intent) else { return [.unsupported()] }
            let matches = await Self.resolve(request)
            let items = matches.map { Self.siriItem($0.item, identifier: $0.identifier) }
            if items.count > 1 {
                return [.disambiguation(with: items)]
            }
            return items.isEmpty ? [.unsupported()] : INPlayMediaMediaItemResolutionResult.successes(with: items)
        }

        func handle(intent: INPlayMediaIntent) async -> INPlayMediaIntentResponse {
            guard let request = Request(intent) else { return INPlayMediaIntentResponse(code: .failure, userActivity: nil) }
            let code = await Self.play(request)
            return INPlayMediaIntentResponse(code: code, userActivity: nil)
        }

        @MainActor private static func resolve(_ request: Request) async -> [(item: MediaItem, identifier: String)] {
            guard let result = await lookup(request) else { return [] }
            return result.matches.compactMap { item in
                guard let id = item.id else { return nil }
                return (item, GusIntentID.make(resource: "media", id: id, provider: item.providerKind, scope: result.session.references.scope))
            }
        }

        @MainActor private static func lookup(_ request: Request) async -> (session: SessionStore, matches: [MediaItem])? {
            guard let session = try? await GusIntentRuntime.session() else { return nil }
            let identifier = request.identifier.flatMap {
                GusIntentID.value($0, resource: "media", provider: session.server.providerKind, scope: session.references.scope)
            }
            if request.identifier != nil, identifier == nil {
                return nil
            }
            do {
                let candidates: [MediaItem]
                if let identifier {
                    let item = try await PlaybackDeadline.run(for: .seconds(5)) { try await session.mediaProvider.item(id: identifier) }
                    guard item.providerKind == session.server.providerKind else { return nil }
                    candidates = Self.matches([item], title: request.title, artist: request.artist, identifier: identifier, types: request.types)
                } else {
                    let page = try await PlaybackDeadline.run(for: .seconds(5)) {
                        try await GusIntentRuntime.search(request.title, in: session, types: request.types)
                    }
                    candidates = Self.matches(page.items, title: request.title, artist: request.artist, identifier: nil, types: request.types)
                    // An incomplete page can neither prove uniqueness nor authorize a one-hit auto-play.
                    if candidates.count == 1, (page.totalRecordCount ?? 0) > 50 {
                        return nil
                    }
                }
                try GusIntentRuntime.validate(session)
                return (session, candidates)
            } catch {
                let failure = GusError(from: error)
                failure.handleIfUnauthorized(session: session)
                guard GusIntentRuntime.canUseDownload(after: error),
                      let records = try? GusIntentRuntime.completedDownloads(in: session) else { return nil }
                let policy = ContentRatingGate.storedPolicy()
                let items = records.filter { $0.isAdmitted(by: policy.admits) }.map(\.playbackItem) + DownloadedLibrary.albums(in: records)
                return (session, Self.matches(items, title: request.title, artist: request.artist, identifier: identifier, types: request.types))
            }
        }

        @MainActor private static func play(_ selection: Request) async -> INPlayMediaIntentResponseCode {
            let app = AppModel.shared
            guard let lookup = await lookup(selection), lookup.matches.count == 1, let item = lookup.matches.first,
                  app.currentSession === lookup.session, lookup.session.isActive else { return .failure }
            return await startAudio(item, session: lookup.session) ? .success : .failure
        }

        @MainActor static func startAudio(_ item: MediaItem, session: SessionStore, shuffle: Bool = false, repeating: Bool = false) async -> Bool {
            let app = AppModel.shared
            let audio = app.audioPlayback
            guard let id = item.id, app.currentSession === session, session.isActive else { return false }
            let downloads = OfflineDownloadStore.shared
            downloads.load(serverID: session.server.id, userID: session.user.id)
            var tracks = [item]
            var request = PlaybackRequest(item: item)
            var continuation: AudioQueueContinuation?
            var localOnly = false
            if item.type == .musicAlbum {
                let query = MediaItemQuery(parentID: id, includeTypes: [.audio], startIndex: 0, limit: 100, sort: .trackOrder)
                let provider = session.mediaProvider
                do {
                    let page = try await PlaybackDeadline.run(for: .seconds(5)) { try await provider.items(query: query) }
                    let total = try MediaPageLoader.validatedTotal(for: page, startIndex: 0)
                    tracks = ContentRatingGate.filter(MediaPageLoader.unique(page.items)).filter { $0.type == .audio && $0.id != nil }
                    guard let first = tracks.first else { return false }
                    request = PlaybackRequest(item: first)
                    continuation = CarPlayPaging.nextIndex(start: 0, rawCount: page.items.count, total: total, pageSize: query.limit).map {
                        AudioQueueContinuation(query: query, nextStartIndex: $0, totalRecordCount: total)
                    }
                } catch {
                    let failure = GusError(from: error)
                    failure.handleIfUnauthorized(session: session)
                    guard GusIntentRuntime.canUseDownload(after: error), let records = try? GusIntentRuntime.completedDownloads(in: session) else { return false }
                    let downloadedTracks = DownloadedLibrary.tracks(in: records, albumID: id)
                    guard let first = downloadedTracks.first else { return false }
                    request = first.playbackRequest
                    tracks = downloadedTracks.map(\.playbackItem)
                    localOnly = true
                }
            } else if let record = downloads.record(for: item, serverID: session.server.id, userID: session.user.id),
                      downloads.localFileURL(for: item, serverID: session.server.id, userID: session.user.id, mediaSourceID: record.mediaSourceID) != nil
            {
                request = record.playbackRequest
                tracks = [request.item]
                localOnly = true
            }
            guard app.currentSession === session, session.isActive, !Task.isCancelled, ContentRatingGate.admitsStored(request.item) else { return false }
            let player = audio.play(tracks: tracks, shuffled: shuffle, localOnly: localOnly, request: request, continuation: continuation, session: session, downloads: downloads, presentOnPhone: false)
            if repeating {
                player.cycleRepeatMode()
            }
            await audio.waitForPreparation(of: player)
            guard session.isActive, audio.store === player, player.hasPreparedContent, player.state == .loaded else { return false }
            return true
        }

        static func matches(_ items: [MediaItem], title: String, artist: String?, identifier: String?, types: [MediaItemType]) -> [MediaItem] {
            let eligible = MediaPageLoader.unique(items).filter { item in
                guard let type = item.type, types.contains(type), item.id != nil else { return false }
                return ContentRatingGate.admitsStored(item)
            }
            if let identifier {
                return eligible.filter { $0.id == identifier }
            }
            return Array(eligible.filter { item in
                guard item.displayTitle.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else { return false }
                guard let artist, !artist.isEmpty else { return true }
                let names = item.artists + item.bookAuthorNames + [item.albumArtist].compactMap { $0 }
                return names.contains { $0.compare(artist, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            }.prefix(5))
        }

        private static func siriItem(_ item: MediaItem, identifier: String) -> INMediaItem {
            let type: INMediaItemType = switch item.type {
            case .audio: .song
            case .audioBook: .audioBook
            case .musicAlbum: .album
            default: .unknown
            }
            return INMediaItem(identifier: identifier, title: item.displayTitle, type: type, artwork: nil, artist: item.albumArtist ?? item.artists.first ?? item.bookAuthorNames.first)
        }
    }
#endif
