import SwiftUI

/// A poster tile: artwork on top, title (and optional subtitle) beneath.
///
/// Uses only system styling — rounded rectangle clip, Material placeholder, Dynamic Type
/// captions, and a platform-appropriate hover/focus effect — so it feels native on each OS.
struct PosterCard: View {
    let title: String
    var subtitle: String?
    var statusItem: MediaItem? = nil
    let imageURL: URL?
    var aspectRatio: CGFloat = 2.0 / 3.0
    var iPhoneAspectRatio: CGFloat? = nil
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var widthClass
    #endif
    var placeholderSymbol: String = "film"
    var fallbackURLs: [URL] = []
    var onExhausted: (() async -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkTile(url: imageURL, aspectRatio: resolvedAspectRatio, placeholderSymbol: placeholderSymbol, fallbackURLs: fallbackURLs, onExhausted: onExhausted)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .posterHoverEffect()
                .gusTVArtworkStatus(item: statusItem)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .gusTVPosterTitle()
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                statusCaption
            }
            .gusTVCardCaption()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .gusTVPosterStatusValue(item: statusItem)
    }

    private var usesIPhoneLayout: Bool {
        #if os(iOS)
            widthClass == .compact
        #else
            false
        #endif
    }

    private var resolvedAspectRatio: CGFloat {
        usesIPhoneLayout ? iPhoneAspectRatio ?? aspectRatio : aspectRatio
    }

    @ViewBuilder private var statusCaption: some View {
        if usesIPhoneLayout {
            if statusItem?.userData?.isWatched == true {
                Text("Watched").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text(statusItem?.userData?.isWatched == true ? String(localized: "Watched") : " ")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityHidden(statusItem?.userData?.isWatched != true)
        }
    }

    private var accessibilityLabel: Text {
        if let subtitle {
            Text("\(title), \(subtitle)")
        } else {
            Text(title)
        }
    }
}

extension PosterCard {
    private static func artworkAspectRatio(for item: MediaItem) -> CGFloat {
        switch item.type {
        case .musicAlbum, .musicArtist, .audio, .audioBook: 1
        case .photo, .photoAlbum: 4.0 / 3.0
        default: 2.0 / 3.0
        }
    }

    /// Convenience initializer from a media item, choosing a sensible title/subtitle.
    init(item: MediaItem, imageURL: URL?, aspectRatio: CGFloat? = nil, fallbackURLs: [URL] = [], onExhausted: (() async -> Void)? = nil) {
        let title: String
        let subtitle: String?

        if item.type == .episode, let series = item.seriesName {
            title = series
            subtitle = item.episodeLocator ?? item.name
        } else if item.type == .boxSet {
            title = item.displayTitle
            subtitle = String(localized: "Collection")
        } else {
            title = item.name ?? "Untitled"
            subtitle = item.productionYear.map(String.init)
        }

        self.init(
            title: title,
            subtitle: subtitle,
            imageURL: imageURL,
            aspectRatio: aspectRatio ?? 2.0 / 3.0,
            iPhoneAspectRatio: aspectRatio == nil ? Self.artworkAspectRatio(for: item) : nil,
            placeholderSymbol: item.artworkPlaceholderSymbol,
            fallbackURLs: fallbackURLs,
            onExhausted: onExhausted
        )
        statusItem = item
    }
}
