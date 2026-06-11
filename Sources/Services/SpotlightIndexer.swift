import Foundation
import OSLog

// CoreSpotlight imports on tvOS but CSSearchableIndex is marked unavailable
// there, so the gate needs the explicit os check.
#if canImport(CoreSpotlight) && !os(tvOS)
    import CoreSpotlight
    import UniformTypeIdentifiers
#endif

/// Donates browsed media items to Core Spotlight so library content surfaces in
/// system search; tapping a result deep-links into the item via `ContentLink`.
/// This is also the indexing foundation the roadmap's Apple Intelligence library
/// assistant builds on (grounded, on-device library search).
///
/// Identifiers carry `server|user|item` so results from a signed-out or switched
/// account are refused at continuation time, and sign-out removes that account's
/// whole domain. watchOS and tvOS have no Core Spotlight indexing; everything
/// no-ops there.
enum SpotlightIndexer {
    /// Pure identifier codec, separated for testability.
    enum Identifier {
        static func encode(serverID: String, userID: String, itemID: String) -> String {
            "\(serverID)|\(userID)|\(itemID)"
        }

        static func decode(_ identifier: String) -> (serverID: String, userID: String, itemID: String)? {
            let parts = identifier.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
            return (parts[0], parts[1], parts[2])
        }

        static func domain(serverID: String, userID: String) -> String {
            "\(serverID)|\(userID)"
        }
    }

    /// Resolves a tapped Spotlight result to a content link, refusing identifiers from
    /// another account.
    static func contentLink(
        forSearchableItemIdentifier identifier: String,
        currentServerID: String?,
        currentUserID: String?
    ) -> ContentLink? {
        guard let decoded = Identifier.decode(identifier) else { return nil }
        if let currentServerID, let currentUserID,
           decoded.serverID != currentServerID || decoded.userID != currentUserID
        {
            return nil
        }
        return .item(id: decoded.itemID)
    }

    #if canImport(CoreSpotlight) && !os(tvOS)
        private static let logger = Logger(category: .home)

        /// Donates items in the background; restricted items (family safety) are
        /// filtered by the callers, which donate exactly what they display.
        static func index(_ items: [MediaItem], serverID: String, userID: String) {
            let searchable: [CSSearchableItem] = items.compactMap { item in
                guard let id = item.id, let type = item.type else { return nil }
                let attributes = CSSearchableItemAttributeSet(contentType: contentType(for: type))
                attributes.title = item.displayTitle
                attributes.contentDescription = item.overview
                var keywords = item.genres
                if let series = item.seriesName {
                    keywords.append(series)
                }
                keywords.append(contentsOf: item.artists)
                attributes.keywords = keywords.isEmpty ? nil : keywords

                return CSSearchableItem(
                    uniqueIdentifier: Identifier.encode(serverID: serverID, userID: userID, itemID: id),
                    domainIdentifier: Identifier.domain(serverID: serverID, userID: userID),
                    attributeSet: attributes
                )
            }
            guard !searchable.isEmpty else { return }

            CSSearchableIndex.default().indexSearchableItems(searchable) { error in
                if let error {
                    logger.debug("Spotlight donation failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        /// Removes an account's donations (sign-out).
        static func deleteIndex(serverID: String, userID: String) {
            CSSearchableIndex.default().deleteSearchableItems(
                withDomainIdentifiers: [Identifier.domain(serverID: serverID, userID: userID)]
            ) { error in
                if let error {
                    logger.debug("Spotlight deindex failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        private static func contentType(for type: MediaItemType) -> UTType {
            switch type {
            case .movie, .episode, .series, .season, .video, .trailer, .liveChannel, .liveProgram, .recording:
                return .movie
            case .audio, .audioBook, .musicAlbum, .musicArtist, .playlist:
                return .audio
            case .book:
                return .epub
            case .photo:
                return .image
            case .collectionFolder, .folder, .unknown:
                return .content
            }
        }
    #else
        static func index(_ items: [MediaItem], serverID: String, userID: String) {}
        static func deleteIndex(serverID: String, userID: String) {}
    #endif
}
