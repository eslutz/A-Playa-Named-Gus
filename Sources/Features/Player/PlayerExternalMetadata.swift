import AVFoundation

/// System player metadata: feeds AVKit's built-in title/info chrome (the tvOS info
/// panel, the visionOS player header, iOS/macOS title displays) so the system surface
/// presents the item like first-party content instead of an untitled stream.
extension MediaItem {
    var externalPlayerMetadata: [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        if let series = seriesName {
            items.append(.gusMetadata(identifier: .commonIdentifierTitle, value: series))
            let subtitle = episodeLocator.map { "\($0) · \(displayTitle)" } ?? displayTitle
            items.append(.gusMetadata(identifier: .iTunesMetadataTrackSubTitle, value: subtitle))
        } else {
            items.append(.gusMetadata(identifier: .commonIdentifierTitle, value: displayTitle))
        }
        if let overview, !overview.isEmpty {
            items.append(.gusMetadata(identifier: .commonIdentifierDescription, value: overview))
        }
        return items
    }
}

private extension AVMetadataItem {
    static func gusMetadata(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }
}
