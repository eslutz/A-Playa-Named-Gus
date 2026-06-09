import SwiftUI

/// A poster tile: artwork on top, title (and optional subtitle) beneath.
///
/// Uses only system styling — rounded rectangle clip, Material placeholder, Dynamic Type
/// captions, and a platform-appropriate hover/focus effect — so it feels native on each OS.
struct PosterCard: View {
    let title: String
    var subtitle: String?
    let imageURL: URL?
    var aspectRatio: CGFloat = 2.0 / 3.0
    var placeholderSymbol: String = "film"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncPoster(url: imageURL, placeholderSymbol: placeholderSymbol)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .posterHoverEffect()

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
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
    /// Convenience initializer from a media item, choosing a sensible title/subtitle.
    init(item: MediaItem, imageURL: URL?, aspectRatio: CGFloat = 2.0 / 3.0) {
        let title: String
        let subtitle: String?

        if item.type == .episode, let series = item.seriesName {
            title = series
            subtitle = item.episodeLocator ?? item.name
        } else {
            title = item.name ?? "Untitled"
            subtitle = item.productionYear.map(String.init)
        }

        self.init(
            title: title,
            subtitle: subtitle,
            imageURL: imageURL,
            aspectRatio: aspectRatio
        )
    }
}
