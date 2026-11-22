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
            let items = await Self.resolve(request).compactMap(Self.siriItem)
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

        @MainActor private static func resolve(_ request: Request) async -> [MediaItem] {
            await lookup(request)?.matches ?? []
        }

        @MainActor private static func lookup(_ request: Request) async -> (session: SessionStore, matches: [MediaItem])? {
            let app = AppModel.shared
            await app.restoreLastSession()
            guard let session = app.currentSession,
                  await session.ageRangeAccess.permitsExternalMedia(isCurrent: { app.currentSession === session && session.isActive }) else { return nil }
            let downloads = OfflineDownloadStore.shared
            let serverID = session.server.id
            let userID = session.user.id
            downloads.load(serverID: serverID, userID: userID)
            let records = downloads.completedRecords(serverID: serverID, userID: userID)
            let albums = Self.downloadedAlbums(records)
            let local = records.map(\.item) + albums
            let localMatches = Self.matches(local, title: request.title, artist: request.artist, identifier: request.identifier, types: request.types)
            if !localMatches.isEmpty {
                return (session, localMatches)
            }
            let provider = session.mediaProvider
            do {
                let page = try await PlaybackDeadline.run(for: .seconds(5)) {
                    try await provider.items(query: MediaItemQuery(searchTerm: request.title, includeTypes: request.types, startIndex: 0, limit: 30, isRecursive: true))
                }
                guard app.currentSession === session, session.isActive, !Task.isCancelled else { return nil }
                return (session, Self.matches(page.items, title: request.title, artist: request.artist, identifier: request.identifier, types: request.types))
            } catch {
                GusError(from: error).handleIfUnauthorized(session: session)
                return nil
            }
        }

        @MainActor private static func play(_ selection: Request) async -> INPlayMediaIntentResponseCode {
            let app = AppModel.shared
            let audio = app.audioPlayback
            guard let lookup = await lookup(selection), lookup.matches.count == 1, let item = lookup.matches.first,
                  app.currentSession === lookup.session, lookup.session.isActive, let id = item.id else { return .failure }
            let session = lookup.session
            let downloads = OfflineDownloadStore.shared
            var tracks = [item]
            var request = PlaybackRequest(item: item)
            var continuation: AudioQueueContinuation?
            var localOnly = false
            let downloadedTracks = Self.downloadedAlbumTracks(
                downloads.completedRecords(serverID: session.server.id, userID: session.user.id), albumID: id
            )
            if item.type == .musicAlbum, let first = downloadedTracks.first {
                request = first.playbackRequest
                tracks = downloadedTracks.map(\.playbackItem)
                localOnly = true
            } else if item.type == .musicAlbum {
                let query = MediaItemQuery(parentID: id, includeTypes: [.audio], startIndex: 0, limit: 100, sort: .trackOrder)
                let provider = session.mediaProvider
                do {
                    let page = try await PlaybackDeadline.run(for: .seconds(5)) { try await provider.items(query: query) }
                    let total = try MediaPageLoader.validatedTotal(for: page, startIndex: 0)
                    tracks = ContentRatingGate.filter(MediaPageLoader.unique(page.items)).filter { $0.type == .audio && $0.id != nil }
                    guard let first = tracks.first else { return .failure }
                    request = PlaybackRequest(item: first)
                    continuation = CarPlayPaging.nextIndex(start: 0, rawCount: page.items.count, total: total, pageSize: query.limit).map {
                        AudioQueueContinuation(query: query, nextStartIndex: $0, totalRecordCount: total)
                    }
                } catch {
                    GusError(from: error).handleIfUnauthorized(session: session)
                    return .failure
                }
            } else if let record = downloads.record(for: item, serverID: session.server.id, userID: session.user.id),
                      downloads.localFileURL(for: item, serverID: session.server.id, userID: session.user.id, mediaSourceID: record.mediaSourceID) != nil
            {
                request = record.playbackRequest
                tracks = [request.item]
                localOnly = true
            }
            guard app.currentSession === session, session.isActive, !Task.isCancelled, ContentRatingGate.admitsStored(request.item) else { return .failure }
            let player = audio.play(tracks: tracks, localOnly: localOnly, request: request, continuation: continuation, session: session, downloads: downloads, presentOnPhone: false)
            await audio.waitForPreparation(of: player)
            guard session.isActive, audio.store === player, player.hasPreparedContent, player.state == .loaded else { return .failure }
            return .success
        }

        private static func downloadedAlbums(_ records: [OfflineDownloadRecord]) -> [MediaItem] {
            let tracks = records.compactMap { record -> MediaItem? in
                let item = record.item
                return item.type == .audio && ContentRatingGate.admitsStored(item) ? item : nil
            }
            return MediaPageLoader.unique(tracks.compactMap { track in
                guard let id = track.albumID, let name = track.album else { return nil }
                return MediaItem(albumArtist: track.albumArtist, artists: track.artists, id: id, name: name, type: .musicAlbum)
            })
        }

        private static func downloadedAlbumTracks(_ records: [OfflineDownloadRecord], albumID: String) -> [OfflineDownloadRecord] {
            records.filter { $0.item.type == .audio && $0.item.albumID == albumID && ContentRatingGate.admitsStored($0.item) }
                .sorted {
                    let lhs = $0.item
                    let rhs = $1.item
                    return (lhs.parentIndexNumber ?? 0, lhs.indexNumber ?? 0, lhs.displayTitle) <
                        (rhs.parentIndexNumber ?? 0, rhs.indexNumber ?? 0, rhs.displayTitle)
                }
        }

        static func matches(_ items: [MediaItem], title: String, artist: String?, identifier: String?, types: [MediaItemType]) -> [MediaItem] {
            let eligible = MediaPageLoader.unique(items).filter { item in
                guard let type = item.type, types.contains(type), item.id != nil else { return false }
                return ContentRatingGate.admitsStored(item)
            }
            if let identifier, let exact = eligible.first(where: { $0.id == identifier }) {
                return [exact]
            }
            return Array(eligible.filter { item in
                guard item.displayTitle.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else { return false }
                guard let artist, !artist.isEmpty else { return true }
                let names = item.artists + item.bookAuthorNames + [item.albumArtist].compactMap { $0 }
                return names.contains { $0.compare(artist, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            }.prefix(5))
        }

        private static func siriItem(_ item: MediaItem) -> INMediaItem? {
            guard let id = item.id else { return nil }
            let type: INMediaItemType = switch item.type {
            case .audio: .song
            case .audioBook: .audioBook
            case .musicAlbum: .album
            default: .unknown
            }
            return INMediaItem(identifier: id, title: item.displayTitle, type: type, artwork: nil, artist: item.albumArtist ?? item.artists.first ?? item.bookAuthorNames.first)
        }
    }
#endif
